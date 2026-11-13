# Meltype（個人フォーク）

[yksr-melt/Meltype](https://github.com/yksr-melt/Meltype) に、Mac の変換精度と記号入力を調整した変更を加えたフォーク。独自変更は `fork_by_hkrhd` に置く。

## 主な変更

### 変換精度

- Mac の漢字変換に Zenzai small v3.2（Metal）を使う。同音異義語はモデルと辞書の候補から選べる。
- 日本語の読みから生成された小文字英単語は候補の後ろに回す（`fo-matta → フォーマッタ`）。英語の直接入力・略語・ユーザー辞書の表記は維持する。
- 日英の区切り判定、最後の文節からの予測、あいさつの補完、括弧・8桁の日付の候補を追加。
- かなのまま残った部分は学習で自動上書きしない。単独入力の学習と候補の選び直しは維持する。
- 短い登録語で終助詞の先頭だけを切り出さず、読み全体の学習を分割より優先する（`けい → 径` があっても、一度選んだ `keisann → 計算` を維持）。直前に日本語があっても、Space・Enterの前から学習した表記で表示する。
- 日数・回数を英字にしない（`1niti1kai → 1日1回`）。`2kani` などには「日に」の候補も出す。
- 独立した「なん」の直後が英字なら「何」を優先する（`nancm → 何cm`、`nanmm → 何mm`）。単位を個別登録せず扱い、「なん」も候補に残す。

### 英語入力

- 英単語の補完候補を、英語判定前でも英字3文字から表示。Tab／Shift+Tab で選び、Enter か続けての入力で確定する（Mac はクリックも可）。
- 英語辞書に登録した単独の語は英字を優先し、日本語の語の途中は分断しない。短い読みで長い語や送り仮名を分断する誤変換も抑える。
- 固有名詞辞書の登録表記を通常入力の表示・確定と、ファイル名の拡張子の前に自動適用する（`github → GitHub`、`AGENTS` を登録すると `agents → AGENTS`・`agents.md → AGENTS.md`）。URL・パス等の保護範囲と F9/F10 で明示した表記は維持する。
- 英字の後ろの助詞や、短い英単語に続く日本語を保つ（`mainno → mainの`、`macnanode → macなので`）。小文字の `no` は「の」と表示し、Space で英語の `no ` を確定する。
- `auto` など、かなでも読める4文字以上の単独の英単語は Space で英字と空白を確定する。日本語由来の語や、よく使う日本語は変換を優先する。
- 日本語の途中では、かなで読める語を英字学習だけで分断しない（`プロンプtotoして → プロンプトとして`）。英単語・英文中の学習は維持する。
- `lじ`（`lji`）は「L字」を先頭候補にする。ショートカット表記はかなにせず、修飾キーだけ大文字にする（`c-s-a → C-S-a`）。

### 記号

- `.` は直前がかな・漢字・長音なら `。`、それ以外は半角。未確定・確定済みの両方に対応する。
- `$`・`"`・バッククォート・`_`・`/` は半角を維持し、未確定の語がなければ即確定する。
- `#`・`-`・`~`・`+`・`&` だけの入力に続く Space は、記号と半角空白を確定する。
- `---` など3個以上続くハイフンは、入力中・変換・確定を通して半角を維持する。通常の長音入力は維持する。
- `～` の直後に `/` を入力すると、半角の `~/` にする。

### macOS 連携

- 辞書ファイル（`dictionaries/` の対応辞書・取込 plist と `userdict.txt`）は保存後に自動反映する。入力中なら確定・取消後に切り替え、再起動は不要。OS の変更通知を使い、定期ポーリングはせず、連続通知は250ミリ秒にまとめる。
- テキスト置換もユーザー辞書へ自動同期して即時反映する。macOS 側を正として、Meltype 側の独自登録も置き換える。
- 画面移動後の候補表示、矢印キー、辞書取込画面を修正する。

## ビルドと実機適用

Mac は Apple Silicon・macOS 13.3 以降が対象。.NET 10 SDK（10.0.403 以降）、Xcode、CMake が必要です。

```sh
bash mac/build-cli.sh --test --build   # Core・Swift のテストとビルド
bash mac/update.sh                    # 入力検証・実機適用・入力ソース選択まで実行
```

入力検証は一時的な辞書・設定・学習データで実行します。Xcode の場所を変える場合は `DEVELOPER_DIR` を指定します。

```sh
dotnet run --project src/Meltype.Core.Tests
dotnet run --project src/Meltype.Core.Tests -- --eval
dotnet run --project src/Meltype.Core.Tests -- --repro kyouhagoogle enter
node tools/check-dictionaries.mjs       # 辞書を変更したとき
python3 tools/mcfly-terms.py --min-count 3  # 英語辞書に足す語をシェル履歴から探す（履歴本文は出さない）
bash mac/benchmark-conversion.sh        # Zenzai の速度・精度比較
```

McFly の集計結果は自動で辞書に追加されません。簡易解析のため、個人情報や不要な語が混ざっていないか公開・登録前に確認してください。

Zenzai のモデル・Metal ランタイムはビルドスクリプトで取得します。モデル更新時は推論上限1回・2回を比較します。
`--convert` と `--benchmark-conversion` の `--inference-limit 1`〜`5` で比較でき、測定結果は `mac/.build/benchmarks/` に残ります。

版番号は `mac/fork-version.sh` が upstream のタグとコミットから生成します。実機適用はコミット前なので `.dirty` が付きます。
必要なら `MELTYPE_VERSION=... bash mac/update.sh` で指定できます。upstream のバージョンファイルは変更しません。

## 更新と配布

2026-11-13 に upstream の 1.5.0 系列（`c67c1aae`、696コミット）を統合しました。
共通化された入力処理と辞書の共有構造に合わせて独自機能を移植し、upstream 単体で合格した日数・回数などの修正は外しました。
基準測定はフォークの Core テスト35件中7件合格（失敗28件中2件はAPI未対応）。統合後は Core 909件・Swift 43件が合格しています。

フォーク版は自動更新の対象外です。[Releases](https://github.com/hkrhd/Meltype/releases) の ZIP、または上記の実機適用コマンドで更新します。
Mac の ZIP は展開して `Install Meltype.command` を実行します。Homebrew Cask・apt は upstream 版向けです。

- `upstream-update`: 2日に1回、日本時間21:17に `main` を同期し、更新依頼の Draft PR を作成します。
- `zenzai-update`: 12時間ごとに small / Q5_K_M の更新を Draft PR で通知します。取り込み・モデル差し替え・自動マージはしません。
- `windows`: push・PR で Windows を検証します。手動実行では Windows・Mac の配布物を作成します。

```sh
gh workflow run windows.yml --repo hkrhd/Meltype --ref fork_by_hkrhd
GITHUB_REPOSITORY=hkrhd/Meltype node .github/bot/zenzai-update.mjs --dry-run
```

Windows の通常版 ZIP・ポータブル版 ZIP・インストーラーと Mac の ZIP がそろうとプレリリースを公開し、失敗時は下書きに残します。
署名の設定がない場合、Mac は ad-hoc 署名、Windows は未署名です。配布物は Releases に保存します。
開発ルールは [AGENTS.md](AGENTS.md) に集約し、旧 `docs/` の説明・画像は削除しました。

ライセンス：[GPL-3.0-or-later](LICENSE)。
