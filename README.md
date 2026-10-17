# Meltype（個人フォーク）

[yksr-melt/Meltype](https://github.com/yksr-melt/Meltype) のフォークです。upstream の `main` に追従します。

変更点：

- ユーザー辞書が単語の途中を分断する誤変換を修正（例：`かん → 燗` の登録で `かんきせん → 燗汽船` になる問題）。
- `.` は直前がかな・漢字・長音なら `。`、それ以外は半角の `.` を入力（未確定・確定済みの両方に対応）。
- Mac の変換に Zenzai small（Metal、ニューラル評価上限2回）を使用。モデルはビルド時に取得・検証し、起動時にウォームアップする。更新時はmacOSが自動起動したIMEも認識する。[計測方法と結果](docs/ZENZAI-PERFORMANCE.md)。

ライセンス：[GPL-3.0-or-later](LICENSE)。
