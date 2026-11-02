#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 hkrhd
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
app="${1:-$root/mac/build/Meltype.app}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
swiftc -o "$temporary/check-dictionary-reload" \
    "$here/DictionaryReloadCheck.swift" \
    "$root/mac/Sources/MeltypeIME/MacDictionaryWatcher.swift" \
    "$root/mac/Sources/MeltypeIME/DictionaryFileMonitor.swift"
"$temporary/check-dictionary-reload" "$app/Contents/Frameworks/libMeltypeNative.dylib"
