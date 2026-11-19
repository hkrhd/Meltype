# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Yukishiro

# Meltype の更新を確認して、新しい版があればダウンロードしておく (Meltype が定期的に呼ぶ)。
#   update.ps1 -Repository hkrhd/Meltype -CurrentVersion 1.6.0-hkrhd.2913.g… -Directory %LOCALAPPDATA%\Meltype\update -Prerelease
# このフォークの配布はすべてプレリリースで、-Prerelease が無ければ更新しない。
# タグ hkrhd-build-<ビルド番号>-… のうち、インストーラー (Meltype-<版>-setup.exe) があり、ビルド番号が今の版
# (1.6.0-hkrhd.2913.g… の 2913) より大きい最新のリリースから、インストーラーを <Directory> にダウンロードし、
# <Directory>\ready.txt に「版 TAB インストーラーの場所」を書く。インストールは Meltype がインストーラーを /VERYSILENT で実行して行う。
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
        $installer = @($candidate.assets | Where-Object { $_.name -like 'Meltype-*-setup.exe' }) | Select-Object -First 1
        if ($installer -and $number -gt $build) { $asset = $installer; $build = $number }
    }
    if (-not $asset) { Write-Output 'none'; exit 0 }
    $latest = $asset.name -replace '^Meltype-(.+)-setup\.exe$', '$1'

    $setup = Join-Path $Directory $asset.name
    $ready = Join-Path $Directory 'ready.txt'
    # 1.6.0 以前の Meltype が書いた ready.txt (2 列目が zip を展開したフォルダー) は、同じ版でもダウンロードし直す
    if ((Test-Path -LiteralPath $ready) -and ((Get-Content -LiteralPath $ready -Raw).Trim() -eq "$latest`t$setup") -and (Test-Path -LiteralPath $setup -PathType Leaf)) { Write-Output "ready $latest"; exit 0 }

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $download = "$setup.download"
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ 'User-Agent' = 'Meltype-Updater' } -OutFile $download -UseBasicParsing -TimeoutSec 600

    # GitHub が公開している SHA-256 と同じか (ダウンロードの途中で壊れていないか) を確かめる。
    if ($asset.digest -like 'sha256:*') {
        $expected = $asset.digest.Substring(7).ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { Remove-Item -LiteralPath $download -Force; Write-Output 'error ダウンロードしたインストーラーのハッシュが違います'; exit 0 }
    }
    Move-Item -LiteralPath $download -Destination $setup -Force
    # インターネットから落とした印 (Zone.Identifier) を外す (実行したときの SmartScreen の確認を出さない)
    Unblock-File -LiteralPath $setup -ErrorAction SilentlyContinue

    # 前の版のインストーラーと、1.6.0 以前の Meltype が展開した zip を片付ける
    Get-ChildItem -LiteralPath $Directory | Where-Object { $_.FullName -ne $setup -and $_.Name -notin 'ready.txt', 'applying.txt', 'install.log' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($ready, "$latest`t$setup", (New-Object Text.UTF8Encoding $false))
    Write-Output "ready $latest"
}
catch {
    Write-Output "error $($_.Exception.Message)"
}
