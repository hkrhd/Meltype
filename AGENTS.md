# このフォークの開発

- 独自変更とデフォルトブランチは `fork_by_hkrhd`。upstream は `main@upstream` を直接使う。
- フォークの文書は `fork/`・`tests/fork/` に置き、コードを読めば分かることは書かない。README.md は説明・主な変更・ライセンスだけ。upstream の `docs/` は復活させない。
- 作業に応じて読む: 要望・修正は [fork/development.md](fork/development.md)、検証は [tests/fork/README.md](tests/fork/README.md)、配布・Actions は [fork/release.md](fork/release.md)、upstream の取り込みは [fork/upstream-intake.md](fork/upstream-intake.md)。
- **Linux で `tests/fork/local-check.sh` の一式に合格してから `fork_by_hkrhd` を push する**（文書だけなら不要）。Actions は配布のときだけ回す。
- 組み込み辞書への追加は `dictionaries/fork/` の同名ファイルに置き、upstream の `dictionaries/*.txt` は変えない。Zenzai の重みは upstream に任せる。
- 追加テストは `tests/fork/`・`mac/Tests/ForkMacTests/` に置き、ユーザーが求める振る舞い・E2E を検証する。辞書個別対応は最終手段（記号は可）。

## ユーザーへの確認

次の場合は止めて確認し、回答まで進めない（無人実行では question ツール）。

- テストの追加・変更・削除。「入力・変更前後の期待値・理由」の表と、期待値を緩めていないか・フォークの振る舞いを消していないか・不要の根拠（upstream のコミット）の点検結果を添える。期待値を変えずに upstream の API 変更へ呼び出しを合わせるだけなら確認せず、最後の報告に書く。
- フォークと upstream の要件が矛盾し、影響が大きいとき。
- 同じ問題で2回続けて失敗したとき。試したこと・失敗の要点・URL・次の案を添える。
- 履歴の書き換え、force push、Release・タグの削除。
