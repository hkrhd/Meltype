// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

internal static partial class SessionFacadeTests
{
    [Test]
    public static void Fork_DictionaryReload_UpdatesRunningProcessAndPreservesCompositionAndLearning()
    {
        var directory = Path.Combine(Path.GetTempPath(), "meltype-dictionary-reload-" + Guid.NewGuid().ToString("N"));
        var dictionaries = Path.Combine(directory, "dictionaries");
        Directory.CreateDirectory(dictionaries);
        try
        {
            new Settings { LiveConversion = false }.Save(Path.Combine(directory, "config.json"));
            using var runtime = new MeltypeRuntime(directory);
            MeltypeSession Create() => runtime.CreateSession(new CompositionTests.FakeConverter());
            var old = Create();
            var unregistered = Type(old, "papitto")[^1].View?.Text;
            Assert.True(unregistered is not null and not "papitto", "未登録の語を比較の基準にする");
            Type(old, "\n");
            var learned = Create();
            Type(learned, "repo");
            learned.HandleKey(VirtualKeys.F6, null, false, false, false, false);
            Type(learned, "\n");
            var before = Type(old, "mos")[^1].View?.Text;
            File.WriteAllText(Path.Combine(dictionaries, "english.txt"), "mosh\nrepo\npapitto\n");
            File.WriteAllText(Path.Combine(directory, "userdict.txt"), "よみ\t新しい登録語\n");
            runtime.ReloadDictionaries();
            Assert.True(old.IsComposing, "辞書更新で未確定文字を確定しない");
            var committed = string.Concat(Type(old, "\n").SelectMany(r => r.Commits).Select(e => e.Text));
            Assert.Equal(before, committed, "入力途中の表示を保って確定する");
            foreach (var session in new[] { Create(), Create() })
            {
                Assert.Equal("mosh", Type(session, "mosh")[^1].View?.Text, "既存プロセス内で追加語を英字表示する");
                Assert.Equal("mosh", string.Concat(Type(session, "\n").SelectMany(r => r.Commits).Select(e => e.Text)));
                Assert.Equal("papitto", Type(session, "papitto")[^1].View?.Text);
                Type(session, "\n");
                Assert.Equal("れぽ", Type(session, "repo")[^1].View?.Text, "明示的に選んだ日本語の学習を保持する");
                Type(session, "\n");
                Type(session, "yomi");
                Assert.Equal("新しい登録語", Type(session, " ")[^1].View?.Text, "ユーザー辞書も更新する");
            }
            File.Delete(Path.Combine(dictionaries, "english.txt"));
            runtime.ReloadDictionaries();
            var removed = Create();
            Assert.Equal(unregistered, Type(removed, "papitto")[^1].View?.Text, "削除した登録語を辞書から除く");
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
