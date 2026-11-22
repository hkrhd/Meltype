# フォーク独自の回帰テスト

このフォークで追加したテストを、upstream 由来のテストと分けて管理します。Swift テストは Swift Package 内に置く必要があるため、`mac/Tests/ForkMacTests` にまとめます。

- `Core/`: 句点の入力、ユーザー辞書による単語の分断防止、記号の半角入力。
  `Meltype.Core.Tests.csproj` から同じアセンブリに取り込み、既存の入力用ヘルパーを共有します。
  実行結果はメソッド名の `Fork_` で識別できます。
  フォークにしかない API（辞書の再読込・検出器のユーザー辞書・Zenzai の偽サーバー）を使うテストは `Core/ForkApi/` に置き、
  `upstream-check.sh` が upstream 単体で実行するときに除きます。
- `mac/check-inputs.sh`: 一時辞書・設定を使った実エンジンの回帰テスト。Linux では `local-check.sh` が Mac アプリの代わりに `LocalChecks/` で流す。
  `--check-predictions` で英字3文字からの補完、Tab／Shift+Tab・Esc・Enter、クリック用のC ABIによる確定も検証します。
- `mac/Tests/ForkMacTests/DictionarySyncTests.swift` (リポジトリ直下からのパス): 一時 SQLite DB を使い、自動同期、WAL・DB 入れ替えの監視、スリープ時の再読込を検証。
- `mac/Tests/ForkMacTests/UpdaterTests.swift`: 偽の Releases 一覧と ZIP で、更新する版の選択、失敗した版の再試行抑止、ハッシュ検証、入力中の待機、`install.sh` の起動を検証。
- `Windows/UpdaterTests.cs`: ビルド番号による新旧の比較と、手元のサーバーで再現した Releases からの `update.ps1` の取得・展開を検証（Windows のみ）。
- `mac/InputChecks.tsv`: 記号・ショートカット表記・区切り線の入力の期待値。upstream の
  `mac/Resources/InputChecks.tsv` と別に実行します。
- `mac/CandidateChecks.tsv`: 入力キー列と選択・確定する候補。`--check-candidates` が
  Space で一覧を開き、候補の位置に依存せず文節ごとに選択して文章全体の確定結果を確認します。
  ライブ変換の有効・無効それぞれで、同じセッションへの再入力も検証します。

実行手順は [README.md のビルドと検証](../../README.md#ビルドと検証)を参照してください。

既存テストの期待値をフォークの仕様に合わせた変更や共通ヘルパーの調整は、元のファイルに残しています。
