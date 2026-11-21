# このフォークの開発

- upstream の `AGENTS.md` はこの内容で上書きする。手順は README.md に集約し、`docs/` は復活させない。
- 独自変更とデフォルトブランチは `fork_by_hkrhd`。upstream は `main@upstream` を直接使う。
- **作業ブランチで `windows` を手動実行（配布なし）し Windows・Mac の全検証に合格してから `fork_by_hkrhd` を進めて push する**（[ビルドと検証](README.md#ビルドと検証)）。ドキュメントだけの変更は不要。
- upstream の取り込みは [README.md の手順](README.md#upstream-の取り込み)に従う。Zenzai の重みは upstream の更新に任せる。
- 追加テストは `tests/fork/`・`mac/Tests/ForkMacTests/` に置き、ユーザーが求める振る舞い・E2E を検証する。辞書個別対応は最終手段（記号は可）。
- upstream の CI・bot は `.github/disabled-workflows/` へ移す。フォークの Actions は `windows` だけ。

## ユーザーへの確認

次の場合は止めて確認し、回答まで進めない（無人実行では question ツール）。

- テストの追加・変更・削除。「入力・変更前後の期待値・理由」の表に、期待値を実装に合わせて緩めていないか、フォークの振る舞いを消していないか、不要になった根拠（upstream のコミット）の点検結果を添える。期待値を変えずに upstream の API 変更へ呼び出しを合わせるだけなら確認せず、最後の報告に書く。
- フォークと upstream の要件が矛盾し、影響が大きいとき。
- 同じ問題で2回続けて失敗したとき。試したこと・失敗の要点・Actions の URL・次の案を添える。
- 履歴の書き換え、force push、Release・タグの削除。
