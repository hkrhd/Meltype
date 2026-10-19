#!/usr/bin/env bash
# b4846 の公開ABIを保ち、Q5モデルで不要なBF16カーネルを除いたMetalランタイムを作る。
# 配布XCFrameworkはこのMacで get_rows_bf16 の初期化に失敗するため、同じソースから再ビルドする。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
revision=10131b23ee0dbd9d03dfc618cec9fe3402919277
checksum=be998a93d2bc25b94935ea5c00b1a4c3b8efc20800894f61e6affe706c5b49c0
architecture=$(uname -m)
directory="$here/.build/llama-metal"
source="$directory/source-$revision"
build="$directory/b4846-no-bf16-$architecture"
mkdir -p "$directory"
if [[ ! -d "$source" ]]; then
    archive=$(mktemp "$directory/source.XXXXXX")
    staging=$(mktemp -d "$directory/unpack.XXXXXX")
    trap 'rm -f "$archive"; rm -rf "$staging"' EXIT
    curl --fail --location --retry 3 "https://codeload.github.com/azooKey/llama.cpp/tar.gz/$revision" -o "$archive" >&2
    [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == "$checksum" ]] || { echo 'llama source checksum mismatch' >&2; exit 1; }
    tar -xzf "$archive" --strip-components=1 -C "$staging"
    mv "$staging" "$source"
fi
cmake -S "$source" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_METAL_USE_BF16=OFF \
    -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=Apple -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF >&2
cmake --build "$build" --config Release --parallel 6 >&2
libraries=("$build/src/libllama.a" "$build/ggml/src/libggml.a"
    "$build/ggml/src/libggml-base.a" "$build/ggml/src/libggml-cpu.a"
    "$build/ggml/src/ggml-metal/libggml-metal.a" "$build/ggml/src/ggml-blas/libggml-blas.a")
xcrun libtool -static -o "$build/combined.a" "${libraries[@]}" >&2
xcrun --sdk macosx clang++ -dynamiclib -arch "$architecture" \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -mmacosx-version-min=13.3 \
    -Wl,-force_load,"$build/combined.a" -framework Foundation -framework Metal -framework Accelerate \
    -install_name '@rpath/llama.framework/Versions/Current/llama' -o "$build/llama" >&2
cp "$source/LICENSE" "$build/llama-LICENSE.txt"
# 成功した現行構成のソースと増分ビルドを残し、旧版・別CPU向けを整理する。
for cached in "$directory"/source-* "$directory"/b*-no-bf16-*; do
    [[ -d "$cached" && "$cached" != "$source" && "$cached" != "$build" ]] || continue
    rm -rf "$cached"
done
printf '%s\n' "$build/llama"
