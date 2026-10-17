#!/usr/bin/env bash
# ビルドした実エンジンを一時辞書・一時学習データで検証する。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="${1:-$here/build/Meltype.app}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
for live in false true; do
    mkdir "$temporary/$live"
    printf 'かん\t燗\nしの\t紫乃\n' > "$temporary/$live/userdict.txt"
    printf '{"LiveConversion":%s}\n' "$live" > "$temporary/$live/config.json"
    printf 'kankisen \t換気扇\nkan \t燗\nkanwosuru \t燗をする\nshinogakita \t紫乃が来た\n' > "$temporary/checks.tsv"
    if [[ "$live" == true ]]; then printf 'kankisen\t換気扇\n' >> "$temporary/checks.tsv"; fi
    echo "ユーザー辞書の実変換テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-inputs "$temporary/checks.tsv"
done
