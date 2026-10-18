# フォーク独自の回帰テスト

このフォークで追加したテストを、upstream 由来のテストと分けて管理します。

- `Core/`: 句点の入力、ユーザー辞書による単語の分断防止、記号の半角入力。
  `Meltype.Core.Tests.csproj` から同じアセンブリに取り込み、既存の入力用ヘルパーを共有します。
  実行結果はメソッド名の `Fork_` で識別できます。
- `mac/check-inputs.sh`: 一時辞書・設定を使った実エンジンの回帰テスト。
- `mac/InputChecks.tsv`: Zenzai の変換例と記号入力の期待値。upstream の
  `mac/Resources/InputChecks.tsv` と別に実行します。

通常どおり `bash mac/build-cli.sh --test --build` で Core・Swift のテストとビルドを行います。
ビルド後は `bash tests/fork/mac/check-inputs.sh` で実エンジンのフォーク回帰テストを実行できます。
`bash mac/update.sh` と Mac の CI でも両方を実行します。

既存テストの期待値をフォークの仕様に合わせた変更や共通ヘルパーの調整は、元のファイルに残しています。
