// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

/// <summary>個人フォークで追加した入力動作の回帰テスト。</summary>
internal static partial class CompositionTests
{
    [Test]
    public static void Fork_QuestionBeforeEnglish_PrefersKanjiAndKeepsKanaSelectable()
    {
        foreach (var live in new[] { false, true })
        foreach (var suffix in new[] { "m", "cm", "mm", "kg", "GB", "px", "fps", "J" })
        foreach (var prefix in new[] { "nan", "nann" })
        {
            var k = new Keyboard(live: live);
            k.Type(prefix + suffix);
            if (live) Assert.Equal("何" + suffix, k.Showing, "ライブ変換で数量の疑問詞にする: " + prefix + suffix);
            k.Type(" ");
            Assert.Equal("何" + suffix, k.Showing, "Space で変換し、空白を勝手に確定しない: " + prefix + suffix);
            var kana = k.Host.View!.Candidates.ToList().IndexOf("なん");
            Assert.True(kana >= 0, "固有名詞などに使う「なん」も選べる");
            k.Type("\n");
            Assert.Equal("何" + suffix, k.Host.Document, "表示どおり確定する");

            var alternative = new Keyboard(live: live);
            alternative.Type(prefix + suffix + " ");
            alternative.Controller.SelectCandidate(alternative.Host.View!.Candidates.ToList().IndexOf("なん"));
            alternative.Type("\n");
            Assert.Equal("なん" + suffix, alternative.Host.Document, "かなの候補も確定できる");
            alternative.Type(prefix + suffix + " ");
            Assert.True(alternative.Host.View!.Candidates.Contains("何"), "かなを学習した後も「何」を選び直せる");
        }
    }

    [Test]
    public static void Fork_QuestionBeforeEnglish_KeepsWordsAndExplicitAlphabet()
    {
        foreach (var live in new[] { false, true })
        foreach (var (input, expected) in new[]
        {
            ("konnnannAPI", "こんなんAPI"), ("sonnnannAPI", "そんなんAPI"),
            ("nandemoAPI", "なんでもAPI"), ("nanteAPI", "なんてAPI"),
            ("nanny", "nanny"), ("Nancy", "Nancy"),
        })
        {
            var k = new Keyboard(live: live);
            k.Type(input + "\n");
            Assert.Equal(expected, k.Host.Document, "語中の「なん」や英単語を置き換えない: " + input);
        }
        var alphabet = new Keyboard(live: true);
        alphabet.Type("nanmm");
        alphabet.Press(VirtualKeys.F10);
        alphabet.Type("\n");
        Assert.Equal("nanmm", alphabet.Host.Document, "明示した英字入力を維持する");
    }

    [Test]
    public static void Fork_LongVowel_KeepsFormatterReadingJapanese()
    {
        foreach (var live in new[] { false, true })
        {
            var k = new Keyboard(live: live);
            k.Type("fo-matta");
            Assert.Equal("ふぉーまった", k.Showing, "長音を含む読みを英語に分断しない");
            k.Type(" \n");
            Assert.Equal("ふぉーまった", k.Host.Document, "変換器に日本語の読みを渡して確定する");
        }
    }

    [Test]
    public static void Fork_LShape_DefaultsToCapitalLAndKanji()
    {
        foreach (var live in new[] { false, true })
        foreach (var input in new[] { "lji" })
        {
            var k = new Keyboard(live: live);
            k.Type(input);
            if (live) Assert.Equal("L字", k.Showing, "ライブ変換中もL字を表示する");
            k.Type(" ");
            Assert.Equal("L字", k.Showing, $"{input}: live={live}");
            k.Type("\n");
            Assert.Equal("L字", k.Host.Document, "先頭候補をそのまま確定する");
        }
    }

