#!/usr/bin/env bash
# small の既定量子化モデルを固定リビジョン・SHA-256で取得する。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
directory="$here/.build/models"
source "$here/../native/zenzai/zenzai.env"
model="$directory/$ZENZ_NAME"
checksum="$ZENZ_SHA256"
url="https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/$ZENZ_COMMIT/ggml-model-Q5_K_M.gguf"
valid() { [[ -f "$1" && "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" == "$checksum" ]]; }
if ! valid "$model"; then
    mkdir -p "$directory"
    temporary=$(mktemp "$directory/download.XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    curl --fail --location --retry 3 "$url" -o "$temporary"
    valid "$temporary" || { echo 'Zenzai model checksum mismatch' >&2; exit 1; }
    mv "$temporary" "$model"
fi
# 検証済みの現行モデルだけを残す。取得失敗時には旧モデルを消さない。
for cached in "$directory"/zenz-*.gguf; do
    [[ -e "$cached" && "$cached" != "$model" ]] || continue
    rm -f "$cached"
done
printf '%s\n' "$model"
