#!/usr/bin/env bash
# upstream の版と、このフォークのビルド番号・コミットを両方識別する。
set -euo pipefail
cd "$(dirname "$0")/.."
base=$(git describe --tags --match 'v[0-9]*' --abbrev=0 HEAD)
# 通しのビルド番号 (CFBundleVersion・リリースタグと同じ) で、Windows・Mac の自動更新が新旧を比べる。
count=$(git rev-list --count HEAD)
revision=$(git rev-parse --short=12 HEAD)
version=${base#v}
if [[ "$version" == *-* ]]; then version="$version.hkrhd.$count.g$revision";
else version="$version-hkrhd.$count.g$revision"; fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then version="$version.dirty"; fi
printf '%s\n' "$version"
