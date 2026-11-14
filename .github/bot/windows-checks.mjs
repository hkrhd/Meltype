// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd
// 変更されたファイルから、その実行で必要な Windows 検証を選ぶ。
import { appendFileSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const checks = { dotnet: false, tip: false, mozc: false, scan: false, installer: false };
const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
if (process.env.GITHUB_EVENT_NAME === 'workflow_dispatch') {
  for (const name of Object.keys(checks)) checks[name] = true;
} else {
  const base = process.env.GITHUB_EVENT_NAME === 'pull_request' ? event.pull_request.base.sha : event.before;
  if (!/^[0-9a-f]{40}$/.test(base ?? '')) throw new Error('比較元のコミット SHA が不正です。');
  let files;
  if (/^0{40}$/.test(base)) {
    files = execFileSync('git', ['ls-tree', '-r', '--name-only', '-z', 'HEAD'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  } else {
    execFileSync('git', ['fetch', '--no-tags', '--depth=1', 'origin', base], { stdio: 'inherit' });
    // PR は checkout が作るマージ結果と base を比較する。リネームは旧名・新名の両方で判定する。
    files = execFileSync('git', ['diff', '--name-only', '--no-renames', '-z', base, 'HEAD'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  }
  for (const file of files.split('\0').filter(Boolean)) {
    if (/^\.github\/(workflows\/fork-windows\.yml|bot\/windows-checks\.mjs)$/.test(file)
        || file === 'tests/fork/windows-checks.test.mjs') {
      for (const name of Object.keys(checks)) checks[name] = true;
    }
    if (/^src\/(Meltype\.(Core|Core\.Tests|Mac\.Native|Windows|Windows\.Tests)\/|Directory\.Build\.)/.test(file)
        || /^(dictionaries\/|tests\/fork\/Core\/)/.test(file)
        || /^(Meltype\.sln|nuget\.config|global\.json|Directory\.(Build|Packages)\.(props|targets))$/.test(file)) checks.dotnet = true;
    if (file.startsWith('native/tip/')) { checks.tip = true; checks.dotnet = true; }
    if (file.startsWith('native/mozc/')) checks.mozc = true;
    if (/^tools\/(Scan-WindowsPackage|Test-WindowsPackageScan)\.ps1$/.test(file)) checks.scan = true;
    if (/^packaging\//.test(file) || file === 'tools/Test-SetupIme.ps1'
        || /^(Build-Package|Install-Meltype|Uninstall-Meltype)\.ps1$/.test(file)
        || /^(LICENSE|THIRD-PARTY-NOTICES\.md)$/.test(file)) checks.installer = true;
  }
}
for (const [name, enabled] of Object.entries(checks)) {
  appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${enabled}\n`);
}
console.log('実行する Windows 検証:', checks);
