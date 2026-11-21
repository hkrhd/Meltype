# Meltype（個人フォーク）

[yksr-melt/Meltype](https://github.com/yksr-melt/Meltype) に、Mac の変換精度と記号入力を調整した変更を加えたフォーク。独自変更は `fork_by_hkrhd` に置く。

## 主な変更

### 変換精度

- 日本語の読みから生成された小文字英単語より日本語候補を優先する（`fo-matta → フォーマッタ`）。英語の直接入力・略語・ユーザー辞書の表記は維持する。
- 日英の区切り判定、最後の文節からの予測、あいさつの補完、括弧・8桁の日付の候補を追加。
- かなのまま残った部分は学習で自動上書きしない。単独入力の学習と候補の選び直しは維持する。
- 短い登録語で終助詞の先頭だけを切り出さず、読み全体の学習を分割より優先する（`けい → 径` があっても、一度選んだ `keisann → 計算` を維持）。直前に日本語があっても、Space・Enterの前から学習した表記で表示する。
- 日数・回数を英字にしない（`1niti1kai → 1日1回`）。`2kani` などには「日に」の候補も出す。
- 独立した「なん」の直後が英字なら「何」を優先する（`nancm → 何cm`、`nanmm → 何mm`）。単位を個別登録せず扱い、「なん」も候補に残す。

### 英語入力

- 英単語の補完候補を、英語判定前でも英字3文字から表示。Tab／Shift+Tab で選び、Enter か続けての入力で確定する（Mac はクリックも可）。
- 英語辞書に登録した単独の語は英字を優先し、日本語の語の途中は分断しない。短い読みで長い語や送り仮名を分断する誤変換も抑える。ユーザー辞書に登録した読みは英単語に分断しない（`masudatokubee → 増田徳兵衛`）。英単語と同じ綴りの読みは日本語の直後だけ（`べえ → 兵衛` で `jinbee → 甚兵衛`、単独の `bee` は英字）。
- 固有名詞辞書の登録表記を通常入力の表示・確定と、ファイル名の拡張子の前に自動適用する（`github → GitHub`、`AGENTS` を登録すると `agents → AGENTS`・`agents.md → AGENTS.md`）。ユーザー辞書の表記を同梱辞書より優先する（`claude` を登録すると `Claude → claude`）。URL・パス等の保護範囲と F9/F10 で明示した表記は維持する。
- 英字の後ろの助詞や、短い英単語に続く日本語を保つ（`mainno → mainの`、`macnanode → macなので`）。小文字の `no` は「の」と表示し、Space で英語の `no ` を確定する。
- `auto` など、かなでも読める4文字以上の単独の英単語は Space で英字と空白を確定する。日本語由来の語や、よく使う日本語は変換を優先する。
- 日本語の途中では、かなで読める語を英字学習だけで分断しない（`プロンプtotoして → プロンプトとして`）。英単語・英文中の学習は維持する。
- 3音のカタカナ語を、後ろの英単語と同じ綴りで分断しない（`sukirude → スキルで`、`apudego → アプデ後`）。2音の語は英単語の一部に現れやすいので対象外。
- `lじ`（`lji`）は「L字」を先頭候補にする。ショートカット表記はかなにせず、修飾キーだけ大文字にする（`c-s-a → C-S-a`）。

### 記号

- `.` は直前がかな・漢字・長音なら `。`、それ以外は半角。未確定・確定済みの両方に対応する。
- `$`・`"`・バッククォート・`_`・`/` は半角を維持し、未確定の語がなければ即確定する。
- `#`・`-`・`~`・`+`・`&` だけの入力に続く Space は、記号と半角空白を確定する。
- `---` など3個以上続くハイフンは、入力中・変換・確定を通して半角を維持する。通常の長音入力は維持する。
- 英語と判定した語の直前のハイフンは半角にする（`-r`・`--force` などのコマンドのオプション）。後ろが日本語なら長音のまま。
- `～` の直後に `/` を入力すると、半角の `~/` にする。

### macOS 連携

- 辞書ファイル（`dictionaries/` の対応辞書・取込 plist と `userdict.txt`）は保存後に自動反映する。入力中なら確定・取消後に切り替え、再起動は不要。OS の変更通知を使い、定期ポーリングはせず、連続通知は250ミリ秒にまとめる。
- テキスト置換もユーザー辞書へ自動同期して即時反映する。macOS 側を正として、Meltype 側の独自登録も置き換える。
- 画面移動後の候補表示、矢印キー、辞書取込画面を修正する。

## ビルドと検証

変更の検証は GitHub Actions で行うため、作業する OS は問いません（Ubuntu でも可）。作業ブランチを push し、配布なしで `windows` を手動実行して Windows・Mac の全検証（Core・Swift のテスト、実エンジンの入力検証、辞書の再読込、NativeAOT 境界）に合格したら `fork_by_hkrhd` を進めます。

```sh
git push origin HEAD:refs/heads/verify/<作業名>
gh workflow run windows -R hkrhd/Meltype --ref verify/<作業名>
gh run watch -R hkrhd/Meltype "$(gh run list -R hkrhd/Meltype --workflow windows --branch verify/<作業名> --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

合格後は作業ブランチを削除します。`fork_by_hkrhd` への push で配布され、利用者の Mac・Windows は自動更新で入れ替わります。

手元の Mac でビルドする場合、対象は Apple Silicon・macOS 13.3 以降。.NET 10 SDK（10.0.403 以降）と Xcode が必要です。
漢字変換は upstream と同じ Mozc の変換ヘルパーと Zenzai（llama-server・zenz-v3.2-small）で、Zenzai はビルドスクリプトが取得します。
Mozc の変換ヘルパーは `native/mozc/build-mozc-helper.sh`（Bazelisk が必要、初回30〜40分）で `native/mozc/bin/mac/` に作るか、`native/mozc/` が同じ upstream リリースの Mac 版 ZIP の `Meltype.app/Contents/Resources/mozc/` から置きます。

```sh
bash mac/build-cli.sh --test --build   # Core・Swift のテストとビルド
bash tests/fork/mac/check-inputs.sh   # 実エンジンの入力検証（一時的な辞書・設定・学習データ）
```

Xcode の場所を変える場合は `DEVELOPER_DIR` を指定します。

```sh
dotnet run --project src/Meltype.Core.Tests
dotnet run --project src/Meltype.Core.Tests -- --eval
dotnet run --project src/Meltype.Core.Tests -- --repro kyouhagoogle enter
node tools/check-dictionaries.mjs       # 辞書を変更したとき
python3 tools/mcfly-terms.py --min-count 3  # 英語辞書に足す語をシェル履歴から探す（履歴本文は出さない）
```

McFly の集計結果は自動で辞書に追加されません。簡易解析のため、個人情報や不要な語が混ざっていないか公開・登録前に確認してください。

配布の版番号は `mac/fork-version.sh` が upstream のタグとコミットから生成します。upstream のバージョンファイルは変更しません。

## 更新と配布

2026-11-21 に upstream の 1.7.0（`b661f03d`、前回から40コミット）を統合しました。upstream が Mac の候補の一覧と入力案内を 1 つのパネル（`CompositionPanel`）にまとめたので、フォークの辞書の再読込と更新メニューは新しい `InputController` に移しました。「ばーじょん」の候補には Zenzai の設定・Linux のフロント・別ビルドの Meltype IME が加わっています。
upstream 単体ではフォークのテストをコンパイルできませんでした（`CompositionDetector.UserDictionary`・`MeltypeRuntime.ReloadDictionaries`・`ZenzaiConverterTests.FakeServer` の可視性）。upstream 単体の合否は測れず、フォークの実装はすべて残しています。統合後は Core 971件・Swift 52件と Windows の検証が合格しています。

[Releases](https://github.com/hkrhd/Meltype/releases) から自動更新し、版の数字（`1.7.0-hkrhd.<ビルド番号>.g…`）のビルド番号で新旧を比べます。Mac 版は6時間ごとに確認して新しい版を準備し、macOS の通知で知らせます。勝手には入れ替えず、通知のクリックか入力メニューの「Meltype ビルド N に更新して再起動」で入れ替えます（失敗した版は再試行しない）。記録は `~/Library/Caches/io.github.yksr-melt.inputmethod.Meltype/update/install.log`、停止は `config.json` の `AutoUpdate: false`。
Windows 版は upstream と同じく次のサインイン時に入れ替えます。「プレリリース版も自動で更新する」を OFF にすると止まります（フォークの配布はすべてプレリリース）。
Mac の ZIP は展開して `Install Meltype.command` を実行します。Homebrew Cask・apt は upstream 版向けです。

upstream の Actions は GitHub 側でも無効化しています。フォークの Actions は `fork-windows.yml` の `windows` だけです。push・PR では変更に関係する Windows のビルド・テスト・配布スクリプト検証を実行し、`fork_by_hkrhd` への push（Mac の変更も含む）と、手動実行で `package` を有効にした場合に Windows・Mac の配布物を作成します。
upstream の更新はユーザーのホスト（sys）が2時間おきに確認し、OpenCode に下の手順での取り込みを依頼します。

```sh
gh workflow run fork-windows.yml --repo hkrhd/Meltype --ref fork_by_hkrhd  # 検証のみ
gh workflow run fork-windows.yml --repo hkrhd/Meltype --ref fork_by_hkrhd -f package=true  # 配布
```

Windows の通常版 ZIP・ポータブル版 ZIP・インストーラーと Mac の ZIP がそろうとプレリリースを公開し、失敗時は下書きに残します。
署名の設定がない場合、Mac は ad-hoc 署名、Windows は未署名です。配布物は Releases に保存します。
開発ルールは [AGENTS.md](AGENTS.md) に集約し、旧 `docs/` の説明・画像は削除しました。
配布物は Releases に保存し、Actions artifact は使いません。失敗した配布は下書きに残し、過去の公開リリース・タグは削除しません。
Actions のキャッシュは無料枠10 GB内に収め、予算 `$0` と `Stop usage when budget limit is reached` を維持します。

## upstream の取り込み

upstream の最新の `main` を取り込み、フォークの全テストに合格した状態で `fork_by_hkrhd` を進めます。upstream が同じ問題を直したフォークの修正は捨て、upstream のやり方に寄せます。判断に迷う点は [AGENTS.md の「ユーザーへの確認」](AGENTS.md#ユーザーへの確認)に従います。

1. `jj git fetch --remote upstream --remote origin` で取得します。未取り込みは `jj log -r 'fork_by_hkrhd@origin..main@upstream'`。
2. **upstream 単体の検証**: `main@upstream` を親に、フォークのテストと CI（`tests/fork/`・`mac/Tests/ForkMacTests/`・`.github/workflows/fork-windows.yml`・`.github/bot/windows-checks.mjs` と、それらを読み込む `src/Meltype.Core.Tests/Meltype.Core.Tests.csproj`・`mac/Package.swift` の該当行）だけを `fork_by_hkrhd` から持ち込んだコミットを作ります。`verify/upstream-<短縮ハッシュ>` に push して `windows` を手動実行し、フォークのテストごとの合否を記録します。ビルドできなければ理由を記録して進みます。
3. **マージ**: `jj new fork_by_hkrhd main@upstream` で2親のマージコミットを作り、競合を解きます。squash で履歴を圧縮しません。
   - 手順2で合格したテストに対応するフォークの実装は破棄し、テストは残します。
   - 不合格のテストに対応するフォークの実装は、upstream の新しい構造に移します（前回は `MeltypeSession` の処理を `ImeSession` へ移しました）。
   - 要件が矛盾すればフォークを優先します。upstream で増えた Actions は `.github/disabled-workflows/` へ移します。
4. **検証**: マージコミットを作業ブランチに push し直して `windows` を手動実行し、全検証に合格するまで Actions のログから原因を特定して直します。無関係な箇所を推測で変えません。
5. この README の「更新と配布」に、取り込んだ upstream のコミットとコミット数、手順2の合否の数、統合後のテスト件数、主な移植内容を書きます（前回分は置き換え）。マージコミットの説明にも upstream の主な変更とフォーク側の対応を箇条書きします。
6. `jj bookmark set fork_by_hkrhd -r <マージコミット>` と `jj git push --bookmark fork_by_hkrhd` で進めます（force push はしません）。push で走る `windows` の成功と、Release に Windows 3個・Mac 1個の配布物がそろったことを `gh run watch` などで確かめます。走らなければ上の配布の手動実行を使います。最後に作業ブランチを削除します。
7. 成功後は不要な旧モデル・旧ランタイム・一時アプリ・一時学習データを削除します。現行モデル・増分ビルドキャッシュ・取得済み依存・最新アプリ・検証結果、共有のシステムキャッシュとユーザーの学習データは残します。

ライセンス：[GPL-3.0-or-later](LICENSE)。
