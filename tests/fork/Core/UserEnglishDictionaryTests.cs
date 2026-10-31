// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

internal static partial class SessionFacadeTests
{
    [Test]
    public static void Fork_UserEnglishDictionary_StandaloneWordsStayEnglish()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-user-english-" + Guid.NewGuid().ToString("N"));
        var dictionaries = Path.Combine(directory, "dictionaries");
        Directory.CreateDirectory(dictionaries);
        File.WriteAllText(Path.Combine(dictionaries, "english.txt"), "# 登録語を優先する\nSUDO\nrepo\nno\ne\nc\n");
        try
        {
            foreach (var live in new[] { false, true })
            foreach (var level in new[] { DetectionLevel.Conservative, DetectionLevel.Balanced, DetectionLevel.Aggressive })
            {
                new Settings { LiveConversion = live, DetectionLevel = level }
                    .Save(Path.Combine(directory, "config.json"));
                foreach (var word in new[] { "sudo", "repo", "no", "e", "c" })
                foreach (var ending in new[] { "\n", " \n" })
                {
                    var session = MeltypeSession.CreateDefault(directory, new CompositionTests.FakeConverter(), null, null);
                    var shown = word == "no" ? "の" : word;
                    Assert.Equal(shown, Type(session, word)[^1].View?.Text, "登録語の表示: " + word);
                    var results = Type(session, ending);
                    Assert.Equal(ending.StartsWith(' ') ? word + " " : shown,
                        string.Concat(results.SelectMany(r => r.Commits).Select(e => e.Text)), "登録語の確定: " + word);
                }
            }

            new Settings { LiveConversion = false }.Save(Path.Combine(directory, "config.json"));
            foreach (var (input, expected) in new[] { ("sudou", "すどう"), ("nihongo", "にほんご"), ("nekono", "ねこの") })
            {
                var session = MeltypeSession.CreateDefault(directory, new CompositionTests.FakeConverter(), null, null);
                Assert.Equal(expected, Type(session, input)[^1].View?.Text, "日本語の途中を分断しない: " + input);
            }

            new Settings { LiveConversion = false, DetectionLevel = DetectionLevel.Manual }.Save(Path.Combine(directory, "config.json"));
            var manual = MeltypeSession.CreateDefault(directory, new CompositionTests.FakeConverter(), null, null);
            Assert.Equal("すど", Type(manual, "sudo")[^1].View?.Text, "手動判定を維持する");

            new Settings { LiveConversion = false }.Save(Path.Combine(directory, "config.json"));
            var remembered = MeltypeSession.CreateDefault(directory, new CompositionTests.FakeConverter(), null, null);
            Type(remembered, "sudo");
            remembered.HandleKey(VirtualKeys.F6, null, false, false, false, false);
            Type(remembered, "\n");
            Assert.Equal("すど", Type(remembered, "sudo")[^1].View?.Text, "明示的に選んだ日本語の学習を優先する");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
