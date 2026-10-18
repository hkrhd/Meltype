変更したらREADME.mdに簡潔に追加する。

# このフォークの開発

- 履歴操作は jj。`main` は `upstream/main` 追従専用。独自変更は `fork_by_hkrhd` に置く。
- upstream の取り込みは Codex が差分と変更意図を確認し、フォーク独自の挙動・方針を保って調整する。競合がない場合も機械的な merge/rebase だけで完了としない。
- 作業後に適切にコミットして.
- 検証・ビルドのみ：`bash mac/build-cli.sh --test --build`。
- 適用：`bash mac/update.sh`。フォーク版番号を生成し、テスト・実変換検証後にインストール・起動・入力ソース選択まで行う。
- upstream の版定義は変更しない。版番号と更新の詳細は [docs/FORK.md](docs/FORK.md)。

Actions は upstream/main を main に反映し、main → fork_by_hkrhd の PR を作成する。ユーザーが PR を確認して Codex に依頼するまで、独自ブランチへの取り込みは行わない。
