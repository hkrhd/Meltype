#!/usr/bin/env bash
# main は upstream 専用、改善は専用ブランチに残す。成功後に mac/update.sh で検証・導入する。
set -euo pipefail
cd "$(dirname "$0")/.."
branch=fix/userdict-head-contamination
if [[ -z "$(jj log --no-graph -r "@ & $branch::" -T commit_id)" ]]; then
    echo "$branch の作業コピーで実行してください。" >&2
    exit 1
fi
if [[ -n "$(jj diff --name-only)" ]]; then
    echo '作業中の変更を jj commit で保存してから再実行してください。' >&2
    exit 1
fi
jj git fetch --remote upstream --branch main --tag 'v*'
if [[ -n "$(jj log --no-graph -r 'main ~ ::main@upstream' -T commit_id)" ]]; then
    echo 'main が upstream から分岐しています。main の独自変更を確認してください。' >&2
    exit 1
fi
jj rebase -b "$branch" -o main@upstream
jj bookmark set main -r main@upstream
if [[ -n "$(jj log --no-graph -r "conflicts() & (::$branch | @)" -T commit_id)" ]]; then
    echo '競合を解消してからテスト・ビルドしてください。インストールは行いません。' >&2
    exit 1
fi
echo 'upstream の取り込みが完了しました。bash mac/update.sh で検証・インストールできます。'
