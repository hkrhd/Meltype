# このフォークの運用

`main` は `upstream/main` の追従用です。独自の変換改善と運用スクリプトは
`fork_by_hkrhd` に置きます。履歴操作には jj を使います。

## 更新

upstream の更新は Codex に取り込みを依頼します。Codex は upstream の差分と変更意図を
確認し、フォーク独自の変換・記号入力などの挙動と方針を保つように調整します。
テキスト上の競合がなくても意味上の衝突があるため、機械的な merge/rebase だけで
完了としません。既存の作業中の変更は保持します。

取り込み後は次のコマンドで検証します。

```sh
bash mac/build-cli.sh --test --build
```

GitHub のデフォルトブランチは `fork_by_hkrhd` です。
Actions の `upstream-update` が12時間ごと（日本時間 9:17・21:17）に upstream/main を確認し、`main` を更新します。
`main` が upstream から分岐している場合は停止します。未取り込みの更新があれば
`main` → `fork_by_hkrhd` の Draft PR を1件作成し、開いている同じ PR があれば再利用します。
専用ブランチは作りません。Actions 画面から手動実行もできます。

ユーザーが PR を確認して Codex に取り込みを依頼します。PR 本文には独自の挙動・方針を
保った調整と検証を指示します。Actions は Codex の起動や独自ブランチへの取り込みを行いません。
GitHub の Actions 設定では、Actions による PR 作成を有効にします。

`zenzai-update` も同じ12時間間隔で、Hugging Face の `Miwa-Keita` 配下の
`zenz-v<数値版>-small-gguf` を確認します。最新系列の `ggml-model-Q5_K_M.gguf` と
使用中の固定モデルを比べ、新系列または重みの SHA-256 が変わった場合に、候補ごとの
`automation/zenzai-v<版>-<SHA-256>` ブランチから `fork_by_hkrhd` への Draft PR を作成します。
PR の変更は `docs/ZENZAI-UPDATE.md` の更新候補の記録だけです。モデル設定の更新・自動マージは行いません。
同じ配布先・重みの PR があれば、クローズ・マージ済みも含めて再作成しません。
説明文だけの更新や xsmall・別量子化形式は通知対象外です。API 障害や必須情報の欠落は実行失敗として扱います。
ユーザーの確認後、Codex にモデル・エンジン互換性・ライセンスの確認と、差し替え・検証を依頼します。
手動実行もでき、`GITHUB_TOKEN` 以外の追加シークレットは不要です。
`GITHUB_REPOSITORY=hkrhd/Meltype node .github/bot/zenzai-update.mjs --dry-run` で、
公開 API に対する検知と重複確認を、PR やブランチを作成せずに試せます。

このフォークで利用する Actions は `upstream-update` と `zenzai-update` です。`build`・`linux`・`mac`・
`bot`・`cla`・`dotnet-update`・`notices`・`pr-checks`・`sponsors`・`winget` は
リポジトリ設定で無効にしています。ワークフローの定義は残し、必要になった場合は
Actions 画面または `gh workflow enable <ファイル名> --repo hkrhd/Meltype` で再開できます。
検証・ビルド・適用は上記のMac用コマンドで行います。

実機へ適用するときは、変更を jj で保存してから `bash mac/update.sh` を実行します。

`mac/update.sh` は Core・Swift テスト、ビルド、実エンジンのフォーク回帰テストと
既存の入力チェックを通してからアプリを入れ替え、起動して入力ソースを選びます。
回帰テストは一時ディレクトリの辞書・設定・学習データを使用します。
既存のユーザー辞書や学習データを編集しません。
フォーク独自の追加テストは `tests/fork/` と Swift Package 内の `mac/Tests/ForkMacTests/` にまとめています。Core の追加テストは
既存テストと一緒に実行し、Mac の実入力ケースは upstream 由来の入力例と分けて検証します。
Swift の既存テストには Xcode (XCTest) が必要です。単体の Command Line Tools が
選択されている場合は、`/Applications/Xcode.app/Contents/Developer` をプロセス内で選びます。
Xcode本体は起動しないため、場所の検出で追加コンポーネントのインストール画面は開きません。
別の場所の Xcode を使う場合は `DEVELOPER_DIR` で指定します。

## バージョン

`mac/fork-version.sh` で履歴上の直近の upstream タグにフォーク識別子・タグ以降のコミット数・
コミット ID を付けます。例: `1.2.2-pre.1.hkrhd.2.g0123456789ab`。
作業中の変更があれば `.dirty` が付きます。upstream のバージョンファイルは変更しません。
アプリの数値ビルド番号には、履歴全体のコミット数を使います。
意図的に指定するときは `MELTYPE_VERSION=... bash mac/update.sh` を使います。

停止中の `mac` CI を再開する場合も、フォークのブランチでは同じバージョンでビルドし、実エンジンの辞書回帰テストを行います。
フォーク版は upstream の自動更新ではなく、このリポジトリから更新してください。
