// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

/// <summary>個人フォークで追加した入力動作の回帰テスト。</summary>
internal static partial class SessionFacadeTests
{
    [Test]
    public static void Fork_ShortEnglishWord_KeepsSupportedJapaneseTail()
    {
        foreach (var live in new[] { false, true })
        foreach (var scored in new[] { false, true })
        foreach (var (input, expected) in new[]
        {
            ("macnanode", "macなので"), ("macdakara", "macだから"),
            ("macnanodetsukau", "macなのでつかう"), ("macde", "macで"),
            ("googlenanode", "googleなので"), ("pcnanode", "pcなので"),
            ("macabre", "macabre"), ("macaroni", "macaroni"), ("machi", "まち"),
            ("procrasticle", "procrasticle"), ("macpapipupepo", "macpapipupepo"),
            ("macnanode_value", "macnanode_value"),
        })
        {
            var detector = CompositionDetector.CreateDefault();
            detector.SpellChecker = Detection.BuiltInWordChecker.Shared;
            detector.UseScoredSegmentation = () => scored;
            var session = new MeltypeSession(detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live }, () => new Settings());
            Assert.Equal(expected, Type(session, input)[^1].View?.Text,
                $"入力中: {input}, live={live}, scored={scored}");
            Assert.Equal(expected, string.Concat(Type(session, "\n").SelectMany(r => r.Commits).Select(e => e.Text)),
                $"表示どおり確定: {input}, live={live}, scored={scored}");
        }
    }

    [Test]
    public static void Fork_ShortEnglishWord_RespectsEnglishEvidence()
    {
        foreach (var live in new[] { false, true })
        foreach (var scored in new[] { false, true })
        foreach (var (input, before, learned) in new[]
        {
            ("macnanode", "", true), ("macnanode", "I use ", false),
            ("macdakara", "I use ", false), ("machine", "I use ", false),
        })
        {
            var detector = CompositionDetector.CreateDefault();
            detector.SpellChecker = Detection.BuiltInWordChecker.Shared;
            detector.UseScoredSegmentation = () => scored;
            var memory = new LanguageMemory(null);
            if (learned) memory.Remember(input, true, explicitChoice: true);
            detector.Memory = memory;
            var session = new MeltypeSession(detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live, Languages = memory }, () => new Settings());
            Type(session, before);
            Assert.Equal(input, Type(session, input)[^1].View?.Text,
                $"英語の根拠がある語: {input}, before={before}, learned={learned}, live={live}, scored={scored}");
            Assert.Equal(input, string.Concat(Type(session, "\n").SelectMany(r => r.Commits).Select(e => e.Text)),
                "英語のまま確定する");
        }
    }

    [Test]
    public static void Fork_CommittedEnglish_KeepsFollowingParticlesJapaneseDespiteLearning()
    {
        foreach (var learned in new bool?[] { null, false, true })
        foreach (var live in new[] { false, true })
        foreach (var scored in new[] { false, true })
        foreach (var prefix in new[] { "google\n", "google " })
        foreach (var (raw, kana) in new[] { ("ni", "に"), ("de", "で"), ("wo", "を"), ("ga", "が") })
        {
            var detector = CompositionDetector.CreateDefault();
            var memory = new LanguageMemory(null);
            if (learned is { } english) memory.Remember(raw, english, explicitChoice: true);
            detector.Memory = memory;
            detector.UseScoredSegmentation = () => scored;
            var session = new MeltypeSession(detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live, Languages = memory }, () => new Settings());
            Type(session, prefix);
            Assert.Equal(kana, Type(session, raw)[^1].View?.Text,
                $"英字確定後の助詞: {raw}, learned={learned}, live={live}, scored={scored}, prefix={prefix.TrimEnd()}");
            Assert.Equal(kana, Type(session, "\n")[0].Commits.Single().Text, "表示どおり確定する");
        }
    }

    [Test]
    public static void Fork_SymbolMarkers_SpaceCommitsAsciiWithoutConversion()
    {
        foreach (var marker in new[] { "#", "##", "###", "####", "#####", "######", "-", "--", "---", "~", "~~~", "+", "++", "&", "&&" })
        foreach (var live in new[] { false, true })
        foreach (var separate in new[] { false, true })
        foreach (var shift in new[] { false, true })
        {
            var session = new MeltypeSession(CompositionTests.Detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live, SeparateKeyRoles = () => separate,
                    AutomaticEnglishSpacing = () => true, SpaceAroundEnglish = () => true }, () => new Settings());
            Type(session, marker);
            var space = session.HandleKey(VirtualKeys.Space, null, shift, false, false, false);
            Assert.True(space.Consumed, "Space を半角空白の確定に使う");
            Assert.Equal(marker + " ", string.Concat(space.Commits.Select(edit => edit.Text)), marker);
            Assert.True(space.View is null, "候補を開かずに確定する");
            Assert.Equal(live ? "今日は" : "きょうは", Type(session, "kyouha")[^1].View?.Text,
                "続けて日本語を入力できる");
        }

        var japanese = Create();
        Type(japanese, "ko-hi- ");
        Assert.Equal("こーひー", Type(japanese, "\n")[0].Commits.Single().Text,
            "単語中の長音は日本語の変換・確定に使う");
    }

    [Test]
    public static void Fork_LiteralSymbols_StayAsciiThroughConversion()
    {
        foreach (var symbol in "$\"`_/")
        foreach (var live in new[] { false, true })
        foreach (var separate in new[] { false, true })
        foreach (var prefix in new[] { "", "kyouha" })
        {
            var session = new MeltypeSession(CompositionTests.Detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live, SeparateKeyRoles = () => separate,
                    AutomaticEnglishSpacing = () => true, SpaceAroundEnglish = () => true,
                    MoreCandidates = reading => reading == symbol.ToString() ? [((char)(symbol + 0xFEE0)).ToString(), "”"] : [] },
                () => new Settings { SigilWordsDirect = false });
            Type(session, prefix);
            var result = Type(session, symbol.ToString())[0];
            var expectedPrefix = prefix.Length == 0 ? "" : symbol == '_' ? prefix : live ? "今日は" : "きょうは";
            var text = string.Concat(result.Commits.Select(edit => edit.Text)) + result.View?.Text;
            if (!result.Consumed) text += symbol;
            Assert.Equal(expectedPrefix + symbol, text, $"{prefix}{symbol}");
            if (prefix.Length == 0)
            {
                Assert.True(result.View is null && !session.IsComposing, "単独の記号はその場で確定する");
                Assert.Equal(symbol.ToString(), string.Concat(result.Commits.Select(edit => edit.Text)), "Enter を押さずに半角入力する");
            }
            else if (result.Consumed)
            {
                for (var i = 0; i < 4; i++)
                {
                    var converted = session.HandleKey(VirtualKeys.Convert, null, false, false, false, false);
                    Assert.True(converted.View?.Text.EndsWith(symbol) == true, "繰り返し変換しても記号は半角のまま");
                    Assert.True(converted.View!.Candidates.All(c => !c.Contains((char)(symbol + 0xFEE0)) && !c.Contains('”')),
                        "全角や曲がった引用符を候補に出さない");
                }
            }
            var committed = Type(session, "\n")[0];
            Assert.True(!committed.Consumed || committed.Commits.Last().Text.EndsWith(symbol), "確定しても半角のまま");
            Assert.Equal(live ? "今日は" : "きょうは", Type(session, "kyouha")[^1].View?.Text, "続けて日本語を入力できる");
        }
    }

    [Test]
    public static void Fork_LiteralSymbols_WhenIdleCommitImmediately()
    {
        foreach (var symbols in new[] { "$", "\"", "`", "_", "/", "$$", "\"\"", "```", "__", "//" })
        foreach (var live in new[] { false, true })
        foreach (var sigil in new[] { false, true })
        {
            var session = new MeltypeSession(CompositionTests.Detector, new CompositionTests.FakeConverter(),
                new CompositionOptions { LiveConversion = () => live, SpaceAroundEnglish = () => true,
                    AutomaticEnglishSpacing = () => true }, () => new Settings { SigilWordsDirect = sigil });
            var output = "";
            foreach (var symbol in symbols)
            {
                var result = Type(session, symbol.ToString())[0];
                output += string.Concat(result.Commits.Select(edit => edit.Text));
                if (!result.Consumed) output += symbol;
                Assert.True(result.View is null && !session.IsComposing, "キーを押すたびに確定する: " + symbols);
            }
            Assert.Equal(symbols, output, "Enter を押さずに入力欄へ届く");
            var space = Type(session, " ")[0];
            Assert.True(!space.Consumed, "記号の後の通常の空白はアプリへ渡す");
        }
    }

    [Test]
    public static void Fork_Period_DirectAndCodeInputStayAscii()
    {
        var direct = Create();
        direct.Direct = true;
        var result = Type(direct, ".", "日本語")[0];
        Assert.True(!result.Consumed && result.Commits.Count == 0 && result.View is null, "英数直接入力はそのまま通す");

        var code = Create();
        code.CodeInput = true;
        result = Type(code, ".", "const value = 日本語")[0];
        Assert.True(!result.Consumed && result.Commits.Count == 0 && result.View is null, "コードのピリオドはそのまま通す");

        var comment = Create();
        comment.CodeInput = true;
        Assert.Equal("。", Type(comment, ".", "// 日本語")[0].View?.Text, "日本語コメント内は直前の文字で判定");

        var unreadable = Create();
        Type(unreadable, "nihongo\n");
        Assert.Equal(".", Type(unreadable, ".")[0].View?.Text, "現在位置が読めない場合は古い確定記録を使わず半角");
    }
}
