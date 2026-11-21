// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Config;
using Meltype.Dictionary;
using Meltype.Input;

namespace Meltype.Tests;

internal static partial class CompositionTests
{
    [Test]
    public static void Fork_UserDictionary_HyoueAfterJapanese()
    {
        // べえ → 兵衛 を登録しても、ますだとく|bee と英単語に分けていた
        var dictionary = new UserDictionary(null, builtIn: false);
        dictionary.Add("べえ", "兵衛");
        Detector.UserDictionary = dictionary;
        try
        {
            var converter = new SplitConverter(new()
            {
                ["ますだとくべえ"] = [new("ますだ", "増田"), new("とくべえ", "徳兵衛")],
                ["はちだいめぎへえ"] = [new("はちだいめ", "八代目"), new("ぎへえ", "儀兵衛")],
            });
            foreach (var live in new[] { false, true })
            foreach (var (input, expected) in new[] { ("masudatokubee", "増田徳兵衛"), ("hachidaimegihee", "八代目儀兵衛") })
            {
                var k = new Keyboard(live: live, converter: converter, userDictionary: dictionary);
                k.Type(input + " \n");
                Assert.Equal(expected, k.Host.Document, input);
            }
        }
        finally
        {
            Detector.UserDictionary = null;
        }
    }
}
