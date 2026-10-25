# フォーク独自の回帰テスト

このフォークで追加したテストを、upstream 由来のテストと分けて管理します。Swift テストは Swift Package 内に置く必要があるため、`mac/Tests/ForkMacTests` にまとめます。

- `Core/`: 句点の入力、ユーザー辞書による単語の分断防止、記号の半角入力。
  `Meltype.Core.Tests.csproj` から同じアセンブリに取り込み、既存の入力用ヘルパーを共有します。
  実行結果はメソッド名の `Fork_` で識別できます。
- `mac/check-inputs.sh`: 一時辞書・設定を使った実エンジンの回帰テスト。
  `--check-predictions` で英字3文字からの補完、Tab／Shift+Tab・Esc・Enter、クリック用のC ABIによる確定も検証します。
- `zenzai-update.test.mjs`: 外部 API を再現し、新系列・重み更新の通知、重複抑制、障害時の停止を検証。
  `node --test tests/fork/zenzai-update.test.mjs` で実行し、GitHub には書き込みません。
- `mac/Tests/ForkMacTests/DictionarySyncTests.swift` (リポジトリ直下からのパス): 一時 SQLite DB を使い、自動同期、WAL・DB 入れ替えの監視、スリープ時の再読込を検証。
- `mac/InputChecks.tsv`: Zenzai の変換例と記号入力の期待値。upstream の
  `mac/Resources/InputChecks.tsv` と別に実行します。
- `mac/CandidateChecks.tsv`: 入力キー列と選択・確定する候補。`--check-candidates` が
  Space で一覧を開き、候補の位置に依存せず文節ごとに選択して文章全体の確定結果を確認します。
  ライブ変換の有効・無効それぞれで、同じセッションへの再入力も検証します。

通常どおり `bash mac/build-cli.sh --test --build` で Core・Swift のテストとビルドを行います。
ビルド後は `bash tests/fork/mac/check-inputs.sh` で実エンジンのフォーク回帰テストを実行できます。
`bash mac/update.sh` と Mac の CI でも両方を実行します。

既存テストの期待値をフォークの仕様に合わせた変更や共通ヘルパーの調整は、元のファイルに残しています。