    [Test]
    public static void Fork_ShortcutNotation_KeepsLettersAndCapitalizesModifiers()
    {
        foreach (var live in new[] { false, true })
        foreach (var (prefix, expectedPrefix) in new[] { ("c-", "C-"), ("c-s-", "C-S-"), ("c-a-", "C-A-") })
        foreach (var letter in "abcdefghijklmnopqrstuvwxyz")
        {
            var k = new Keyboard(live: live);
            k.Type(prefix + letter);
            Assert.Equal(expectedPrefix + letter, k.Showing, "入力中も英字で表示する: " + prefix + letter);
            k.Type("\n");
            Assert.Equal(expectedPrefix + letter, k.Host.Document, "修飾キーだけ大文字で確定する");
        }

        foreach (var (input, expected) in new[]
        {
            ("c-", "C-"), ("c-s-", "C-S-"), ("c-a-", "C-A-"),
            ("C-s-a", "C-S-a"), ("c-A-x", "C-A-x"), ("C-S-Z", "C-S-Z"),
            ("c-zh", "C-zh"), ("c-a-kana", "C-A-kana"), ("c-x c-s-a", "C-x C-S-a"),
            ("c-s-a\b\b\bi", "C-i"), ("camera", "camera"),
        })
        {
            var k = new Keyboard();
            k.Type(input + " ");
            Assert.Equal(expected + " ", k.Host.Document, "Space でショートカット表記と空白を確定する: " + input);
        }

        var japanese = new Keyboard();
        japanese.Type("ka-do\n");
        Assert.Equal("かーど", japanese.Host.Document, "変換前のかな入力では通常の長音を維持する（カタカナ変換の検証ではない）");
    }

    [Test]
    public static void Fork_DaysAndCounts_RemainJapaneseWhenNumbersRepeat()
    {
        foreach (var live in new[] { false, true })
        foreach (var (input, expected) in new[]
        {
            ("1niti1kai", "1にち1かい"), ("1nichi1kai", "1にち1かい"),
            ("1nitini1kai", "1にちに1かい"), ("2kani1kai", "2かに1かい"),
            ("3kani1kai", "3かに1かい"), ("4kani1kai", "4かに1かい"),
            ("10kani1kai", "10かに1かい"), ("1niti2kai", "1にち2かい"),
            ("1niti3kai", "1にち3かい"), ("2kani3kai", "2かに3かい"),
            ("12nichini10kai", "12にちに10かい"),
        })
        {
            var k = new Keyboard(live: live);
            k.Type(input + " ");
            Assert.Equal(expected, k.Showing, $"{input}: live={live}");
            k.Type("\n");
            Assert.Equal(expected, k.Host.Document, "表示どおり確定する: " + input);
        }
    }

    [Test]
    public static void Fork_DayCandidate_KeepsOtherMeaningsSelectable()
    {
        var converter = new SplitConverter(new()
        {
            ["2かに"] = [new("2かに", "2課に")],
            ["3かに"] = [new("3", "3"), new("かに", "課に")],
        });
        foreach (var live in new[] { false, true })
        foreach (var number in new[] { "2", "3" })
        {
            var k = new Keyboard(live: live, converter: converter);
            k.Type(number + "kani ");
            Assert.Equal(number + "課に", k.Showing, "元の先頭候補を維持する");
            if (k.Host.View!.Clauses!.Count > 1) k.Press(VirtualKeys.Right);
            var day = number == "2" ? "2日に" : "日に";
            var index = k.Host.View!.Candidates.ToList().IndexOf(day);
            Assert.True(index >= 0, "日にを候補から選べる: " + number);
            k.Controller.SelectCandidate(index);
            k.Type("\n");
            Assert.Equal(number + "日に", k.Host.Document, "日数の候補を確定する");
        }
    }

