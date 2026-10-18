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
    printf '{"main":{"English":true,"Used":"2026-10-18T00:00:00Z","Count":1},"no":{"English":true,"Used":"2026-10-18T00:00:00Z","Count":1,"Explicit":true}}\n' > "$temporary/$live/languages.json"
    printf 'kankisen \t換気扇\nkan \t燗\nkanwosuru \t燗をする\nshinogakita \t紫乃が来た\n' > "$temporary/checks.tsv"
    printf 'motatsukukanjihaaru \tもたつく感じはある\nsukoshimotatsukukanjigasuru \t少しもたつく感じがする\n' >> "$temporary/checks.tsv"
    printf 'shijisuru \t支持する\n' >> "$temporary/checks.tsv"
    printf 'mainno\tmainの\nmainno \tmainの\nmainde\tmainで\nmainde \tmainで\nmainwo\tmainを\nmainwo \tmainを\n' >> "$temporary/checks.tsv"
    if [[ "$live" == true ]]; then
        printf 'kankisen\t換気扇\nmotatsukukanjihaaru\tもたつく感じはある\n' >> "$temporary/checks.tsv"
    fi
    echo "ユーザー辞書・英単語と助詞の実変換テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-inputs "$temporary/checks.tsv"
    echo "候補の表示・選択・確定テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-candidates "$here/CandidateChecks.tsv"
done

echo "フォーク独自の入力チェック"
mkdir "$temporary/inputs"
printf '{"SigilWordsDirect":false}\n' > "$temporary/inputs/config.json"
MELTYPE_DATA_DIR="$temporary/inputs" "$app/Contents/MacOS/Meltype" --check-inputs "$here/InputChecks.tsv"
