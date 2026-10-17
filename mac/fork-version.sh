#!/usr/bin/env bash
# upstream の版と、このフォークの変更数・コミットを両方識別する。
set -euo pipefail
cd "$(dirname "$0")/.."
base=$(git describe --tags --match 'v[0-9]*' --abbrev=0 HEAD)
count=$(git rev-list --count "$base..HEAD")
revision=$(git rev-parse --short=12 HEAD)
version=${base#v}
if [[ "$version" == *-* ]]; then version="$version.hkrhd.$count.g$revision";
else version="$version-hkrhd.$count.g$revision"; fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then version="$version.dirty"; fi
printf '%s\n' "$version"