    [Test]
    public static void Fork_ReadableEnglishWord_SpaceCommitsTheWholeWord()
    {
        foreach (var live in new[] { false, true })
        foreach (var before in new[] { "", "English ", "I use ", "日本語" })
        foreach (var word in new[] { "auto", "make" })
        {
            var k = new Keyboard(live: live);
            k.Host.PrecedingText = before;
            k.Type(word + " ");
            Assert.Equal(word + " ", k.Host.Document, $"Space で単独の英単語と空白を確定する: {word}, live={live}, before={before}");
        }

        foreach (var live in new[] { false, true })
        foreach (var (input, expected) in new[]
        {
            ("auto", "あうと"), ("autogadeta", "あうとがでた"),
            ("site", "して"), ("made", "まで"), ("sushi", "すし"), ("kana", "かな"),
        })
        {
            var k = new Keyboard(live: live);
            k.Type(input);
            if (input != "auto") k.Type(" ");
            Assert.Equal(expected, k.Showing, "かな表示と日本語の変換を維持する: " + input);
        }

        var manual = new Keyboard { Level = DetectionLevel.Manual };
        manual.Type("auto ");
        Assert.Equal("あうと", manual.Showing, "手動判定では日本語を変換する");

        var separate = new Keyboard { SeparateKeyRoles = true };
        separate.Type("auto ");
        Assert.True(separate.Host.View?.Converting == true, "キーの役割を分ける設定では候補を開く");

        var shifted = new Keyboard();
        shifted.Type("auto");
        shifted.Key(VirtualKeys.LShift);
        shifted.Press(VirtualKeys.Space);
        shifted.Key(VirtualKeys.LShift, up: true);
        Assert.Equal("あうと", shifted.Showing, "Shift+Space では日本語を変換できる");
    }

    [Test]
    public static void Fork_No_UsesSpaceToChooseEnglish()
    {
        foreach (var learned in new bool?[] { null, false, true })
        {
            var memory = new LanguageMemory(null);
            if (learned is { } english) memory.Remember("no", english, explicitChoice: true);
            Detector.Memory = memory;
            try
            {
                foreach (var live in new[] { false, true })
                foreach (var before in new[] { "", "English ", "I have ", "日本語" })
                {
                    var k = new Keyboard(live: live, languages: memory);
                    k.Host.PrecedingText = before;
                    k.Type("no");
                    Assert.Equal("の", k.Showing, $"空白なし: learned={learned}, before={before}");
                    k.Type("\n");
                    Assert.Equal("の", k.Host.Document, "空白なしなら日本語で確定する");

                    k = new Keyboard(live: live, languages: memory);
                    k.Host.PrecedingText = before;
                    k.Type("no ");
                    Assert.Equal("no ", k.Host.Document, "空白を押した時点で英語と空白を確定する");
                    k.Type("no");
                    Assert.Equal("の", k.Showing, "英語として学習した直後も空白を待つ");
                    k.Type("nihongo\n");
                    Assert.Equal("no のにほんご", k.Host.Document, "空白なしで日本語を続けられる");
                }

                foreach (var (input, expected) in new[]
                {
                    ("no problem", "no problem"), ("I have no problem", "I have no problem"),
                    ("north", "north"), ("No", "No"), ("NO", "NO"),
                })
                {
                    var k = new Keyboard(languages: memory);
                    k.Type(input + "\n");
                    Assert.Equal(expected, k.Host.Document, "英単語全体と大文字は維持する: " + input);
                }
            }
            finally
            {
                Detector.Memory = null;
            }
        }
    }

    [Test]
    public static void Fork_LearnedEnglishEndingInN_KeepsTheFollowingParticle()
    {
        var memory = new LanguageMemory(null);
        memory.Remember("main", true);
        memory.Remember("no", true, explicitChoice: true);
        memory.Remember("me", true, explicitChoice: true);
        Detector.Memory = memory;
        try
        {
            foreach (var live in new[] { false, true })
            foreach (var convert in new[] { false, true })
            foreach (var (input, expected) in new[]
            {
                ("mainno", "mainの"), ("mainde", "mainで"), ("mainwo", "mainを"),
                ("mainnoyousuwomite", "mainのようすをみて"), ("mainnohenkou", "mainのへんこう"),
            })
            {
                var k = new Keyboard(live: live, languages: memory);
                for (var i = 0; i < input.Length; i++)
                {
                    k.Type(input[i].ToString());
                    if (input.StartsWith("mainno") && i >= "mainno".Length - 1)
                        Assert.True(k.Showing!.StartsWith("mainの"), "日本語を続けても助詞を保つ: " + input);
                }
                if (convert) k.Type(" ");
                Assert.Equal(expected, k.Showing, $"{input}: live={live}, convert={convert}");
                k.Type("\n");
                Assert.Equal(expected, k.Host.Document, "表示どおり確定する: " + input);
            }
            foreach (var input in new[] { "mainme", "no problem", "I have no problem" })
            {
                var k = new Keyboard(languages: memory);
                k.Type(input + "\n");
                Assert.Equal(input, k.Host.Document, "学習した英単語と英文は維持する: " + input);
            }
        }
        finally
        {
            Detector.Memory = null;
        }
    }

