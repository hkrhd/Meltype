# Zenzai モデルの更新候補

## 現在使用しているモデル

- 配布先: https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf
- バージョン: v3.1 small / Q5_K_M
- リビジョン: `ddf6e44b2e05ab7ea9a3e31559c5e7948761365c`
- SHA-256: `4de930c06bef8c263aa1aa40684af206db4ce1b96375b3b8ed0ea508e0b14f6c`

## 更新候補

- 配布先: https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf
- バージョン: v3.2 small / Q5_K_M
- ファイル: `ggml-model-Q5_K_M.gguf`
- リビジョン: `c67e03e07d215c869f591b274c1631170d3e11fe`
- SHA-256: `29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673`
- サイズ: 73871936 bytes
- ライセンス: `apache-2.0`
- 固定取得 URL: https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf
- モデルカード・ライセンス確認先: https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/blob/c67e03e07d215c869f591b274c1631170d3e11fe/README.md

## 確認・適用

ユーザーがこの PR を確認した後、Codex に更新を依頼してください。
この PR は更新候補の記録だけを追加します。実際のモデル設定は変更していません。

- モデルカードと変更内容を読み、ライセンスおよび固定中の変換エンジン・Metal ランタイムとの互換性を確認する。
- フォーク独自の変換挙動・small / Q5_K_M・ニューラル評価上限2回を保つ。
- 必要に応じてモデル取得先・SHA-256、同梱リソース名、変換器の世代設定、ライセンス表記、関連文書を整合させる。
- `bash mac/build-cli.sh --test --build` と `bash tests/fork/mac/check-inputs.sh` で検証し、変換品質・性能と結果を報告する。

自動マージや実機へのインストールは行いません。
