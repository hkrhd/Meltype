// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Ime;
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
            {
                new Settings { LiveConversion = live, AutoDetection = true }
                    .Save(Path.Combine(directory, "config.json"));
                using var runtime = new MeltypeRuntime(directory);
                foreach (var word in new[] { "sudo", "repo", "no", "e", "c" })
                foreach (var ending in new[] { "\n", " \n" })
                {
                    var session = new TestSession(runtime.SessionParts(new CompositionTests.FakeConverter(), null, _ => null), () => runtime.Settings.Current);
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
                using var runtime = new MeltypeRuntime(directory);
                var session = new TestSession(runtime.SessionParts(new CompositionTests.FakeConverter(), null, _ => null), () => runtime.Settings.Current);
                Assert.Equal(expected, Type(session, input)[^1].View?.Text, "日本語の途中を分断しない: " + input);
            }

            new Settings { LiveConversion = false, AutoDetection = false }.Save(Path.Combine(directory, "config.json"));
            using var manualRuntime = new MeltypeRuntime(directory);
            var manual = new TestSession(manualRuntime.SessionParts(new CompositionTests.FakeConverter(), null, _ => null), () => manualRuntime.Settings.Current);
            Assert.Equal("すど", Type(manual, "sudo")[^1].View?.Text, "手動判定を維持する");

            new Settings { LiveConversion = false }.Save(Path.Combine(directory, "config.json"));
            using var rememberedRuntime = new MeltypeRuntime(directory);
            var remembered = new TestSession(rememberedRuntime.SessionParts(new CompositionTests.FakeConverter(), null, _ => null), () => rememberedRuntime.Settings.Current);
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
