# AGENTS.md

このフォークで作業する AI エージェント (Claude Code・Codex など) の決まりです。
upstream の `AGENTS.md` は適用しません (フォークの決まりはこのファイルが正です)。

コマンドと手順は [docs/FORK.md](docs/FORK.md) にまとめています。ここには書きません。

## 構成

| 場所                        | 中身                                                                                                                   |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `src/Meltype.Core`          | OS によらない判定・変換のコア (Composition / Detection / Input / Config / Diagnostics)。判定・変換を直すときはまずここ |
| `src/Meltype.Core.Tests`    | コアのテスト (どの OS でも動く)                                                                                        |
| `src/Meltype`               | Windows 版 (TSF・UI・更新)                                                                                             |
| `src/Meltype.Tests`         | Windows 版のテスト (Windows でしか動かない)                                                                            |
| `src/Meltype.Mac.Native`    | Mac 版から呼ぶコアの出口                                                                                               |
| `native/tip`・`native/mozc` | ネイティブの部分 (TSF の TIP・Mozc)                                                                                    |
| `mac/`                      | Mac 版 (Swift)                                                                                                         |
| `linux/`                    | Linux 版 (fcitx5・ibus) とパッケージの作成                                                                             |
| `web/`                      | Web (Cloudflare Workers・報告フォーム)                                                                                 |
| `dictionaries/`             | 辞書 (英単語・固有名詞・同音異義語の候補・文脈の手がかり)                                                              |
| `tools/`                    | 辞書の生成・検査、ベンチマーク、テスト用のスクリプト                                                                   |
| `docs/`                     | 使い方・開発・設計の文書                                                                                               |

## ビルドとテスト

[docs/FORK.md](docs/FORK.md) の「コマンド」を見てください。

# このフォークの開発

- 変更したら README.md に簡潔に追加し、[docs/FORK.md](docs/FORK.md) の手順でローカルに適用してからコミット・プッシュする。
- `upstream/main` に追従する。独自変更は `fork_by_hkrhd` に置く。
- fork 版番号と更新は [docs/FORK.md](docs/FORK.md)。
- 辞書個別対応は最終手段とする(キリがないので.記号は辞書的な決め打ちでOK)
- モデル更新・ビルド・比較検証後は、成功を確認して現行作業に必要ない旧モデル・旧ランタイム・一時アプリなどの不要な生成物を削除する。
- github actionsは追加した更新通知のみ.upstreamのactionsは無効化