    [Test]
    public static void Fork_DoubleN_KeepsJapaneseReadings()
    {
        foreach (var (input, expected) in new[]
        {
            ("konnnichiha", "こんにちは"), ("kannji", "かんじ"),
            ("gomennnasai", "ごめんなさい"), ("onnna", "おんな"), ("annnai", "あんない"),
        })
        {
            var k = new Keyboard();
            k.Type(input);
            Assert.Equal(expected, k.Showing, input);
            k.Type("\n");
            Assert.Equal(expected, k.Host.Document, "表示どおり確定する: " + input);
        }
    }

    private sealed class KansenConverter : IKanjiConverter
    {
        public string? Convert(string hiragana) => ConvertClauses(hiragana) is { } clauses ? string.Concat(clauses.Select(c => c.Text)) : null;
        public IReadOnlyList<ConversionClause>? ConvertClauses(string hiragana, string? context = null) => hiragana switch
        {
            "かんきせん" => [new("かんき", "換気"), new("せん", "扇")],
            "かんき" => [new("かんき", "換気")],
            "かんきせ" => [new("かんきせ", "換気せ")],
            "きせん" => [new("きせん", "汽船")],
            "ふろのかん" => [new("ふろの", "風呂の"), new("かん", "関")],
            "ふろの" => [new("ふろの", "風呂の")],
            "かんをする" => [new("かんを", "勘を"), new("する", "する")],
            "かんをしています" => [new("かんをしています", "勘をしています")],
            "をしています" => [new("をしています", "をしています")],
            "をする" => [new("をする", "をする")],
            "かんじ" => [new("かんじ", "感じ")],
            "かんじはある" => [new("かんじは", "感じは"), new("ある", "ある")],
            "もたつくかんじはある" => [new("もたつく", "もたつく"), new("かんじは", "感じは"), new("ある", "ある")],
            "じ" => [new("じ", "事")],
            "じはある" => [new("じは", "事は"), new("ある", "ある")],
            "かん" => [new("かん", "関")],
            _ => null,
        };
    }

    [Test]
    public static void Fork_Period_UsesOnlyTheCharacterImmediatelyBeforeTheCaret()
    {
        foreach (var (before, expected) in new (string?, string)[]
        {
            (null, "."), ("", "."), ("かな", "。"), ("漢字", "。"), ("カナ", "。"), ("コーヒー", "。"),
            ("ｶﾅ", "。"), ("𠮷", "。"), ("時々", "。"), ("Google", "."), ("123", "."),
            ("日本語 ", "."), ("日本語　", "."), ("日本語\n", "."), ("日本語」", "."),
            ("日本語。", "."), ("日本語、", "."), ("日本語・", "."), ("日本語🙂", "."),
        })
        {
            var k = new Keyboard();
            k.Host.SurroundingTextIsCurrent = true;
            k.Host.PrecedingText = before;
            k.Type(".");
            Assert.Equal(expected, k.Showing, $"直前: {before}");
            k.Type("\n");
            Assert.Equal(expected, k.Host.Document, $"確定後も維持: {before}");
        }
    }

