#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 hkrhd
#
# upstream 単体に作業コピーのフォークの Core テスト (ForkApi/ を除く) を載せて実行し、テストごとの合否を出す。
# 合格したテストは upstream が同じ問題を解決済みで、対応するフォークの実装は捨てられる。
# 使い方: tests/fork/upstream-check.sh [upstream のリビジョン (既定 main@upstream)]
set -euo pipefail

upstream="${1:-main@upstream}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

commit() { jj -R "$repo" log --no-graph -r "$1" -T commit_id; }
git -C "$repo" archive "$(commit "$upstream")" | tar -x -C "$work"
mkdir -p "$work/tests/fork"
cp -R "$repo/tests/fork/Core" "$work/tests/fork/"

# プロジェクトの下に置けば csproj を変えずにコンパイルされる。
tests="$work/src/Meltype.Core.Tests"
rm -rf "$work/tests/fork/Core/ForkApi"
mv "$work/tests/fork/Core" "$tests/Fork"
# フォークのテストが足す partial class に合わせ、upstream 側の同名クラスも partial にする。
for name in $(sed -n 's/^internal static partial class \([A-Za-z0-9_]*\).*/\1/p' "$tests"/Fork/*.cs | sort -u); do
  sed -i "s/^internal static class $name\$/internal static partial class $name/" "$tests"/*.cs
done

dotnet run --project "$tests" -c Release -- Fork_
