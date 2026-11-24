# フォークの検証

フォークで足したテストはここに置き、upstream 由来のテストと分けます（Swift のテストは Swift Package 内に要るので `mac/Tests/ForkMacTests/`）。フォークにしかない API を使う Core テストは `Core/ForkApi/` に置き、`upstream-check.sh` が upstream 単体で実行するときに除きます。既存テストの期待値をフォークの仕様に合わせた変更や共通ヘルパーの調整は、元のファイルに残しています。

## Linux で流す（push 前の一式）

```sh
tests/fork/local-check.sh --core Fork_   # Core テストの一部（名前に一致するもの）
tests/fork/local-check.sh --inputs <TSV>  # 「打ったキー<Tab>確定した結果」の一覧を実エンジンで
tests/fork/local-check.sh                 # push 前の一式
tests/fork/upstream-check.sh              # upstream 単体にフォークの Core テストを載せる（取り込み用）
```

`local-check.sh` の実エンジンは Mac 版と同じ版の Mozc と Zenzai で、Mac アプリの代わりに `LocalChecks/` が同じ確認をします。初回は Mozc の変換ヘルパー（Bazelisk・clang、1時間ほど）と llama-server（cmake）をビルドします。`native/mozc/` と `native/zenzai/zenzai.env` が同じなら、別の作業コピーの `native/mozc/bin/linux/`・`native/zenzai/bin/`・`native/zenzai/cache/*.gguf` をコピーして使えます。Windows・Swift 固有の検証は[配布](../../fork/release.md)の実行で行います。

## 手元の Mac で流す

対象は Apple Silicon・macOS 13.3 以降で、.NET 10 SDK（10.0.403 以降）と Xcode が要ります（Xcode の場所は `DEVELOPER_DIR`）。Mozc の変換ヘルパーは `native/mozc/build-mozc-helper.sh`（Bazelisk、初回30〜40分）で `native/mozc/bin/mac/` に作るか、`native/mozc/` が同じ upstream リリースの Mac 版 ZIP の `Meltype.app/Contents/Resources/mozc/` から置きます。Zenzai はビルドスクリプトが取得します。

```sh
bash mac/build-cli.sh --test --build   # Core・Swift のテストとビルド
bash tests/fork/mac/check-inputs.sh   # 実エンジンの入力検証（一時的な辞書・設定・学習データ）
```

## そのほか

```sh
dotnet run --project src/Meltype.Core.Tests -- --eval
dotnet run --project src/Meltype.Core.Tests -- --repro kyouhagoogle enter
node tools/check-dictionaries.mjs       # 辞書を変更したとき
python3 tools/mcfly-terms.py --min-count 3  # 英語辞書に足す語をシェル履歴から探す（履歴本文は出さない）
```

McFly の集計結果は自動では辞書に足しません。個人情報や不要な語が混ざっていないか、登録の前に確かめます。
