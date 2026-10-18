# このフォークの運用

`main` は `upstream/main` の追従用です。独自の変換改善と運用スクリプトは
`fix/userdict-head-contamination` に置きます。履歴操作には jj を使います。

## 更新

作業を `jj commit -m '変更の説明'` で保存してから実行します。

```sh
bash tools/sync-upstream.sh
bash mac/update.sh
```

同期は upstream の main とタグを取得し、改善ブランチを新しい main に rebase します。
main に独自変更がある場合や競合した場合は停止します。競合を解消するまで導入しません。
同期だけではリモートへの push やインストールは行いません。

`mac/update.sh` は Core・Swift テスト、ビルド、実エンジンのフォーク回帰テストと
既存の入力チェックを通してからアプリを入れ替え、起動して入力ソースを選びます。
回帰テストは一時ディレクトリの辞書・設定・学習データを使用します。
既存のユーザー辞書や学習データを編集しません。
フォーク独自の追加テストは `tests/fork/` にまとめています。Core の追加テストは
既存テストと一緒に実行し、Mac の実入力ケースは upstream 由来の入力例と分けて検証します。
Swift の既存テストには Xcode (XCTest) が必要です。単体の Command Line Tools が
選択されている場合は、インストール済みの Xcode をプロセス内で選びます。
別の Xcode を使う場合は `DEVELOPER_DIR` で指定します。

## バージョン

`mac/fork-version.sh` で履歴上の直近の upstream タグにフォーク識別子・タグ以降のコミット数・
コミット ID を付けます。例: `1.2.2-pre.1.hkrhd.2.g0123456789ab`。
作業中の変更があれば `.dirty` が付きます。upstream のバージョンファイルは変更しません。
アプリの数値ビルド番号には、履歴全体のコミット数を使います。
意図的に指定するときは `MELTYPE_VERSION=... bash mac/update.sh` を使います。

CI もフォークのブランチでは同じバージョンでビルドし、実エンジンの辞書回帰テストを行います。
フォーク版は upstream の自動更新ではなく、このリポジトリから更新してください。
