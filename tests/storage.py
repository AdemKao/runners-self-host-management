#!/usr/bin/env python3
"""Regression tests for bounded disk inspection and scoped maintenance."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

STORAGE = Path(__file__).resolve().parent.parent / 'bin' / 'runnerctl-storage.py'

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location('runnerctl_storage', STORAGE)
storage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(storage)


def policy(directory, **overrides):
    data = {'schema_version': 1,
            'filesystems': [{'path': str(directory), 'min_free_bytes': 0, 'min_free_inodes': 0,
                             'max_used_percent': 100}],
            'runners': [], 'log_retention_days': 1}
    data.update(overrides)
    return data


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.path = self.directory / 'policy.json'

    def write(self, data):
        self.path.write_text(json.dumps(data))

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(STORAGE), *args], capture_output=True, text=True, timeout=60)

    def test_inspect_reports_real_free_space_without_policy(self):
        result = self.run_cli('inspect', '--path', str(self.directory), '--json')
        self.assertEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertTrue(data['ready'])
        self.assertGreater(data['filesystems'][0]['total_bytes'], 0)
        self.assertIn('free_inodes', data['filesystems'][0])

    def test_check_exit_code_signals_blocked_admission(self):
        self.write(policy(self.directory, filesystems=[{'path': str(self.directory),
                                                        'min_free_bytes': 1 << 62, 'min_free_inodes': 0,
                                                        'max_used_percent': 100}]))
        result = self.run_cli('check', '--policy', str(self.path), '--json')
        self.assertEqual(result.returncode, 3)
        self.assertFalse(json.loads(result.stdout)['ready'])

    def test_used_percent_threshold_blocks_admission(self):
        self.write(policy(self.directory, filesystems=[{'path': str(self.directory), 'min_free_bytes': 0,
                                                        'min_free_inodes': 0, 'max_used_percent': 1}]))
        self.assertEqual(self.run_cli('check', '--policy', str(self.path), '--json').returncode, 3)

    def test_missing_inode_reserve_blocks_admission(self):
        self.write(policy(self.directory, filesystems=[{'path': str(self.directory), 'min_free_bytes': 0,
                                                        'min_free_inodes': 1 << 30, 'max_used_percent': 100}]))
        self.assertEqual(self.run_cli('check', '--policy', str(self.path), '--json').returncode, 3)

    def test_invalid_policies_fail_closed_without_echoing_content(self):
        secret = 'SECRET_POLICY_CONTENT'
        cases = [{'schemaVersion': 1},
                 {'schema_version': 2, 'filesystems': []},
                 {'schema_version': 1},
                 {'schema_version': 1, 'filesystems': []},
                 {'schema_version': 1, 'filesystems': [{'path': 'relative', 'min_free_bytes': 0}]},
                 {'schema_version': 1, 'filesystems': [{'path': str(self.directory) + '/../..', 'min_free_bytes': 0}]},
                 {'schema_version': 1, 'filesystems': [{'path': str(self.directory), 'min_free_bytes': -1}]},
                 {'schema_version': 1, 'filesystems': [{'path': str(self.directory), 'min_free_bytes': True}]},
                 {'schema_version': 1, 'filesystems': [{'path': str(self.directory), 'min_free_bytes': 0, 'max_used_percent': 0}]},
                 {'schema_version': 1, 'filesystems': [{'path': str(self.directory), 'min_free_bytes': 0}], 'runners': ['/etc']}]
        for data in cases:
            with self.subTest(data=data), tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as handle:
                json.dump({**data, 'note': secret}, handle)
                name = handle.name
            result = self.run_cli('inspect', '--policy', name, '--json')
            self.assertEqual(result.returncode, 1)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertNotIn(self.temp.name, result.stdout + result.stderr)
            os.unlink(name)

    def test_oversized_policy_is_refused(self):
        self.path.write_text('{"schema_version":1,"filesystems":[],"pad":"' + 'x' * 70000 + '"}')
        self.assertEqual(self.run_cli('inspect', '--policy', str(self.path), '--json').returncode, 1)

    def test_unmanaged_runner_path_is_refused(self):
        self.write(policy(self.directory, runners=[str(self.directory)]))
        result = self.run_cli('plan', '--policy', str(self.path), '--json')
        self.assertEqual(result.returncode, 1)
        self.assertIn('unmanaged-runner', result.stderr)


class SizeScanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def test_missing_workspace_is_unavailable_not_zero(self):
        result = storage.bounded_size(self.directory / 'absent', 5)
        self.assertIsNone(result['workspace_kb'])
        self.assertEqual(result['scan_status'], 'unavailable')

    def test_timeout_is_reported_and_does_not_hang(self):
        slow = self.directory / 'slow'
        slow.mkdir()
        started = time.monotonic()
        result = storage.bounded_size(slow, 0.001)
        self.assertIn(result['scan_status'], ('timeout', 'ok'))
        self.assertLess(time.monotonic() - started, 30)


class LogRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.runner = self.directory / 'runners' / 'example-runner-01'
        self.diag = self.runner / '_diag'
        self.diag.mkdir(parents=True)
        (self.runner / '.runnerctl-meta').write_text('name=example-runner-01\nrepo=example-org/example-repo\n')
        self.audit = self.directory / 'audit.jsonl'

    def logs(self, prefix, count, age_days):
        for index in range(count):
            path = self.diag / ('%s_%d.log' % (prefix, index))
            path.write_text('log line\n')
            # Older index is newer on disk, so retention is deterministic.
            when = time.time() - age_days * 86400 + index * 60
            os.utime(path, (when, when))

    def test_plan_retains_recent_logs_and_newest_of_each_kind(self):
        self.logs('Runner', 4, 30)
        self.logs('Worker', 3, 30)
        data = storage.log_plan(policy(self.directory, runners=[str(self.runner)]))
        removed = {Path(item['path']).name for item in data['files']}
        # Four Runner logs and three Worker logs: the newest two of each kind stay.
        self.assertEqual(removed, {'Runner_0.log', 'Runner_1.log', 'Worker_0.log'})
        self.assertEqual(data['reclaimable_bytes'], sum((self.diag / name).stat().st_size for name in removed))

    def test_recent_logs_are_never_planned(self):
        self.logs('Runner', 3, 0)
        data = storage.log_plan(policy(self.directory, runners=[str(self.runner)]))
        self.assertEqual(data['files'], [])

    def test_non_runner_files_are_never_planned(self):
        (self.diag / 'service.log.20xx-xx-xxT00:00:00.000Z').write_text('keep\n')
        os.utime(self.diag / 'service.log.20xx-xx-xxT00:00:00.000Z', (0, 0))
        (self.diag / '.credentials').write_text('keep\n')
        os.utime(self.diag / '.credentials', (0, 0))
        data = storage.log_plan(policy(self.directory, runners=[str(self.runner)]))
        self.assertEqual(data['files'], [])

    def test_gc_without_apply_is_preview_only(self):
        self.logs('Runner', 3, 30)
        data = policy(self.directory, runners=[str(self.runner)])
        path = self._policy(data)
        result = subprocess.run([sys.executable, str(STORAGE), 'gc', '--policy', str(path), '--json'],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Of three Runner logs only the oldest is planned; the newest two are kept.
        self.assertEqual(json.loads(result.stdout)['reclaimable_bytes'], 9)
        for item in storage.log_plan(data)['files']:
            self.assertTrue(Path(item['path']).exists())

    def test_gc_apply_requires_audit(self):
        self.logs('Runner', 3, 30)
        path = self._policy(policy(self.directory, runners=[str(self.runner)]))
        result = subprocess.run([sys.executable, str(STORAGE), 'gc', '--policy', str(path), '--apply', '--json'],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 1)
        self.assertIn('audit-required', result.stderr)
        self.assertTrue((self.diag / 'Runner_0.log').exists())

    def _policy(self, data):
        path = self.directory / ('policy-%s.json' % id(data))
        path.write_text(json.dumps(data))
        return path

    def test_gc_deletes_only_planned_logs_and_audits_each_step(self):
        self.logs('Runner', 3, 30)
        (self.diag / 'Runner_keep.log').write_text('recent\n')
        data = policy(self.directory, runners=[str(self.runner)])
        planned = {Path(i['path']).name for i in storage.log_plan(data)['files']}
        result = subprocess.run([sys.executable, str(STORAGE), 'gc', '--policy', str(self._policy(data)),
                                 '--apply', '--audit', str(self.audit), '--json'],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in planned:
            self.assertFalse((self.diag / name).exists())
        self.assertTrue((self.diag / 'Runner_keep.log').exists())
        audit = [json.loads(line) for line in self.audit.read_text().splitlines()]
        self.assertEqual(audit[0]['event'], 'gc-start')
        self.assertEqual(audit[-1]['event'], 'gc-complete')
        self.assertTrue(all('path' in item for item in audit if item['event'] == 'delete-log'))
        self.assertEqual(oct(self.audit.stat().st_mode & 0o777), '0o600')

    def test_changed_file_is_not_deleted(self):
        self.logs('Runner', 3, 30)
        data = policy(self.directory, runners=[str(self.runner)])
        stale = storage.log_plan(data)
        victim = Path(stale['files'][0]['path'])
        victim.write_text('rewritten by another process\n')
        original = storage.log_plan

        def replan(_data):
            # Reuse the earlier plan so apply_gc validates identity against a
            # file that has since been replaced by a different inode.
            return stale

        storage.log_plan = replan
        self.addCleanup(setattr, storage, 'log_plan', original)
        with self.assertRaises(storage.Refused):
            storage.apply_gc(data, str(self.audit))
        self.assertTrue(victim.exists())

    def test_shared_default_builder_is_refused(self):
        for name in ('default', 'desktop-linux'):
            with self.subTest(name=name), self.assertRaises(storage.Refused):
                storage.builder_settings(policy(
                    self.directory, runners=[str(self.runner)],
                    builder={'name': name, 'docker_config': str(self.directory / 'docker'),
                             'unused_hours': 24, 'max_used_gib': 4}))

    def test_named_builder_is_planned_but_not_executed_without_policy(self):
        data = policy(self.directory, runners=[str(self.runner)],
                      builder={'name': 'example-builder', 'docker_config': str(self.directory),
                               'unused_hours': 24, 'max_used_gib': 4})
        self.assertEqual(storage.builder_settings(data)['name'], 'example-builder')
        with self.assertRaises(storage.Refused):
            storage.builder_settings(policy(self.directory, runners=[str(self.runner)],
                                           builder={'name': 'bad name', 'docker_config': str(self.directory)}))

    def test_no_policy_builder_means_no_builder_command(self):
        self.logs('Runner', 3, 30)
        data = policy(self.directory, runners=[str(self.runner)])
        self.assertIsNone(storage.log_plan(data)['builder'])


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.runner = Path(self.temp.name) / 'runners' / 'example-runner-01'
        self.workspace = self.runner / '_work' / 'example-org' / 'example-repo'
        self.workspace.mkdir(parents=True)
        (self.runner / '.runnerctl-meta').write_text('name=example-runner-01\n')
        (self.workspace / 'artifact').mkdir()
        (self.workspace / 'file.txt').write_text('output\n')

    def test_preview_does_not_delete(self):
        result = storage.workspace_clean(self.runner, self.workspace, 5, False)
        self.assertEqual(result['status'], 'preview')
        self.assertTrue((self.workspace / 'file.txt').exists())

    def test_apply_removes_contents_but_keeps_the_workspace_directory(self):
        self.assertEqual(storage.workspace_clean(self.runner, self.workspace, 5, True)['status'], 'cleaned')
        self.assertTrue(self.workspace.is_dir())
        self.assertEqual(list(self.workspace.iterdir()), [])

    def test_paths_outside_the_runner_work_tree_are_refused(self):
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        with self.assertRaises(storage.Refused):
            storage.workspace_clean(self.runner, outside, 5, True)
        with self.assertRaises(storage.Refused):
            storage.workspace_clean(Path(self.temp.name), self.workspace, 5, True)
        self.assertTrue((outside).exists())

    def test_unmanaged_runner_is_refused(self):
        unmanaged = Path(self.temp.name) / 'not-a-runner'
        unmanaged.mkdir()
        with self.assertRaises(storage.Refused):
            storage.workspace_clean(unmanaged, unmanaged, 5, True)


class ErrorTests(unittest.TestCase):
    def test_errors_do_not_leak_paths_or_tracebacks(self):
        result = subprocess.run([sys.executable, str(STORAGE), 'plan', '--policy', '/nonexistent/policy.json'],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('Traceback', result.stdout + result.stderr)
        self.assertNotIn('/nonexistent', result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stderr)['error'], 'storage-operation-failed')


if __name__ == '__main__':
    unittest.main()