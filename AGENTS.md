# このフォークの開発

- upstream の `AGENTS.md` はこの内容で上書きする。運用手順は [README.md](README.md#ビルドと実機適用) に集約し、`docs/` は復活させない。
- `main` は `upstream/main` の追従用、独自変更とデフォルトブランチは `fork_by_hkrhd`。
- **`bash mac/update.sh` による検証・実機適用に成功してからコミットを確定し、`fork_by_hkrhd` を進めて push する。** jj の作業内容の自動保存はコミット確定と区別する。
- 追加テストは `tests/fork/` と `mac/Tests/ForkMacTests/` に置き、ユーザーが求める振る舞い・E2E を検証する。
- 辞書個別対応は最終手段とする。記号は種類が少ないので可。
- 成功後は不要な旧モデル・旧ランタイム・一時アプリ・一時学習データを削除する。現行モデル・増分ビルドキャッシュ・取得済み依存・最新アプリ・検証結果は保持し、共有のシステムキャッシュとユーザーの学習データは削除しない。

## upstream の取り込み

1. 最新の `upstream/main` を取得. まず純粋なupstreamのコードでどの程度フォークのテストに合格するか見る。
2. 合格になった項目を修正するフォークの内容は破棄。テストはそのまま残す。不合格の内容を修正する内容を取り込んだfork_by_hkrhd と `main` を親に持つマージコミットを作成し全てのテストに合格を確認する。squashで履歴圧縮しない。first principal thinkingで. フォークとupstreamで矛盾する要件ならフォークを優先する。
3. README.md を更新して実機に適用する。成功後push する。

## Actions とモデル更新

- upstream の Actions は無効化する。新しい upstream の CI・bot は登録前に `.github/disabled-workflows/` へ移す。
- このフォークの `upstream-update`・`zenzai-update`・`windows` を維持する。CI/CD を新設・変更したら一度手動実行して成功を確認する。
- upstream 同期は書き込み可能な SSH デプロイキーを使う。公開鍵は Deploy keys、秘密鍵は `upstream-sync` Environment の `UPSTREAM_SYNC_SSH_KEY` に置き、`fork_by_hkrhd` からだけ利用可能にする。PR 作成には `GITHUB_TOKEN` を使う。キーの廃止・交換時は両方更新する。
- Zenzai 更新通知は `.github/ZENZAI-UPDATE.md` の候補記録だけを変更する。同じ配布先・重みは再通知せず、説明文だけの変更・xsmall・別量子化形式は対象外。API 障害・必須情報の欠落は失敗として扱う。
- モデル更新では互換性・ライセンスを確認し、推論上限1回・2回の精度を比較する。低下がなければ1回に減らす。
- 配布物は Releases に保存し、Actions artifact は使わない。失敗した配布は下書きに残し、過去の公開リリース・タグは削除しない。
- Actions のキャッシュは無料枠10 GB内に収め、予算 `$0` と `Stop usage when budget limit is reached` を維持する。
