# このフォークの運用

`main` は `upstream/main` の追従用です。独自の変換改善と運用スクリプトは
`fork_by_hkrhd` に置きます。履歴操作には jj を使います。

## 更新

upstream の更新は Codex に取り込みを依頼します。Codex は upstream の差分と変更意図を
確認し、フォーク独自の変換・記号入力などの挙動と方針を保つように調整します。
テキスト上の競合がなくても意味上の衝突があるため、機械的な merge/rebase だけで
完了としません。既存の作業中の変更は保持します。

取り込みは `fork_by_hkrhd` と `main` を親に持つマージコミットとして記録します。
squash や rebase で取り込み元の履歴を平坦化せず、Git の履歴から両方の親を追えるようにします。
`jj new fork_by_hkrhd main` で統合し、調整・検証後に `fork_by_hkrhd` を進めます。

取り込み後は次のコマンドで検証します。

```sh
bash mac/build-cli.sh --test --build
```

GitHub のデフォルトブランチは `fork_by_hkrhd` です。
GitHub のブランチ保護で `fork_by_hkrhd` への強制プッシュとブランチ削除を禁止し、
管理者にも適用しています。通常の push は可能です。必須ステータスチェックや
PR レビューの必須化は設定せず、検証は上記のローカルコマンドで行います。
Actions の `upstream-update` が2日に1回（日本時間 21:17）に upstream/main を確認し、`main` を更新します。
cron では2日間隔を表せないため、毎日 21:17 に起動して、UTC の通算日が偶数の日だけ同期します（手動実行は常に動きます）。
`main` が upstream から分岐している場合は停止します。未取り込みの更新があれば
`main` → `fork_by_hkrhd` の Draft PR を1件作成し、開いている同じ PR があれば再利用します。
専用ブランチは作りません。Actions 画面から手動実行もできます。

ユーザーが PR を確認して Codex に取り込みを依頼します。PR 本文には独自の挙動・方針を
保った調整と検証を指示します。Actions は Codex の起動や独自ブランチへの取り込みを行いません。
GitHub の Actions 設定では、Actions による PR 作成を有効にします。

`main` の同期は、このリポジトリ専用の書き込み用 SSH デプロイキーで行います。
公開鍵を Settings → Deploy keys に書き込み許可付きで登録します。
Settings → Environments に `upstream-sync` を作り、Deployment branches and tags を
Selected branches and tags にして、Branch の `fork_by_hkrhd` だけを許可します。
秘密鍵はその Environment の `UPSTREAM_SYNC_SSH_KEY` シークレットに登録します。
リポジトリ全体のシークレットには置かず、同期対象の `main` からキーを使えないようにします。
標準の `GITHUB_TOKEN` では upstream の `.github/workflows/` の変更を同期できないためです。
キーが未設定の場合はエラーで停止します。upstream のコードは実行せず、`main` が
upstream/main の祖先であることを確認して、force なしの push で追従します。
PR 作成には引き続き `GITHUB_TOKEN` を使います。キーを廃止・交換する際は
Deploy keys と Environment シークレットの両方を削除・更新してください。

`zenzai-update` も同じ12時間間隔で、Hugging Face の `Miwa-Keita` 配下の
`zenz-v<数値版>-small-gguf` を確認します。最新系列の `ggml-model-Q5_K_M.gguf` と
使用中の固定モデルを比べ、新系列または重みの SHA-256 が変わった場合に、候補ごとの
`automation/zenzai-v<版>-<SHA-256>` ブランチから `fork_by_hkrhd` への Draft PR を作成します。
PR の変更は `docs/ZENZAI-UPDATE.md` の更新候補の記録だけです。モデル設定の更新・自動マージは行いません。
同じ配布先・重みの PR があれば、クローズ・マージ済みも含めて再作成しません。
説明文だけの更新や xsmall・別量子化形式は通知対象外です。API 障害や必須情報の欠落は実行失敗として扱います。
ユーザーの確認後、Codex にモデル・エンジン互換性・ライセンスの確認、差し替え、実機へのインストール・動作確認を依頼します。
モデル更新時は推論上限1回と2回の精度を比較し、低下がなければ1回に減らします。
手動実行もでき、`GITHUB_TOKEN` 以外の追加シークレットは不要です。
`GITHUB_REPOSITORY=hkrhd/Meltype node .github/bot/zenzai-update.mjs --dry-run` で、
公開 API に対する検知と重複確認を、PR やブランチを作成せずに試せます。

このフォークで利用する Actions は `upstream-update` と `zenzai-update` です。`build`・`linux`・`mac`・
`bot`・`cla`・`dotnet-update`・`ime-tests`・`notices`・`pr-checks`・`sponsors`・`web`・`winget` は
リポジトリ設定で無効にしています。ワークフローの定義は残し、必要になった場合は
Actions 画面または `gh workflow enable <ファイル名> --repo hkrhd/Meltype` で再開できます。
検証・ビルド・適用は上記のMac用コマンドで行います。

upstream で追加された `code-scanning`・`codeql`・`conflicts`・`quality` は、
GitHub がワークフローとして登録する前に `.github/disabled-workflows/` に移して保管します。
フォークへの取り込みで新しいCIやコメントbotが自動的に有効になるのを防ぎます。
開発指示は、大文字小文字を区別しない macOS でも衝突しないよう `AGENTS.md` に統合しています。

取り込んだ `Casks/meltype.rb` と apt 配布手順は upstream 版向けです。
このフォークの独自変更を使う場合は Homebrew・apt ではなく `bash mac/update.sh` で更新します。

実機へ適用するときは、変更を jj で保存してから `bash mac/update.sh` を実行します。

ローカルの生成物は必要最低限に保ちます。モデルの取得・SHA-256検証後は
`mac/.build/models` の旧 `zenz-*.gguf` を、Metalランタイムのビルド成功後は
`mac/.build/llama-metal` の旧ソース・旧構成を削除します。アプリの組み立て・署名後は
`mac/build/native` の作業用コピーとデバッグシンボルも削除します。
現行モデル、Swift・.NET・Metalの増分ビルド、取得済み依存と最新のアプリは保持します。
比較検証で作った一時アプリ・旧モデル・一時学習データも、検証終了後に整理し、
比較結果のJSON・ログなどは残します。共有のシステムキャッシュやユーザーの学習データは対象外です。

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
