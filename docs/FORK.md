# このフォークの運用

`main` は `upstream/main` の追従用、`fork_by_hkrhd` は独自変更用です。
GitHub のデフォルトブランチは `fork_by_hkrhd`。履歴操作には jj を使います。
一般的な開発手順は [DEVELOPMENT.md](DEVELOPMENT.md) を参照してください。

## 検証・実機適用・コミット

README.md に変更点を追記し、**実機への適用に成功してからコミット・プッシュ**します。
jj による作業内容の自動保存は、検証後のコミット確定とは区別します。

```sh
bash mac/build-cli.sh --test --build   # 実機へ適用せず、Core・Swift のテストとビルド
bash mac/update.sh                     # テスト・ビルド・入力検証・実機適用・入力ソース選択
# 成功後、jj でコミットを確定し、fork_by_hkrhd を進めて push
```

入力検証には一時的な辞書・設定・学習データを使い、既存のユーザーデータは編集しません。
Swift のテストには Xcode が必要です。スクリプトは Xcode 本体を起動せず検出します。
別の場所を使う場合は `DEVELOPER_DIR` で指定します。

```sh
dotnet run --project src/Meltype.Core.Tests
dotnet run --project src/Meltype.Core.Tests -- --eval
dotnet run --project src/Meltype.Core.Tests -- --repro kyouhagoogle enter
node tools/check-dictionaries.mjs       # 辞書を変更したとき
```

追加テストは `tests/fork/` と `mac/Tests/ForkMacTests/` に置きます。
成功後は不要な旧モデル・旧ランタイム・一時アプリ・一時学習データを削除します。
現行モデル、増分ビルド用キャッシュ、取得済み依存、最新アプリ、検証結果は保持します。
共有のシステムキャッシュやユーザーの学習データは削除しません。

## upstream の取り込み

1. 最新の `upstream/main` を取得し、分岐していないことを確認して `main` を進めます。
2. 既存の作業中の変更を保持し、`jj new fork_by_hkrhd main` で統合先を作って変更を引き継ぎます。
3. 差分と変更意図を確認し、Zenzai・半角記号など独自の挙動を維持します。
   競合がない箇所も意味上の衝突を確認し、判断に迷ったらユーザーに尋ねます。
   upstream の `AGENTS.md` はフォークの内容で上書きします。
4. README.md を更新し、`bash mac/update.sh` で検証・実機適用します。
5. 成功後、`fork_by_hkrhd` と `main` を親に持つマージコミットを確定して push します。
   squash・rebase で取り込み元の履歴を平坦化せず、更新依頼 PR があれば変更点・検証結果を記録します。

通知の Draft PR は作業依頼です。GitHub のマージボタンでは取り込まず、最新の `main` を使って調整します。
`fork_by_hkrhd` は管理者を含め強制 push・削除を禁止し、通常の push は許可しています。
必須 CI・必須レビューは設定せず、ローカルで検証します。

## 辞書同期とバージョン

- macOS のテキスト置換を `userdict.txt` に自動同期します。DB/WAL の変更後、画面スリープ時に再読込します。
  macOS 側を正とし、独自登録や入力メニューから取り込んだ plist の内容も次の同期で置き換わります。
  DB の取得・形式エラー時は既存辞書を保ち、CLI・テストでは同期しません。
- `mac/fork-version.sh` は直近の upstream タグ・以降のコミット数・コミット ID から版番号を作ります
  （例: `1.2.2-pre.1.hkrhd.2.g0123456789ab`）。実機適用はコミット前なので `.dirty` が付きます。
  数値ビルド番号は履歴全体のコミット数です。必要なら `MELTYPE_VERSION=... bash mac/update.sh` で指定します。
- upstream のバージョンファイルは変更しません。フォーク版は自動更新の対象外です。
  Releases の Mac 版 ZIP または `bash mac/update.sh` で更新します。Homebrew Cask・apt は upstream 版向けです。

## 更新通知の Actions

| ワークフロー | 動作 |
| --- | --- |
| `upstream-update` | 2日に1回、日本時間21:17に `main` を同期し、未取り込み分の Draft PR を作成・再利用 |
| `zenzai-update` | 12時間ごとに Zenzai small / Q5_K_M の新系列・重みの SHA-256 変更を Draft PR で通知 |
| `windows` | push・PR で Windows を検証。手動実行では Windows・Mac の配布物を作成 |

