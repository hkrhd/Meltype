変更したらREADME.mdに簡潔に追加する。

# このフォークの開発

- 履歴操作は jj。`main` は `upstream/main` 追従専用。独自変更は `fix/userdict-head-contamination` に置く。
- 作業後に適切にコミットして.
- 検証・ビルドのみ：`bash mac/build-cli.sh --test --build`。
- 適用：`bash mac/update.sh`。フォーク版番号を生成し、テスト・実変換検証後にインストール・起動・入力ソース選択まで行う。
- upstream の版定義は変更しない。版番号と更新の詳細は [docs/FORK.md](docs/FORK.md)。
