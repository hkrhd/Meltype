// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

internal static partial class SessionFacadeTests
{
    [Test]
    public static void Fork_ProperNounInput_UsesRegisteredCasingWithoutConversion()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-proper-input-" + Guid.NewGuid().ToString("N"));
        var dictionaries = Path.Combine(directory, "dictionaries");
        Directory.CreateDirectory(dictionaries);
        File.WriteAllText(Path.Combine(dictionaries, "propernouns.txt"), "AGENTS\n");
        try
        {
            foreach (var live in new[] { false, true })
            {
                new Settings { LiveConversion = live }.Save(Path.Combine(directory, "config.json"));
                using var runtime = new MeltypeRuntime(directory);
                foreach (var (input, expected) in new[]
                {
                    ("agents", "AGENTS"), ("github", "GitHub"), ("iphone", "iPhone"),
                    ("kyouhagithubde", live ? "今日はGitHubで" : "きょうはGitHubで"),
                    ("github.com", "github.com"), ("https://github.com/agents", "https://github.com/agents"),
                    ("./agents.md", "./agents.md"), ("@github", "@github"), ("github_user", "github_user"),
                    ("hello", "hello"),
                })
                foreach (var ending in new[] { "\n", " \n" })
                {
                    var session = runtime.CreateSession(new CompositionTests.FakeConverter());
                    Assert.Equal(expected, Type(session, input)[^1].View?.Text, "通常入力を登録表記で表示する: " + input);
                    var committed = string.Concat(Type(session, ending).SelectMany(r => r.Commits).Select(e => e.Text));
                    var mixed = input == "kyouhagithubde";
                    var expectedCommit = mixed ? live || ending.StartsWith(' ') ? "今日はGitHubで" : expected
                        : ending.StartsWith(' ') ? expected + " " : expected;
                    Assert.Equal(expectedCommit, committed, "候補選択なしで登録表記を確定する: " + input);
                }

                foreach (var key in new[] { VirtualKeys.F9, VirtualKeys.F10 })
                {
                    var session = runtime.CreateSession(new CompositionTests.FakeConverter());
                    Type(session, "github");
                    session.HandleKey(key, null, false, false, false, false, null);
                    var committed = string.Concat(Type(session, "\n").SelectMany(r => r.Commits).Select(e => e.Text));
                    Assert.Equal(key == VirtualKeys.F9 ? "ｇｉｔｈｕｂ" : "github", committed, "明示した英数表記を維持する");
                }
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
