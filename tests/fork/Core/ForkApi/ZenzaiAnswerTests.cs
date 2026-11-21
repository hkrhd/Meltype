// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using Meltype.Composition;
using Meltype.Engine;

namespace Meltype.Tests;

/// <summary>個人フォークで追加した Zenzai の答えの採否。</summary>
internal static class ZenzaiAnswerTests
{
    [Test]
    public static void Fork_ZenzaiEnglishFromKanaReading_PrefersMozcJapanese()
    {
        using var server = new ZenzaiConverterTests.FakeServer { Answer = p => p.Contains("タンイヲトル") ? "TANIwoTORU" : "TANI" };
        using var zenzai = new ZenzaiConverter(server.Endpoint);
        using var mozc = MozcConverterTests.Fake();
        var hybrid = new HybridConverter(mozc, () => zenzai);
        // 偽の Mozc は たんい → 単位、たんいをとる → 単位を|取る
        Assert.Equal("単位", hybrid.ConvertText("たんい", "前の文") ?? "", "読みから作った英字より Mozc の日本語");
        Assert.Equal("単位", hybrid.ConvertText("たんい", null) ?? "", "1 語の変換も同じ");
        Assert.Equal("単位を取る", hybrid.ConvertText("たんいをとる", null) ?? "", "英字と仮名を混ぜた答えも使わない");
    }
}
