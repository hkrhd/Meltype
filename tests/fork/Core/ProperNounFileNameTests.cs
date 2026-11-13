// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;

namespace Meltype.Tests;

internal static partial class SessionFacadeTests
{
    [Test]
    public static void Fork_ProperNounFileName_UsesRegisteredCasingBeforeExtension()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-proper-filename-" + Guid.NewGuid().ToString("N"));
        var dictionaries = Path.Combine(directory, "dictionaries");
        Directory.CreateDirectory(dictionaries);
        File.WriteAllText(Path.Combine(dictionaries, "propernouns.txt"), "AGENTS\n");
        try
        {
            foreach (var live in new[] { false, true })
            {
                new Settings { LiveConversion = live }.Save(Path.Combine(directory, "config.json"));
                using var runtime = new MeltypeRuntime(directory);
                foreach (var ending in new[] { "\n", " \n" })
                {
                    var session = runtime.CreateSession(new CompositionTests.FakeConverter());
                    Assert.Equal("AGENTS.md", Type(session, "agents.md")[^1].View?.Text, "登録した表記でファイル名を表示する");
                    var committed = string.Concat(Type(session, ending).SelectMany(r => r.Commits).Select(e => e.Text));
                    Assert.Equal(ending.StartsWith(' ') ? "AGENTS.md " : "AGENTS.md", committed, "表示したファイル名を確定する");
                }
            }
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
