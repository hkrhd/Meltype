# 配布

配布するのは、upstream の新しいリリースを取り込んだときと、ユーザーの要望による変更を `fork_by_hkrhd` に入れたときだけです。前者は、取り込んだ範囲に前回の配布にない upstream のリリースタグ（`v*`）があれば sys の定期実行が、後者は作業した会話が手動実行します。

```sh
gh workflow run fork-windows.yml --repo hkrhd/Meltype --ref fork_by_hkrhd  # 配布（Windows・Mac の全検証も行う）
```

- GitHub Actions は無料枠が小さく（Mac は課金係数10倍）、超えると止められます。予算 `$0` と `Stop usage when budget limit is reached` を維持し、配布以外では回しません（ワークフローは `fork_by_hkrhd` の手動実行でしか動きません）。
- 配布の実行が Windows・Mac 固有の検証（Swift のテスト、辞書の再読込、NativeAOT 境界、CPU の差で Zenzai の答えが変わる箇所など）を兼ね、落ちたら公開せず下書きに残します。配布だけが落ちたらホスト起因かを確かめ、手元で再現できる差なら `tests/fork/local-check.sh` を CI に合わせます。
- Actions のキャッシュは10 GBの9割まで使ってかまいません。7日使わないと消え、次の配布は遅くなります。
- 配布物は Releases に保存し、Actions artifact は使いません。過去の公開リリース・タグは削除しません。署名の設定がなければ Mac は ad-hoc 署名、Windows は未署名です。
- 版番号は `mac/fork-version.sh` が upstream のタグとコミットから作ります。upstream のバージョンファイルは変えません。
- upstream の Actions は `.github/disabled-workflows/` へ移し、GitHub 側でも無効化します。フォークの Actions は `fork-windows.yml` の `windows` だけです。

## 利用者の更新

[Releases](https://github.com/hkrhd/Meltype/releases) から自動更新し、版の数字（`1.7.0-hkrhd.<ビルド番号>.g…`）のビルド番号で新旧を比べます。Mac 版は6時間ごとに確認して新しい版を準備し、macOS の通知で知らせます。勝手には入れ替えず、通知のクリックか入力メニューの「Meltype ビルド N に更新して再起動」で入れ替えます（失敗した版は再試行しない）。記録は `~/Library/Caches/io.github.yksr-melt.inputmethod.Meltype/update/install.log`、停止は `config.json` の `AutoUpdate: false`。
Windows 版は upstream と同じく次のサインイン時に入れ替えます。「プレリリース版も自動で更新する」を OFF にすると止まります（フォークの配布はすべてプレリリース）。
Mac の ZIP は展開して `Install Meltype.command` を実行します。Homebrew Cask・apt は upstream 版向けです。