    [Test]
    public static void Fork_Period_PreservesTheChosenWidthWhileTypingAndDeleting()
    {
        foreach (var live in new[] { false, true })
        {
            var japanese = live ? "日本語" : "にほんご";
            foreach (var (input, expected) in new[]
            {
                ("...", "..."), ("nihongo.", japanese + "。"), ("nihongo...", japanese + "。.."),
                ("nihongo,Google.", "にほんご、Google."), ("Google.", "Google."),
                ("3.14", "3.14"), ("README.md", "README.md"), ("https://example.com", "https://example.com"),
            })
            {
                var k = new Keyboard(live: live);
                k.Type(input);
                Assert.Equal(expected, k.Showing, $"live={live}: {input}");
                k.Type("\n");
                Assert.Equal(expected, k.Host.Document, $"確定後: {input}");
            }
            var deleting = new Keyboard(live: live);
            deleting.Host.PrecedingText = "漢字";
            deleting.Type(".https://example.com\b\b\b");
            Assert.Equal("。https://example.", deleting.Showing, "URL内を削除しても先頭の句点は維持");
            deleting.Type("\n");
            Assert.Equal("。https://example.", deleting.Host.Document);

            var empty = new Keyboard(live: live);
            empty.Type("nihongo\b\b\b\b.");
            Assert.Equal(".", empty.Showing, "すべて削除した後の単独ピリオド");
        }
    }

    [Test]
    public static void Fork_Period_UsesTheSelectedConversionAndCurrentCaretPosition()
    {
        foreach (var continueAfterConversion in new[] { false, true })
        {
            var k = new Keyboard { ContinueAfterConversion = continueAfterConversion };
            k.Type("nihongo ");
            Assert.Equal("日本語", k.Showing);
            k.Type(".");
            if (continueAfterConversion) k.Type(" ");
            k.Type("\n");
            Assert.Equal("日本語。", k.Host.Document, $"選択中の候補の後ろ: 続けて変換={continueAfterConversion}");
        }
        var moved = new Keyboard();
        moved.Host.SurroundingTextIsCurrent = true;
        moved.Type("nihongo\n");
        moved.Host.PrecedingText = "English";
        moved.Type(".");
        Assert.Equal(".", moved.Showing, "確定直後でも移動先の文字を使う");

        var committed = new Keyboard();
        committed.Host.SurroundingTextIsCurrent = true;
        committed.Type("nihongo\n.\n");
        Assert.Equal("にほんご。", committed.Host.Document, "確定済み日本語の直後");
    }

    [Test]
    public static void Fork_UserDictionary_ParticlePrefixDoesNotSplitAWholeWord()
    {
        foreach (var live in new[] { false, true })
        {
            var dictionary = new UserDictionary(null, builtIn: false);
            dictionary.Add("けい", "径");
            var history = new ConversionHistory(null);
            history.Remember("けい", "計");
            var converter = new SplitConverter(new()
            {
                ["けいさん"] = [new("けいさん", "けいさん")],
                ["けいには"] = [new("けいには", "けいには")],
            });
            var k = new Keyboard(live: live, history: history, converter: converter, userDictionary: dictionary,
                moreCandidates: reading => reading == "けいさん" ? ["計算"] : []);
            k.Type("keisann ");
            Assert.Equal("けいさん", k.Showing, "「さん」は助詞「さ」で始まるだけなので、登録語で分割しない");
            var index = k.Host.View!.Candidates.ToList().IndexOf("計算");
            Assert.True(index >= 0, "読み全体の候補を選べる");
            k.Controller.SelectCandidate(index);
            k.Type("\n");
            Assert.Equal("計算", k.Host.Document);
            Assert.Equal("計算", history.Get("けいさん"), "読み全体として学習する");

            foreach (var (input, expected) in new[] { ("kei", "計"), ("keiniha", "計には") })
            {
                var registered = new Keyboard(live: live, history: history, converter: converter, userDictionary: dictionary);
                registered.Type(input + " \n");
                Assert.Equal(expected, registered.Host.Document, "単独の登録語と助詞の連続は維持する");
            }
        }
    }

