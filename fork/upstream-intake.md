# upstream の取り込み

upstream の最新の `main` を取り込み、フォークの全テストに合格した状態で `fork_by_hkrhd` を進めます。upstream が同じ問題を直したフォークの修正は捨て、upstream のやり方に寄せます。判断に迷う点は [AGENTS.md の「ユーザーへの確認」](../AGENTS.md#ユーザーへの確認)に従います。

upstream の更新はユーザーのホスト（sys）が2時間おきに確認し、OpenCode にこの手順での取り込みを依頼します。その場合は `jj workspace add` で作った作業用ワークスペース（会話の作業ディレクトリ）で行い、本体の作業コピーは読み取り専用として扱います（編集・コミット・push・`jj edit` での切り替えはしない）。作業用ワークスペースは取り込みの完了時に削除し、停止で中断したときは再開に使うため残します。最後に Linux の検証結果（ログのパス）、push した `fork_by_hkrhd` のコミット、手順3の合否の要約を報告します。

1. `jj git fetch --remote upstream --remote origin` で取得します。未取り込みは `jj log -r 'fork_by_hkrhd@origin..main@upstream'`。
2. **マージ**: `jj new fork_by_hkrhd main@upstream` で2親のマージコミットを作り、競合を解きます。squash で履歴を圧縮しません。
   - フォークの実装は upstream の新しい構造に移します（前回は `MeltypeSession` の処理を `ImeSession` へ移しました）。フォークのテストは期待値を変えずに upstream の新しい API・namespace へ呼び出しを合わせます。
   - 要件が矛盾すればフォークを優先します。upstream で増えた Actions は `.github/disabled-workflows/` へ移します。upstream の `README.md`・`AGENTS.md` はフォークの内容で上書きし、`docs/` は削除したままにします。
   - 競合を解く間は Core のテスト（`dotnet run --project src/Meltype.Core.Tests -c Release`）で確かめます。
3. **upstream 単体の検証**: `tests/fork/upstream-check.sh` で、`main@upstream` に作業コピーのフォークの Core テスト（`tests/fork/Core/ForkApi/` を除く）を載せて実行し、テストごとの合否を記録します。コンパイルできないテストはフォークにしかない API を使っているので `ForkApi/` へ移します（期待値は変えません）。
   - 合格したテストごとに、そのテストを足したフォークのコミットの実装側の変更をマージコミットから外し、Core テストを実行します。全テストに合格すれば外したままにします（upstream が同じ問題を解決済み）。不合格なら戻し、手順5で残した理由を書きます。
4. **検証**: `tests/fork/local-check.sh` の一式に合格するまで原因を特定して直します。無関係な箇所を推測で変えません。取り込みでは Actions を回しません。sys の定期実行から頼まれたときは、合格したら依頼文の合格記録ファイルに「検証した `fork_by_hkrhd` のコミットID ログのパス」を1行で書きます（定期実行の完了確認に使います）。
5. マージコミットの説明に、取り込んだ upstream のコミットとコミット数、upstream の主な変更とフォーク側の対応、手順3の合否の数と外した・残した実装（残した理由）、統合後のテスト件数を箇条書きします。文書には書きません。
6. origin に `request/` のブランチがあれば、push せずにそのことを報告して終えます（要望の作業が優先で、終わると sys の定期実行がこの会話に続きを頼みます）。`fork_by_hkrhd@origin` がマージコミットの親より進んでいれば、`jj rebase -s <マージコミット> -d fork_by_hkrhd@origin -d main@upstream` で載せ直し、手順4からやり直します。どちらでもなければ `jj bookmark set fork_by_hkrhd -r <マージコミット>` と `jj git push --bookmark fork_by_hkrhd` で進めます（force push はしません）。最後に作業ブランチを削除します。[配布](release.md)は sys の定期実行が upstream のリリースに合わせて行うので、取り込みの作業では実行しません。
7. 成功後は不要な旧モデル・旧ランタイム・一時アプリ・一時学習データを削除します。現行モデル・増分ビルドキャッシュ・取得済み依存・最新アプリ・検証結果、共有のシステムキャッシュとユーザーの学習データは残します。
