# このフォークの開発

- 履歴操作は jj。`main` は `upstream/main` 追従専用。独自変更は `fix/userdict-head-contamination` に置く。
- upstream 取り込みは、作業をコミットしてから `bash tools/sync-upstream.sh`。競合を解消するまで導入しない。
- 変換制御は `src/Meltype.Core/Composition/`、Mac の実変換器は `mac/Sources/MeltypeIME/Converter.swift`。
- 検証・ビルドのみ：`bash mac/build-cli.sh --test --build`。Swift テストには Xcode が必要。
- 適用：`bash mac/update.sh`。フォーク版番号を生成し、テスト・実変換検証後にインストール・起動・入力ソース選択まで行う。
- 辞書変換を変更したら `bash mac/test-user-dictionary.sh` でも実エンジンを検証する。追加検証は `MELTYPE_DATA_DIR` でデータを隔離し、普段の辞書・学習データを使わない。
- upstream の版定義は変更しない。版番号と更新の詳細は [docs/FORK.md](docs/FORK.md)。