通知の Actions は取り込み・モデル差し替え・自動マージを行いません。
upstream の PR は `main` → `fork_by_hkrhd` とし、通知時点のコミットと固定した差分リンクを記録します。
毎日起動して UTC の通算日が偶数の日だけ同期し、手動実行は常に同期します。
`main` が upstream から分岐している場合は停止し、force push は行いません。

同期には専用の書き込み可能な SSH デプロイキーを使います。公開鍵は Deploy keys、秘密鍵は
`upstream-sync` Environment の `UPSTREAM_SYNC_SSH_KEY` に登録します。
Environment は `fork_by_hkrhd` からだけ利用可能にし、リポジトリ全体のシークレットには置きません。
標準の `GITHUB_TOKEN` では upstream のワークフロー定義を同期できないためです。
PR 作成には `GITHUB_TOKEN` を使い、Actions による PR 作成を有効にします。
キーの廃止・交換時は Deploy keys と Environment シークレットの両方を更新します。

Zenzai は Miwa-Keita の `zenz-v<数値版>-small-gguf` / `ggml-model-Q5_K_M.gguf` を確認し、
`docs/ZENZAI-UPDATE.md` の候補記録だけを変更します。同じ配布先・重みの PR はクローズ済みも含め再作成しません。
説明文だけの変更・xsmall・別量子化形式は対象外で、API 障害や必須情報の欠落は失敗として扱います。
モデル更新では互換性・ライセンスを確認し、推論上限1回・2回の精度を比較して、低下がなければ1回に減らします。
測定方法と過去の比較は [ZENZAI-PERFORMANCE.md](ZENZAI-PERFORMANCE.md) を参照してください。

```sh
GITHUB_REPOSITORY=hkrhd/Meltype node .github/bot/zenzai-update.mjs --dry-run
```

upstream の Actions は無効化します。既存の `build`・`linux`・`mac`・`bot`・`cla`・`dotnet-update`・
`ime-tests`・`notices`・`pr-checks`・`sponsors`・`web`・`winget` はリポジトリ設定で停止しています。
`code-scanning`・`codeql`・`conflicts`・`quality` など、新しい CI・bot は登録前に `.github/disabled-workflows/` へ移します。
CI/CD を新設・変更した場合は一度手動実行して成功を確認します。

## Windows の検証と配布物

`windows` は Release ビルド、TSF DLL の x64・x86 ビルド、共通コアを含む Windows テスト、
インストーラー検証を行います。Microsoft IME・スペルチェッカーがない環境の該当テストはスキップします。
実際の入力欄への打鍵 E2E は含みません。

```sh
gh workflow run windows.yml --repo hkrhd/Meltype --ref fork_by_hkrhd
```

手動実行では検証成功後にリリースの下書きを作り、両 OS の配布物を並列ビルドします。
Windows は通常版 ZIP・ポータブル版 ZIP・インストーラーを作り、自己診断と Defender 検査を行います。
Mac は Apple Silicon / macOS 13.3 以降向けに Core・Swift・実エンジン・NativeAOT 境界を検証し、
Zenzai・Metal ランタイム・インストーラーを含む ZIP を作ります。展開後 `Install Meltype.command` で導入できます。
Mac の Developer ID・公証シークレットがなければ ad-hoc 署名、Windows の署名シークレットがなければ未署名です。

同じソース・フォーク版番号の配布物4個がそろうと、`hkrhd-release-<実行ID>-<再実行番号>` をプレリリース公開します。
失敗時は下書きのままとし、過去の公開リリース・タグは削除しません。
配布物は Releases に保存し、Actions artifact は使いません。キャッシュは無料枠10 GB内で保持します。
課金防止には Actions の予算を `$0`、`Stop usage when budget limit is reached` を有効にします。
Windows も `mac/fork-version.sh` の版番号を使い、upstream の版タグを取得してからビルドします。

## コントリビュート

3つ以上の PR を出す場合は統合 PR も作成します。2つまでなら必要に応じて競合を解消します。
