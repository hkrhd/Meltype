#!/usr/bin/env bash
# small の既定量子化モデルを固定リビジョン・SHA-256で取得する。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
directory="$here/.build/models"
model="$directory/zenz-v3.2-small-Q5_K_M.gguf"
checksum=29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673
url=https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf
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
