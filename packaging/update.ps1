# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Yukishiro

# Meltype の更新を確認して、新しい版があればダウンロードして展開しておく (Meltype が定期的に呼ぶ)。
#   update.ps1 -Repository hkrhd/Meltype -CurrentVersion 1.6.0-hkrhd.2913.g… -Directory %LOCALAPPDATA%\Meltype\update -Prerelease
# このフォークの配布はすべてプレリリースで、-Prerelease が無ければ更新しない。
# タグ hkrhd-build-<ビルド番号>-… のうち、Windows 版の zip (Meltype-<版>-windows.zip) があり、ビルド番号が今の版
# (1.6.0-hkrhd.2913.g… の 2913) より大きい最新のリリースを、<Directory>\<版> に展開し、<Directory>\ready.txt に
# 「版 TAB 展開した場所」を書く。インストールは Meltype が install.ps1 を呼んで行う。
# 結果は標準出力に 1 行で返す: none (更新なし) / ready <版> / error <理由>

param(
    [Parameter(Mandatory)] [string]$Repository,
    [Parameter(Mandatory)] [string]$CurrentVersion,
    [Parameter(Mandatory)] [string]$Directory,
    [switch]$Prerelease,
    # テストでは手元のサーバーの一覧を渡す。
    [string]$ReleasesUri = "https://api.github.com/repos/$Repository/releases?per_page=30"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# 結果を UTF-8 で返す (Meltype が UTF-8 として読む)
[Console]::OutputEncoding = [Text.Encoding]::UTF8

try {
    if (-not $Prerelease) { Write-Output 'none'; exit 0 }
    if ($CurrentVersion -notmatch '[-.]hkrhd\.(\d+)\.') { Write-Output "error 今の版 $CurrentVersion からビルド番号を読めません"; exit 0 }
    $build = [long]$Matches[1]
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'Meltype-Updater'; 'Accept' = 'application/vnd.github+json' }
    $releases = Invoke-RestMethod -Uri $ReleasesUri -Headers $headers -TimeoutSec 30
    $asset = $null
    foreach ($candidate in $releases) {
        if ($candidate.draft -or $candidate.tag_name -notmatch '^hkrhd-build-(\d+)-') { continue }
        $number = [long]$Matches[1]
        $windows = @($candidate.assets | Where-Object { $_.name -like 'Meltype-*-windows.zip' }) | Select-Object -First 1
        if ($windows -and $number -gt $build) { $asset = $windows; $build = $number }
    }
    if (-not $asset) { Write-Output 'none'; exit 0 }
    $latest = $asset.name -replace '^Meltype-(.+)-windows\.zip$', '$1'

    $target = Join-Path $Directory $latest
    $ready = Join-Path $Directory 'ready.txt'
    if ((Test-Path -LiteralPath $ready) -and ((Get-Content -LiteralPath $ready -Raw) -like "$latest`t*")) { Write-Output "ready $latest"; exit 0 }

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $zip = Join-Path $Directory $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ 'User-Agent' = 'Meltype-Updater' } -OutFile $zip -UseBasicParsing -TimeoutSec 600

    # GitHub が公開している SHA-256 と同じか (ダウンロードの途中で壊れていないか) を確かめる。
    if ($asset.digest -like 'sha256:*') {
        $expected = $asset.digest.Substring(7).ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { Remove-Item -LiteralPath $zip -Force; Write-Output 'error ダウンロードした zip のハッシュが違います'; exit 0 }
    }

    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-Path -LiteralPath (Join-Path $target 'install.ps1'))) { Write-Output 'error zip に install.ps1 がありません'; exit 0 }

    # 古い版の展開先を片付ける
    Get-ChildItem -LiteralPath $Directory -Directory | Where-Object { $_.Name -ne $latest } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($ready, "$latest`t$target", (New-Object Text.UTF8Encoding $false))
    Write-Output "ready $latest"
}
catch {
    Write-Output "error $($_.Exception.Message)"
}
