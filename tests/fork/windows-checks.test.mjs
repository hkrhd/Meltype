// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';

const script = resolve('.github/bot/windows-checks.mjs');

test('変更した対象の検証だけを選び、手動実行ではすべて検証する', () => {
  const root = mkdtempSync(join(tmpdir(), 'meltype-windows-checks-'));
  const repo = join(root, 'repo');
  mkdirSync(repo);
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const put = (file, content = 'fixture\n') => {
    mkdirSync(dirname(join(repo, file)), { recursive: true });
    writeFileSync(join(repo, file), content);
  };
  function select(eventName, payload) {
    const eventPath = join(root, 'event.json');
    const output = join(root, 'output');
    writeFileSync(eventPath, JSON.stringify(payload));
    writeFileSync(output, '');
    execFileSync(process.execPath, [script], {
      cwd: repo,
      env: { ...process.env, GITHUB_EVENT_NAME: eventName, GITHUB_EVENT_PATH: eventPath, GITHUB_OUTPUT: output },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return readFileSync(output, 'utf8').trim().split('\n').filter(line => line.endsWith('=true')).map(line => line.split('=')[0]);
  }
  try {
    git('init', '-q');
    git('config', 'user.name', 'Workflow test');
    git('config', 'user.email', 'test@example.invalid');
    git('remote', 'add', 'origin', repo);
    put('README.md');
    git('add', '.'); git('commit', '-qm', 'initial');
    const all = ['dotnet', 'tip', 'mozc', 'scan', 'installer'];
    assert.deepEqual(select('workflow_dispatch', {}), all);
    for (const [file, expected] of [
      ['tools/mcfly-terms.py', []],
      ['tests/fork/mac/check-inputs.sh', []],
      ['src/Meltype.Linux/Program.cs', []],
      ['src/Meltype.Windows/Program.cs', ['dotnet']],
      ['tests/fork/Core/ConversionTests.cs', ['dotnet']],
      ['src/Directory.Build.props', ['dotnet']],
      ['nuget.config', ['dotnet']],
      ['native/tip/TextService.cpp', ['dotnet', 'tip']],
      ['native/mozc/merge-ut-dictionary.py', ['mozc']],
      ['tools/Scan-WindowsPackage.ps1', ['scan']],
      ['packaging/Meltype.iss', ['installer']],
      ['Build-Package.ps1', ['installer']],
      ['.github/workflows/windows.yml', all],
    ]) {
      const before = git('rev-parse', 'HEAD');
      put(file);
      git('add', '.'); git('commit', '-qm', 'change');
      assert.deepEqual(select('push', { before }), expected, file);
    }
    // PR の base に対する変更も検出し、関係するファイルの削除・移動でも検証を残す。
    const before = git('rev-parse', 'HEAD');
    renameSync(join(repo, 'src/Meltype.Windows/Program.cs'), join(repo, 'moved.txt'));
    rmSync(join(repo, 'packaging/Meltype.iss'));
    git('add', '-A'); git('commit', '-qm', 'move and delete');
    assert.deepEqual(select('pull_request', { pull_request: { base: { sha: before } } }), ['dotnet', 'installer']);
    assert.deepEqual(select('push', { before: '0'.repeat(40) }), all);
    assert.throws(() => select('push', { before: 'invalid' }));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
