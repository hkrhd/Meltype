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
    mkdir "$temporary/$live/dictionaries"
    printf 'sudo\nrepo\nno\ne\nc\n' > "$temporary/$live/dictionaries/english.txt"
    printf 'かん\t燗\nしの\t紫乃\n' > "$temporary/$live/userdict.txt"
    printf '{"LiveConversion":%s}\n' "$live" > "$temporary/$live/config.json"
    printf '{"main":{"English":true,"Used":"2026-10-18T00:00:00Z","Count":1},"no":{"English":true,"Used":"2026-10-18T00:00:00Z","Count":1,"Explicit":true},"ni":{"English":true,"Used":"2026-10-24T00:00:00Z","Count":2,"Explicit":true},"toto":{"English":true,"Used":"2026-10-17T02:44:59Z","Count":1,"Explicit":false}}\n' > "$temporary/$live/languages.json"
    printf '{"ないように":{"Text":"内容に","Used":"2026-10-24T00:00:00Z"}}\n' > "$temporary/$live/conversions.json"
    printf 'kankisen \t換気扇\nkan \t燗\nkanwosuru \t燗をする\nshinogakita \t紫乃が来た\n' > "$temporary/checks.tsv"
    printf 'motatsukukanjihaaru \tもたつく感じはある\nsukoshimotatsukukanjigasuru \t少しもたつく感じがする\n' >> "$temporary/checks.tsv"
    printf 'shijisuru \t支持する\n' >> "$temporary/checks.tsv"
    printf 'lji \tL字\n' >> "$temporary/checks.tsv"
    printf 'nanm \t何m\nnancm \t何cm\nnanmm \t何mm\nnankg \t何kg\nnanGB \t何GB\nnanpx \t何px\nnanfps \t何fps\nnannAPI \t何API\n' >> "$temporary/checks.tsv"
    printf 'fo-matta \tフォーマッタ\nfor\tfor\ne-mail\te-mail\nco-op\tco-op\nx-ray\tx-ray\n' >> "$temporary/checks.tsv"
    printf 'mainno\tmainの\nmainno \tmainの\nmainde\tmainで\nmainde \tmainで\nmainwo\tmainを\nmainwo \tmainを\n' >> "$temporary/checks.tsv"
    printf 'mainnoyousuwomite \tmainの様子を見て\n' >> "$temporary/checks.tsv"
    printf '1niti1kai \t1日1回\n1nichi1kai \t1日1回\n1nitini1kai \t1日に1回\n' >> "$temporary/checks.tsv"
    printf '1niti2kai \t1日2回\n1niti3kai \t1日3回\n12nichini10kai \t12日に10回\n' >> "$temporary/checks.tsv"
    printf 'sudo\tsudo\nsudo apt\tsudo apt\nrepo\trepo\n' >> "$temporary/checks.tsv"
    printf 'no\tの\nno no\tno の\nno problem\tno problem\nI have no problem\tI have no problem\n' >> "$temporary/checks.tsv"
    printf 'auto no\tauto の\n' >> "$temporary/checks.tsv"
    printf 'google ni\tgoogle に\n' >> "$temporary/checks.tsv"
    printf 'macnanode\tmacなので\nmacnanode \tmacなので\nmacdakara\tmacだから\nmacdakara \tmacだから\n' >> "$temporary/checks.tsv"
    printf 'puronputotoshite \tプロンプトとして\npuronputotosite \tプロンプトとして\npuronputoto \tプロンプトと\nkatachiwototonoeru \t形を整える\n' >> "$temporary/checks.tsv"
    printf 'toto\ttoto\nI use toto\tI use toto\nkyouhalinede \t今日はlineで\n' >> "$temporary/checks.tsv"
    printf 'ataranaiyouni \t当たらないように\nfurenaiyouni \t触れないように\nnaiyouni \t内容に\n' >> "$temporary/checks.tsv"
    if [[ "$live" == true ]]; then
        printf 'puronputotoshite\tプロンプトとして\npuronputotosite\tプロンプトとして\nkyouhalinede\t今日はlineで\n' >> "$temporary/checks.tsv"
        printf 'lji\tL字\n' >> "$temporary/checks.tsv"
        printf 'nancm\t何cm\nnanmm\t何mm\nnanpx\t何px\n' >> "$temporary/checks.tsv"
        printf 'fo-matta\tフォーマッタ\n' >> "$temporary/checks.tsv"
        printf 'ataranaiyouni\t当たらないように\nfurenaiyouni\t触れないように\nnaiyouni\t内容に\n' >> "$temporary/checks.tsv"
        printf '1niti1kai\t1日1回\n' >> "$temporary/checks.tsv"
        printf 'kankisen\t換気扇\nmotatsukukanjihaaru\tもたつく感じはある\n' >> "$temporary/checks.tsv"
        printf 'mainnoyousuwomite\tmainの様子を見て\n' >> "$temporary/checks.tsv"
    else
        printf 'mainnoyousuwomite\tmainのようすをみて\n' >> "$temporary/checks.tsv"
    fi
    echo "ユーザー辞書・英単語と助詞の実変換テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-inputs "$temporary/checks.tsv"
    echo "候補の表示・選択・確定テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-candidates "$here/CandidateChecks.tsv"
    echo "英単語補完の表示・選択・確定テスト (LiveConversion=$live)"
    MELTYPE_DATA_DIR="$temporary/$live" "$app/Contents/MacOS/Meltype" --check-predictions

    echo "短い登録語がある場合の読み全体の選択・学習テスト (LiveConversion=$live)"
    learned="$temporary/whole-$live"
    mkdir "$learned"
    printf '{"LiveConversion":%s}\n' "$live" > "$learned/config.json"
    printf 'けい\t径\n' > "$learned/userdict.txt"
    printf '{"けい":{"Text":"計","Used":"2026-11-03T00:00:00Z"}}\n' > "$learned/conversions.json"
    printf 'keisann\t計算\n' > "$learned/candidates.tsv"
    MELTYPE_DATA_DIR="$learned" "$app/Contents/MacOS/Meltype" --check-candidates "$learned/candidates.tsv"
    # 別プロセスでも読み全体の学習が残り、途中の登録語・学習で再分割されない。
    printf 'keisann \t計算\nkeisan \t計算\nkei \t計\n' > "$learned/inputs.tsv"
    if [[ "$live" == true ]]; then
        printf 'keisann\t計算\nkeisan\t計算\n' >> "$learned/inputs.tsv"
    fi
    MELTYPE_DATA_DIR="$learned" "$app/Contents/MacOS/Meltype" --check-inputs "$learned/inputs.tsv"
done

echo "フォーク独自の入力チェック"
mkdir "$temporary/inputs"
printf '{"SigilWordsDirect":false}\n' > "$temporary/inputs/config.json"
MELTYPE_DATA_DIR="$temporary/inputs" "$app/Contents/MacOS/Meltype" --check-inputs "$here/InputChecks.tsv"
