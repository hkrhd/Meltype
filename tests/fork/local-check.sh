#!/usr/bin/env bash
# CI (fork-windows.yml) の Core テストと、Mac の実エンジンの入力検証を Linux の手元で流す。
#   tests/fork/local-check.sh                 … CI と同じ一式 (Core テスト・tests/fork/mac/check-inputs.sh・mac/Resources/InputChecks.tsv)
#   tests/fork/local-check.sh --core [名前]   … Core テストだけ (名前に一致するテストだけにもできる)
#   tests/fork/local-check.sh --inputs FILE   … 「打ったキー<Tab>確定した結果」の一覧だけを実エンジンで確かめる
# 実エンジンは Mac 版と同じ版の Mozc の変換ヘルパーと Zenzai。無ければ native/ のスクリプトでビルドする (初回だけ時間がかかる)。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
app="$root/build-check/local-app"
runner="$root/tests/fork/LocalChecks/bin/Release/net10.0/Meltype.LocalChecks.dll"

prepare_engine() {
    # shellcheck source=../../native/zenzai/zenzai.env
    source "$root/native/zenzai/zenzai.env"
    # 初回のビルドは並列数 LOCAL_CHECK_JOBS (既定 2) で 1 つずつ流す (非力な PC でも固まらない)
    local jobs="${LOCAL_CHECK_JOBS:-2}"
    if [[ ! -x "$root/native/mozc/bin/linux/meltype_mozc_helper" ]]; then
        mkdir -p "$root/build-check"
        # 常駐するサーバーは 5 分使わなければ終わらせる
        printf '#!/usr/bin/env bash\nexec %q --max_idle_secs=300 "$1" --jobs=%q "${@:2}"\n' "${BAZEL:-bazelisk}" "$jobs" > "$root/build-check/bazel"
        chmod +x "$root/build-check/bazel"
        BAZEL="$root/build-check/bazel" bash "$root/native/mozc/build-mozc-helper.sh" "${MOZC_SOURCE:-$HOME/mozc}" "${BAZEL_CACHE:-}"
    fi
    # build-llama-server.sh の並列数は nproc (OMP_NUM_THREADS に従う)
    [[ -x "$root/native/zenzai/bin/linux-$LLAMA_BUILD/llama-server" ]] || OMP_NUM_THREADS="$jobs" bash "$root/native/zenzai/build-llama-server.sh"
    local model="$root/native/zenzai/cache/$ZENZ_NAME"
    if [[ ! -f "$model" ]] || [[ "$(sha256sum "$model" | cut -d' ' -f1)" != "$ZENZ_SHA256" ]]; then
        curl -fsSL -o "$model" "https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/$ZENZ_COMMIT/ggml-model-Q5_K_M.gguf"
        echo "$ZENZ_SHA256  $model" | sha256sum -c -
    fi
    rm -rf "$app"
    mkdir -p "$app"
    ln -s "$root/native/mozc/bin/linux" "$app/mozc"
    cp -R "$root/native/zenzai/bin/linux-$LLAMA_BUILD" "$app/zenzai"
    ln -s "$model" "$app/zenzai/$ZENZ_NAME"
    dotnet build "$root/tests/fork/LocalChecks/Meltype.LocalChecks.csproj" -c Release -v quiet -nologo
}

inputs() {
    local data
    data="$(mktemp -d)"
    MELTYPE_APP_DIR="$app" MELTYPE_DATA_DIR="$data" dotnet "$runner" --check-inputs "$1"
    rm -rf "$data"
}

case "${1:-}" in
    --core)
        dotnet run --project "$root/src/Meltype.Core.Tests" -c Release -- "${@:2}"
        ;;
    --inputs)
        prepare_engine
        inputs "$2"
        ;;
    "")
        dotnet run --project "$root/src/Meltype.Core.Tests" -c Release
        prepare_engine
        # check-inputs.sh には、Mac アプリの代わりに同じ --check-* を受け付けるランナーを渡す
        wrapper="$app/meltype"
        printf '#!/usr/bin/env bash\nMELTYPE_APP_DIR=%q exec dotnet %q "$@"\n' "$app" "$runner" > "$wrapper"
        chmod +x "$wrapper"
        bash "$here/mac/check-inputs.sh" "$wrapper"
        inputs "$root/mac/Resources/InputChecks.tsv"
        ;;
    *)
        sed -n '2,6p' "$0" >&2
        exit 2
        ;;
esac
