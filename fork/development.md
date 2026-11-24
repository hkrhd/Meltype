# 要望・修正の作業の流れ

作業ブランチは、ユーザーの要望なら `request/<作業名>`、upstream の取り込みなら `verify/<作業名>` です。origin に `request/` のブランチがある間は sys の定期実行が新しい取り込みを始めず、進行中の取り込みは `fork_by_hkrhd` への push の前で待ちます。要望の作業は始めたらすぐ push し、取り込みの完了を待たずに進めます。

```sh
git push origin HEAD:refs/heads/request/<作業名>
```

1. `tests/fork/local-check.sh` の `--inputs`・`--core` で再現させてから直します（[検証](../tests/fork/README.md)）。
2. push の前に `jj git fetch` し、`fork_by_hkrhd@origin` が進んでいれば（先に取り込みが入ったなど）その上へ rebase して検証し直します。
3. `tests/fork/local-check.sh` の一式に合格したら `fork_by_hkrhd` を進めて push します（文書だけの変更なら検証は不要）。
4. 要望の変更なら、push 後に[配布](release.md)を手動実行し、Release に Windows 3個・Mac 1個がそろったことを確かめます。
5. `verify/` は `fork_by_hkrhd` を進めたら、`request/` は配布の後か要望をやめたときに削除します。