    [Test]
    public static void Fork_WholeReadingHistory_PrevailsOverShortUserWordsAndEngineSplits()
    {
        foreach (var live in new[] { false, true })
        foreach (var split in new[] { false, true })
        foreach (var input in new[] { "keisann", "keisan" })
        {
            var dictionary = new UserDictionary(null, builtIn: false);
            dictionary.Add("けい", "径");
            var history = new ConversionHistory(null);
            history.Remember("けい", "計");
            history.Remember("けいさん", "計算");
            var converter = new SplitConverter(new()
            {
                ["けいさん"] = split ? [new("けい", "系"), new("さん", "さん")] : [new("けいさん", "けいさん")],
            });
            var k = new Keyboard(live: live, history: history, converter: converter, userDictionary: dictionary);
            k.Type(input + " \n");
            Assert.Equal("計算", k.Host.Document, "分割に関係なく読み全体の学習を優先する");

            var enter = new Keyboard(live: true, history: history, converter: converter, userDictionary: dictionary);
            enter.Type("keisann");
            Assert.Equal("計算", enter.Showing, "ライブ変換にも読み全体の学習を使う");
            enter.Type("\n");
            Assert.Equal("計算", enter.Host.Document);
        }
    }

    [Test]
    public static void Fork_UserDictionary_WordCuttingAnEngineClause_IsNotSplitOut()
    {
        // かん → 燗 を登録すると、かんきせん (換気|扇 と区切る) の頭の かん で区切って 燗|汽船 になっていた。
        // #374 の 始まりが文節の途中の語 と同じで、終わりが文節の途中の語でも区切らない。
        var dictionary = new UserDictionary(null, builtIn: false);
        dictionary.Add("かん", "燗");
        var k = new Keyboard(converter: new KansenConverter(), userDictionary: dictionary);
        k.Type("kankisen ");
        Assert.Equal("換気扇", string.Concat(k.Host.View!.Clauses!));

        k = new Keyboard(live: true, converter: new KansenConverter(), userDictionary: dictionary);
        k.Type("kankisen");
        Assert.True(!k.Showing!.Contains("燗"), "ライブ変換でも割り込まない: " + k.Showing);

        // 終わりが文節の境目に合う語は、今までどおり語で区切る (ふろの|かん の かん → 燗)
        k = new Keyboard(converter: new KansenConverter(), userDictionary: dictionary);
        k.Type("furonokan ");
        Assert.Equal("風呂の燗", string.Concat(k.Host.View!.Clauses!));

        // 読みだけで終わる語も、今までどおり登録した単語 (かん → 燗)
        k = new Keyboard(converter: new KansenConverter(), userDictionary: dictionary);
        k.Type("kan ");
        Assert.Equal("燗", k.Host.View!.Clauses!.Single());

        // Mac は助詞を前の語と同じ文節にする。登録語 + 助詞は引き続き使える。
        k = new Keyboard(converter: new KansenConverter(), userDictionary: dictionary);
        k.Type("kanwosuru ");
        Assert.Equal("燗をする", string.Concat(k.Host.View!.Clauses!));
    }

    [Test]
    public static void Fork_UserDictionary_DoesNotSplitOkuriganaFromAWord()
    {
        var dictionary = new UserDictionary(null, builtIn: false);
        dictionary.Add("かん", "燗");
        foreach (var live in new[] { false, true })
        foreach (var (input, expected) in new[] {
            ("kanji", "感じ"),
            ("kanjihaaru", "感じはある"),
            ("motatsukukanjihaaru", "もたつく感じはある"),
            ("kanwoshiteimasu", "燗をしています"),
        })
        {
            var k = new Keyboard(live: live, converter: new KansenConverter(), userDictionary: dictionary);
            k.Type(input + " ");
            Assert.Equal(expected, k.Showing, input);
            k.Press(VirtualKeys.Return);
            Assert.Equal(expected, k.Host.Document, "表示どおり確定する: " + input);
        }

        var liveInput = new Keyboard(live: true, converter: new KansenConverter(), userDictionary: dictionary);
        liveInput.Type("motatsukukanjihaaru");
        Assert.Equal("もたつく感じはある", liveInput.Showing, "ライブ変換でも送り仮名を分断しない");
    }
}
