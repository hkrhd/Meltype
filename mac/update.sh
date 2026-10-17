#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 hrmcngs

# テストと実エンジンの検証に成功したビルドだけをインストールする。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$HOME/Library/Input Methods/Meltype.app"

case "${1:-}" in
    -h|--help)
        echo "Usage: bash mac/update.sh"
        echo "Test, build, install, verify, and select the local Mac input method."
        exit 0 ;;
    "") ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 1; }
[[ "$(uname)" == Darwin ]] || { echo "This updater requires macOS." >&2; exit 1; }

export MELTYPE_VERSION="${MELTYPE_VERSION:-$(bash "$here/fork-version.sh")}"
export MELTYPE_BUILD_NUMBER="${MELTYPE_BUILD_NUMBER:-$(git -C "$here/.." rev-list --count HEAD)}"
bash "$here/build-cli.sh" --test --build
bash "$here/test-user-dictionary.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
MELTYPE_DATA_DIR="$temporary" "$here/build/Meltype.app/Contents/MacOS/Meltype" --check-inputs "$here/Resources/InputChecks.tsv"
bash "$here/install-app.sh" "$here/build/Meltype.app" "$app"
"$app/Contents/MacOS/Meltype" --register-input-source
"$app/Contents/MacOS/MeltypeRegisterInputSource" "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
# 未登録のビルド用コピーを解除すると -10814 になる。導入済みIMEの起動は妨げない。
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$here/build/Meltype.app" 2>/dev/null || true
bash "$here/start-input-method.sh" "$app"
swift "$here/select-input-source.swift"
"$app/Contents/MacOS/Meltype" --version
echo "Meltype update and input checks completed."
