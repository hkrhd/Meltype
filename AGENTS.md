# このフォークの開発

- upstream の `AGENTS.md` はこの内容で上書きする。手順は README.md に集約し、`docs/` は復活させない。
- 独自変更とデフォルトブランチは `fork_by_hkrhd`。upstream は `main@upstream` を直接使う。
- 修正は `tests/fork/local-check.sh` の `--inputs`・`--core` で再現させてから直す。
- **Linux で `tests/fork/local-check.sh` の一式に合格してから `fork_by_hkrhd` を進めて push する**（文書だけなら不要）。Actions は配布のときだけ回す。要望は push 後に配布する。
- upstream の取り込みは [README.md の手順](README.md#upstream-の取り込み)に従う。Zenzai の重みは upstream に任せる。
- 組み込み辞書への追加は `dictionaries/fork/` の同名ファイルに置き、upstream の `dictionaries/*.txt` は変えない。
- 追加テストは `tests/fork/`・`mac/Tests/ForkMacTests/` に置き、ユーザーが求める振る舞い・E2E を検証する。フォークにしかない API を使う Core テストは `tests/fork/Core/ForkApi/`。辞書個別対応は最終手段（記号は可）。
- upstream の CI・bot は `.github/disabled-workflows/` へ移す。

## ユーザーへの確認

次の場合は止めて確認し、回答まで進めない（無人実行では question ツール）。

- テストの追加・変更・削除。「入力・変更前後の期待値・理由」の表と、期待値を緩めていないか・フォークの振る舞いを消していないか・不要の根拠（upstream のコミット）の点検結果を添える。期待値を変えずに upstream の API 変更へ呼び出しを合わせるだけなら確認せず、最後の報告に書く。
- フォークと upstream の要件が矛盾し、影響が大きいとき。
- 同じ問題で2回続けて失敗したとき。試したこと・失敗の要点・URL・次の案を添える。
- 履歴の書き換え、force push、Release・タグの削除。
