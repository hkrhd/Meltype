// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hrmcngs

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

internal static class InputCoverageTests
{
    [Test]
    public static void AutomaticSpaces_PreserveCaseAndIdentifiers()
    {
        foreach (var (input, expected) in new[] {
            ("seeyouagain", "see you again"), ("SeeYouAgain", "See You Again"),
            ("THANKYOU", "THANK YOU"), ("thank you", "thank you"),
            ("https://seeyouagain.com", "https://seeyouagain.com"),
            ("my_seeyouagain_function", "my_seeyouagain_function"),
            ("hello@gmail.com", "hello@gmail.com"), ("github", "github") })
            Assert.Equal(expected, EnglishPhraseSpacing.Format(input));
        Assert.Equal("今日は google で検索", CompositionController.AddSpacesAroundEnglish("今日はgoogleで検索", null, null));
        Assert.Equal("今日は google で検索", CompositionController.AddSpacesAroundEnglish("今日は google で検索", null, null));
    }

    [Test]
    public static void AutomaticSpaces_AreAppliedWhenCommitting()
    {
        foreach (var (input, expected) in new[] { ("seeyouagain", "see you again"), ("kyouhagoogledekensaku", "きょうは Google でけんさく"), ("nice to meet you", "nice to meet you") })
        {
            var detector = CompositionDetector.CreateDefault();
            detector.SpellChecker = Meltype.Detection.BuiltInWordChecker.Shared;
            var session = new MeltypeSession(detector, new CompositionTests.FakeConverter(),
                new CompositionServices { AutomaticEnglishSpacing = () => true }, () => new Settings { SpaceAroundEnglish = true, AutoCorrectAfterCommit = true, LiveConversion = false });
            var output = "";
            foreach (var character in input + "\n")
            {
                var result = session.HandleKey(character == '\n' ? VirtualKeys.Return : char.ToUpperInvariant(character),
                    character == '\n' ? null : character, false, false, false, false);
                foreach (var edit in result.Commits)
                {
                    if (edit.DeleteBefore > 0) output = output[..(output.Length - Math.Min(edit.DeleteBefore, output.Length))];
                    output += edit.Text;
                }
            }
            Assert.Equal(expected, output);
            Assert.True(!output.Contains('\u3000') && !output.Contains('\u00A0'), "半角スペースだけを使う");
        }
    }

    [Test]
    public static void GreetingsAndWords_RemainEnglish()
    {
        foreach (var (phrase, expected) in new[]
        {
            // 固有名詞辞書 (propernouns.txt) にある語は、辞書の登録表記で確定する (google → Google)。
            ("hello", "hello"), ("google", "Google"), ("github", "GitHub"), ("meeting", "meeting"),
            ("keyboard", "keyboard"), ("message", "message"), ("computer", "computer"), ("coffee", "coffee"), ("camera", "camera"),
            ("feature", "feature"), ("remote", "remote"), ("seeyouagain", "seeyouagain"), ("seeyou", "seeyou"),
            ("seeyoulater", "seeyoulater"), ("seeyoutomorrow", "seeyoutomorrow"), ("thankyou", "thankyou"),
            ("thankyouverymuch", "thankyouverymuch"), ("thanks", "thanks"), ("goodbye", "goodbye"),
            ("goodmorning", "goodmorning"), ("goodafternoon", "goodafternoon"), ("goodevening", "goodevening"),
            ("goodnight", "goodnight"), ("nicetomeetyou", "nicetomeetyou"), ("howareyou", "howareyou"),
            ("imfine", "imfine"), ("iloveyou", "iloveyou"), ("takecare", "takecare"), ("welcomehome", "welcomehome"),
            ("see you again", "see you again"), ("thank you very much", "thank you very much"),
            ("good morning", "good morning"), ("nice to meet you", "nice to meet you"), ("how are you", "how are you"),
            ("I want to go to the park", "I want to go to the park"), ("I am going home", "I am going home"),
            ("my name is Taro", "my name is Taro"),
        })
        {
            var detector = CompositionDetector.CreateDefault();
            detector.SpellChecker = Meltype.Detection.BuiltInWordChecker.Shared;
            var session = new MeltypeSession(detector, new CompositionTests.FakeConverter(), new CompositionServices(), () => new Settings());
            var output = "";
            foreach (var character in phrase + "\n")
            {
                var vk = character == ' ' ? VirtualKeys.Space : character == '\n' ? VirtualKeys.Return : char.ToUpperInvariant(character);
                var result = session.HandleKey(vk, character is ' ' or '\n' ? null : character,
                    char.IsAsciiLetterUpper(character), false, false, false);
                foreach (var edit in result.Commits)
                {
                    if (edit.DeleteBefore > 0) output = output[..(output.Length - Math.Min(edit.DeleteBefore, output.Length))];
                    output += edit.Text;
                }
                if (!result.Consumed) output += character;
            }
            Assert.Equal(expected, output, phrase);
        }
    }
}
