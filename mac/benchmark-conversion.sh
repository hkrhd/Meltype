#!/usr/bin/env bash
# 各条件を別プロセス・一時学習データで測る。結果とMetalログは .build 内。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="${1:-$here/build/Meltype.app}"
results="$here/.build/benchmarks"
mkdir -p "$results"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
for engine in zenzai classic; do
    for pipeline in converter keys; do
        name="$engine-$pipeline"
        mkdir "$temporary/$name"
        printf '{"LiveConversion":true}\n' > "$temporary/$name/config.json"
        options=(--benchmark-conversion)
        [[ "$engine" != classic ]] || options+=(--classic)
        [[ "$pipeline" != keys ]] || options+=(--key-events)
        echo "計測: $name"
        MELTYPE_DATA_DIR="$temporary/$name" /usr/bin/time -l \
            "$app/Contents/MacOS/Meltype" "${options[@]}" \
            > "$results/$name.json" 2> "$results/$name.log"
    done
done
echo "計測結果: $results"
