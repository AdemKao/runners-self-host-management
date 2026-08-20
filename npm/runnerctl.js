#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const script = path.join(__dirname, '..', 'bin', 'runnerctl');
const result = spawnSync('bash', [script, ...process.argv.slice(2)], {
  stdio: 'inherit',
});

if (result.error) {
  console.error(`[runnerctl] Failed to start Bash: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
