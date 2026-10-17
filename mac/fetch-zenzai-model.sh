#!/usr/bin/env bash
# small の既定量子化モデルを固定リビジョン・SHA-256で取得する。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
directory="$here/.build/models"
model="$directory/zenz-v3.1-small-Q5_K_M.gguf"
checksum=4de930c06bef8c263aa1aa40684af206db4ce1b96375b3b8ed0ea508e0b14f6c
url=https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/ddf6e44b2e05ab7ea9a3e31559c5e7948761365c/ggml-model-Q5_K_M.gguf
valid() { [[ -f "$1" && "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" == "$checksum" ]]; }
if ! valid "$model"; then
    mkdir -p "$directory"
    temporary=$(mktemp "$directory/download.XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    curl --fail --location --retry 3 "$url" -o "$temporary"
    valid "$temporary" || { echo 'Zenzai model checksum mismatch' >&2; exit 1; }
    mv "$temporary" "$model"
fi
printf '%s\n' "$model"
