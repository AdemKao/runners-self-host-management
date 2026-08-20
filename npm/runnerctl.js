#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const frontend = path.join(__dirname, '..', 'runnerctl');
const result = spawnSync('bash', [frontend, ...process.argv.slice(2)], {
  stdio: 'inherit',
});

if (result.error) {
  console.error(`[runnerctl] Failed to start Bash: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
