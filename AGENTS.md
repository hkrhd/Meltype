# このフォークの開発

- upstream の `AGENTS.md` はこの内容で上書きする。運用手順は [README.md](README.md#ビルドと実機適用) に集約し、`docs/` は復活させない。
- 回答・コミットメッセージは日本語。変更点を README.md に簡潔に記載する。
- 履歴操作には jj を使う。`main` は `upstream/main` の追従用、独自変更とデフォルトブランチは `fork_by_hkrhd`。
- **`bash mac/update.sh` による検証・実機適用に成功してからコミットを確定し、`fork_by_hkrhd` を進めて push する。** jj の作業内容の自動保存はコミット確定と区別する。
- 追加テストは `tests/fork/` と `mac/Tests/ForkMacTests/` に置き、ユーザーが求める振る舞い・E2E を検証する。
- 辞書個別対応は最終手段とする。記号は種類が少ないので可。
- 成功後は不要な旧モデル・旧ランタイム・一時アプリ・一時学習データを削除する。現行モデル・増分ビルドキャッシュ・取得済み依存・最新アプリ・検証結果は保持し、共有のシステムキャッシュとユーザーの学習データは削除しない。

## upstream の取り込み

1. 最新の `upstream/main` を取得し、分岐していないことを確認して `main` を進める。
2. 作業中の変更を保持し、`jj new fork_by_hkrhd main` で統合先を作って変更を引き継ぐ。
3. 競合がない箇所も変更意図を確認し、Zenzai・半角記号など独自の挙動を維持する。削除済みのドキュメントは復活させない。判断に迷ったら質問する。
4. README.md を更新して実機に適用する。成功後、`fork_by_hkrhd` と `main` を親に持つマージコミットを確定して push する。squash・rebase で取り込み元の履歴を平坦化しない。

通知の Draft PR は作業依頼として扱い、GitHub のマージボタンでは取り込まず、最新の `main` を使って調整する。
`main` が upstream から分岐していたら停止し、force push は行わない。`fork_by_hkrhd` も強制 push・削除は禁止。
必須 CI・必須レビューは設定せずローカルで検証し、更新依頼 PR があれば変更点・検証結果を記録する。
3つ以上の PR を出す場合は統合 PR も作成する。

## Actions とモデル更新

- upstream の Actions は無効化する。新しい upstream の CI・bot は登録前に `.github/disabled-workflows/` へ移す。
- このフォークの `upstream-update`・`zenzai-update`・`windows` を維持する。CI/CD を新設・変更したら一度手動実行して成功を確認する。
- upstream 同期は書き込み可能な SSH デプロイキーを使う。公開鍵は Deploy keys、秘密鍵は `upstream-sync` Environment の `UPSTREAM_SYNC_SSH_KEY` に置き、`fork_by_hkrhd` からだけ利用可能にする。PR 作成には `GITHUB_TOKEN` を使う。キーの廃止・交換時は両方更新する。
- Zenzai 更新通知は `.github/ZENZAI-UPDATE.md` の候補記録だけを変更する。同じ配布先・重みは再通知せず、説明文だけの変更・xsmall・別量子化形式は対象外。API 障害・必須情報の欠落は失敗として扱う。
- モデル更新では互換性・ライセンスを確認し、推論上限1回・2回の精度を比較する。低下がなければ1回に減らす。
- 配布物は Releases に保存し、Actions artifact は使わない。失敗した配布は下書きに残し、過去の公開リリース・タグは削除しない。
- Actions のキャッシュは無料枠10 GB内に収め、予算 `$0` と `Stop usage when budget limit is reached` を維持する。
