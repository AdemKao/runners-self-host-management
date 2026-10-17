#!/usr/bin/env python3
"""Bounded disk inspection, admission and opt-in scoped maintenance (Python 3.8+)."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time


class Refused(Exception):
    pass


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise Refused('invalid-policy-integer')
    return value


def safe_path(value):
    # Accept only absolute, traversal-free, already-real paths. Callers compare
    # resolved paths for containment, so an operator-chosen symlinked prefix
    # (/tmp on macOS, /srv on some hosts) does not become a false refusal.
    if not isinstance(value, str) or not value.startswith('/') or '\n' in value or '\0' in value:
        raise Refused('absolute-path-required')
    path = Path(value)
    if '..' in path.parts:
        raise Refused('path-traversal-refused')
    resolved = Path(os.path.realpath(path))
    if path != resolved and path.is_symlink():
        raise Refused('symlinked-target-refused')
    return resolved


def policy(path):
    source = safe_path(str(Path(path).absolute()))
    if source.stat().st_size > 65536:
        raise Refused('policy-too-large')
    data = json.loads(source.read_text())
    if not isinstance(data, dict) or type(data.get('schema_version')) is not int or data['schema_version'] != 1:
        raise Refused('unsupported-policy')
    paths = data.get('filesystems')
    if not isinstance(paths, list) or not 1 <= len(paths) <= 16:
        raise Refused('filesystems-required')
    for item in paths:
        safe_path(item['path'])
        integer(item['min_free_bytes'])
        integer(item.get('min_free_inodes', 10000))
        if not 1 <= integer(item.get('max_used_percent', 85), 1) <= 100:
            raise Refused('invalid-used-percent')
    runners = data.get('runners', [])
    if not isinstance(runners, list) or len(runners) > 100:
        raise Refused('invalid-runner-list')
    for value in runners:
        runner = safe_path(value)
        if not (runner / '.runnerctl-meta').is_file():
            raise Refused('unmanaged-runner')
    integer(data.get('log_retention_days', 14), 1)
    return data


def inspect_filesystems(items):
    rows = []
    for item in items:
        path = safe_path(item['path'])
        usage = shutil.disk_usage(path)
        fs = os.statvfs(path)
        percent = round(100 * usage.used / usage.total, 2)
        inode_free = fs.f_favail if fs.f_files else None
        ready = (usage.free >= item.get('min_free_bytes', 0)
                 and percent < item.get('max_used_percent', 100)
                 and (inode_free is None or inode_free >= item.get('min_free_inodes', 0)))
        rows.append({'path': str(path), 'total_bytes': usage.total, 'free_bytes': usage.free,
                     'used_percent': percent, 'free_inodes': inode_free, 'ready': ready})
    return {'schema_version': 1, 'sampled_at': int(time.time()), 'ready': all(r['ready'] for r in rows),
            'filesystems': rows}


def bounded_size(path, timeout):
    process = subprocess.Popen(['du', '-sk', str(path)], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        out, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # Stop the whole measurement process group so an abandoned scan cannot keep running.
        with contextlib.suppress(OSError):
            os.killpg(process.pid, signal.SIGKILL)
        with contextlib.suppress(subprocess.SubprocessError, ValueError):
            process.communicate(timeout=5)
        return {'workspace_kb': None, 'scan_status': 'timeout'}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {'workspace_kb': None, 'scan_status': 'unavailable'}
    if process.returncode != 0:
        return {'workspace_kb': None, 'scan_status': 'unavailable'}
    try:
        return {'workspace_kb': int(out.split()[0]), 'scan_status': 'ok'}
    except (IndexError, ValueError):
        return {'workspace_kb': None, 'scan_status': 'unavailable'}


def log_plan(data):
    cutoff = time.time() - data.get('log_retention_days', 14) * 86400
    candidates = []
    for value in data.get('runners', []):
        directory = safe_path(value) / '_diag'
        if not directory.exists():
            continue
        safe_path(str(directory))
        logs = []
        with os.scandir(directory) as entries:
            for entry in entries:
                if len(logs) >= 10000:
                    raise Refused('too-many-log-files')
                if re.fullmatch(r'(Runner|Worker)_[A-Za-z0-9_.-]+\.log', entry.name) and entry.is_file(follow_symlinks=False):
                    info = entry.stat(follow_symlinks=False)
                    logs.append((Path(entry.path), info))
        # Retain the newest two files of each kind, irrespective of age.
        protected = set()
        for kind in ('Runner_', 'Worker_'):
            protected.update(p for p, _ in sorted((r for r in logs if r[0].name.startswith(kind)),
                                                  key=lambda r: r[1].st_mtime, reverse=True)[:2])
        for path, info in logs:
            if path not in protected and info.st_mtime < cutoff:
                candidates.append({'path': str(path), 'bytes': info.st_size, 'inode': info.st_ino,
                                   'device': info.st_dev, 'mtime_ns': info.st_mtime_ns,
                                   'reason': 'expired-runner-diagnostic'})
    return {'schema_version': 1, 'files': candidates, 'reclaimable_bytes': sum(r['bytes'] for r in candidates),
            'excluded': ['volumes', 'images', 'package-caches', 'workspaces', 'backups', 'containerd'],
            'builder': builder_settings(data)}


def builder_settings(data):
    value = data.get('builder')
    if value is None:
        return None
    if not isinstance(value, dict) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', value.get('name', '')):
        raise Refused('invalid-builder')
    if value['name'] in ('default', 'desktop-linux'):
        raise Refused('shared-default-builder-refused')
    config = safe_path(value['docker_config'])
    hours = integer(value.get('unused_hours', 168), 24)
    budget = integer(value.get('max_used_gib', 4), 1)
    return {'name': value['name'], 'docker_config': str(config), 'unused_hours': hours, 'max_used_gib': budget}


@contextlib.contextmanager
def lock(path):
    path = safe_path(str(Path(path).absolute()))
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Refused('maintenance-already-running')
        yield


def apply_gc(data, audit_path):
    audit = safe_path(str(Path(audit_path).absolute()))
    # Require an audit destination before any deletion. Retain it under operator policy.
    with lock(str(audit) + '.lock'):
        fd = os.open(audit, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'a') as stream:
            def record(event, **fields):
                stream.write(json.dumps({'at': int(time.time()), 'event': event, **fields}) + '\n')
                stream.flush()
                os.fsync(stream.fileno())
            plan = log_plan(data)
            record('gc-start', count=len(plan['files']))
            removed = 0
            for item in plan['files']:
                path = safe_path(item['path'])
                info = path.lstat()
                if not stat.S_ISREG(info.st_mode) or (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_size) != (item['device'], item['inode'], item['mtime_ns'], item['bytes']):
                    raise Refused('log-changed-since-plan')
                record('delete-log', path=str(path), bytes=info.st_size)
                path.unlink()
                removed += 1
            builder = plan['builder']
            if builder:
                # The policy explicitly opts into one named builder. Never run system/image/volume prune.
                args = ['docker', '--config', builder['docker_config'], 'buildx', '--builder', builder['name'],
                        'prune', '--filter', 'until=%dh' % builder['unused_hours'],
                        '--max-used-space', '%dGB' % builder['max_used_gib'], '--force']
                record('builder-gc-start', builder=builder['name'])
                try:
                    subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
                except (OSError, subprocess.SubprocessError):
                    record('builder-gc-failed', builder=builder['name'])
                    raise Refused('builder-gc-failed')
            record('gc-complete', removed_files=removed)
            return {'removed_files': removed, 'builder': builder['name'] if builder else None}


def workspace_clean(runner, workspace, timeout, apply):
    root = safe_path(str(Path(runner).absolute()))
    path = safe_path(str(Path(workspace).absolute()))
    work = root / '_work'
    try:
        depth = len(path.relative_to(work).parts)
    except ValueError:
        raise Refused('workspace-outside-runner')
    if not (root / '.runnerctl-meta').is_file() or depth != 2:
        raise Refused('workspace-outside-runner')
    if not path.is_dir():
        return {'status': 'absent'}
    if not apply:
        return {'status': 'preview', 'workspace': str(path)}
    # A fresh process bounds traversal/removal. Do not follow a workspace symlink.
    code = "import os,shutil,sys; p=sys.argv[1]; [(shutil.rmtree(e.path) if e.is_dir(follow_symlinks=False) else os.unlink(e.path)) for e in os.scandir(p)]"
    try:
        with lock(str(root / '.runnerctl-cleanup.lock')):
            subprocess.run([sys.executable, '-c', code, str(path)], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {'status': 'timeout-partial'}
    return {'status': 'cleaned'}


def main(argv=None):
    parser = argparse.ArgumentParser(description='Disk admission and scoped maintenance. No global prune or volume deletion.')
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('inspect', 'check', 'plan', 'gc'):
        cmd = sub.add_parser(name)
        cmd.add_argument('--policy', required=name != 'inspect')
        cmd.add_argument('--json', action='store_true')
        if name == 'inspect':
            cmd.add_argument('--path', action='append')
        if name == 'gc':
            cmd.add_argument('--apply', action='store_true', help='Required to mutate; otherwise only preview')
            cmd.add_argument('--audit', help='Required with --apply; absolute audit file')
    size = sub.add_parser('_size')
    size.add_argument('path')
    size.add_argument('--timeout', type=float, default=5)
    clean = sub.add_parser('_workspace')
    clean.add_argument('runner')
    clean.add_argument('workspace')
    clean.add_argument('--timeout', type=float, default=30)
    clean.add_argument('--apply', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.command == '_size':
            if not 0 < args.timeout <= 300:
                raise Refused('invalid-timeout')
            output = bounded_size(safe_path(args.path), args.timeout)
        elif args.command == '_workspace':
            if not 0 < args.timeout <= 300:
                raise Refused('invalid-timeout')
            output = workspace_clean(args.runner, args.workspace, args.timeout, args.apply)
        else:
            data = policy(args.policy) if args.policy else {'filesystems': [{'path': p} for p in (args.path or ['/'])]}
            if args.command in ('inspect', 'check'):
                output = inspect_filesystems(data['filesystems'])
            elif args.command == 'gc' and args.apply:
                if not args.audit:
                    raise Refused('audit-required')
                output = apply_gc(data, args.audit)
            else:
                output = log_plan(data)
        if getattr(args, 'json', False) or args.command.startswith('_'):
            print(json.dumps(output))
        else:
            print(json.dumps(output, indent=2))
        return 3 if args.command == 'check' and not output['ready'] else 0
    except (Refused, OSError, ValueError, KeyError, TypeError) as error:
        # Never dump policy content, environment, subprocess output or traceback.
        print(json.dumps({'error': str(error) if isinstance(error, Refused) else 'storage-operation-failed'}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
