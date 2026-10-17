# Meltype（個人フォーク）

[yksr-melt/Meltype](https://github.com/yksr-melt/Meltype) のフォークです。基本的に upstream の `main` に追従します。

変更点：

- ユーザー辞書が単語の途中を分断する誤変換を修正（例：`かん → 燗` の登録で `かんきせん → 燗汽船` になる問題）。
- upstream 同期と、検証付きの Mac 版更新・フォーク版番号の付与を自動化。詳細は [運用手順](docs/FORK.md)。

ライセンス：[GPL-3.0-or-later](LICENSE)。
