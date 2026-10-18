#!/usr/bin/env bash
# ビルドした実エンジンを一時辞書・一時学習データで検証する。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
app="${1:-$root/mac/build/Meltype.app}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
for live in false true; do
    mkdir "$temporary/$live"
    printf 'かん\t燗\nしの\t紫乃\n' > "$temporary/$live/userdict.txt"
    printf '{"LiveConversion":%s}\n' "$live" > "$temporary/$live/config.json"
    printf 'kankisen \t換気扇\nkan \t燗\nkanwosuru \t燗をする\nshinogakita \t紫乃が来た\n' > "$temporary/checks.tsv"
    printf 'motatsukukanjihaaru \tもたつく感じはある\nsukoshimotatsukukanjigasuru \t少しもたつく感じがする\n' >> "$temporary/checks.tsv"
    if [[ "$live" == true ]]; then
        printf 'kankisen\t換気扇\nmotatsukukanjihaaru\tもたつく感じはある\n' >> "$temporary/checks.tsv"
    fi
    echo "ユーザー辞書の実変換テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-inputs "$temporary/checks.tsv"
done

echo "フォーク独自の入力チェック"
mkdir "$temporary/inputs"
printf '{"SigilWordsDirect":false}\n' > "$temporary/inputs/config.json"
MELTYPE_DATA_DIR="$temporary/inputs" "$app/Contents/MacOS/Meltype" --check-inputs "$here/InputChecks.tsv"
