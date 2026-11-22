// SPDX-License-Identifier: GPL-3.0-or-later
// mac/Sources/MeltypeIME/main.swift の runChecks を、C ABI (src/Meltype.Core.CApi/Exports.cs) と同じ組み立てで流す。
//   MELTYPE_APP_DIR=<mozc/・zenzai/ のあるフォルダー> MELTYPE_DATA_DIR=<データ> LocalChecks --check-inputs <file>
//   … --check-candidates <file> / --check-predictions
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Meltype.Dictionary;
using Meltype.Ime;

var appDirectory = Environment.GetEnvironmentVariable("MELTYPE_APP_DIR") ?? throw new InvalidOperationException("MELTYPE_APP_DIR がありません");
if (Environment.GetEnvironmentVariable("MELTYPE_DATA_DIR") is not { Length: > 0 }) throw new InvalidOperationException("MELTYPE_DATA_DIR がありません");
Console.OutputEncoding = new System.Text.UTF8Encoding(false);
using var runtime = MeltypeRuntime.OpenDefault();
var converter = runtime.CreateConverter(appDirectory);
if (!converter.MozcInstalled) throw new InvalidOperationException($"{appDirectory}/mozc に Mozc の変換ヘルパーがありません");
converter.WarmUp();
var environment = new LocalEnvironment(runtime.Snippets);
var failures = 0;

void Check(string name, bool condition)
{
    Console.WriteLine($"{(condition ? "PASS" : "FAIL")} {name}");
    if (!condition) failures++;
}

Document NewDocument() =>
    new(new ImeHost(environment, runtime.SessionParts(converter, converter.Candidates, converter.Reading), () => runtime.Settings.Current));

var mode = args.ElementAtOrDefault(0);
var path = args.ElementAtOrDefault(1);
return mode switch
{
    "--check-inputs" when path is not null => Inputs(path),
    "--check-candidates" when path is not null => Candidates(path),
    "--check-predictions" => Predictions(),
    _ => Usage(),
};

static int Usage()
{
    Console.Error.WriteLine("Usage: LocalChecks --check-inputs <file> | --check-candidates <file> | --check-predictions");
    return 2;
}

IEnumerable<(string Input, string Expected)> Lines(string file) =>
    File.ReadAllText(file).Split('\n').Where(line => line.Length > 0 && !line.StartsWith('#'))
        .Select(line => line.Split('\t', 2)).Where(parts => parts.Length == 2).Select(parts => (parts[0], parts[1]));

int Inputs(string file)
{
    var count = 0;
    foreach (var (input, expected) in Lines(file))
    {
        var document = NewDocument();
        document.Type(input + "\n");
        Check(input, document.Text == expected);
        if (document.Text != expected) Console.WriteLine($"expected: {expected}; actual: {document.Text}");
        count++;
    }
    Console.WriteLine($"{count - failures}/{count} input checks passed");
    return count > 0 && failures == 0 ? 0 : 1;
}

int Candidates(string file)
{
    var document = NewDocument();
    var count = 0;
    foreach (var (input, expected) in Lines(file))
    {
        var watch = Stopwatch.StartNew();
        document.Type(input);
        var view = document.Type(" ")?["result"]?["view"];
        var lists = new List<List<string>>();
        if (view is not null && view["converting"]?.GetValue<bool>() == true)
        {
            // 変換を始めると最後の文節を選ぶので、先頭から候補を集める
            var clauses = view["clauses"]?.AsArray().Count ?? 0;
            for (var i = 1; i < clauses; i++) view = document.Key(0x25)?["result"]?["view"];
            for (var clause = 0; clause < clauses; clause++)
            {
                if (clause > 0) view = document.Key(0x27)?["result"]?["view"];
                lists.Add(Items(view));
            }
        }
        List<int>? Choices(int clause, string remaining)
        {
            if (clause == lists.Count) return remaining.Length == 0 ? [] : null;
            for (var index = 0; index < lists[clause].Count; index++)
            {
                var candidate = lists[clause][index];
                if (remaining.StartsWith(candidate, StringComparison.Ordinal) && Choices(clause + 1, remaining[candidate.Length..]) is { } rest) return [index, .. rest];
            }
            return null;
        }
        var selection = Choices(0, expected);
        if (selection is { Count: > 0 })
        {
            for (var i = 1; i < selection.Count; i++) document.Key(0x25);
            for (var clause = 0; clause < selection.Count; clause++)
            {
                if (clause > 0) document.Key(0x27);
                view = document.Send("CandidateClicked", new() { ["index"] = selection[clause] })?["result"]?["view"];
            }
        }
        var committed = document.Send("CommitRequested");
        Check($"{input} → {expected}", selection is not null && view?["text"]?.GetValue<string>() == expected && committed?["result"]?["view"] is null && document.Text == expected);
        if (selection is null || document.Text != expected)
            Console.WriteLine($"expected: {expected}; actual: {document.Text}; candidates: {JsonSerializer.Serialize(lists, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping })}");
        Console.WriteLine($"candidate latency: {watch.Elapsed.TotalSeconds:F3}s");
        document.Text = "";
        document.Send("CaretMoved", new() { ["caret"] = new JsonObject { ["moved"] = true, ["passedKey"] = 0 } });
        count++;
    }
    Console.WriteLine($"{count - failures}/{count} candidate checks passed");
    return count > 0 && failures == 0 ? 0 : 1;
}

int Predictions()
{
    var document = NewDocument();
    Check("英語補完: 1文字では非表示", Items(document.Type("d")?["result"]?["view"]).Count == 0);
    Check("英語補完: 2文字では非表示", Items(document.Type("e")?["result"]?["view"]).Count == 0);
    var three = document.Type("c")?["result"]?["view"];
    var candidates = Items(three);
    Check("英語補完: 3文字から表示", candidates.Count > 0 && candidates.All(c => c.StartsWith("dec", StringComparison.Ordinal) && c.Length > 3));
    Check("英語補完: 表示時点では未選択", three?["candidates"]?["selected"]?.GetValue<int>() == -1);
    var tab = document.Type("\t");
    Check("英語補完: Tabで先頭を選択", tab?["result"]?["consumed"]?.GetValue<bool>() == true && Text(tab?["result"]?["view"]) == candidates.FirstOrDefault());
    var back = document.Key(0x09, shift: true)?["result"]?["view"];
    Check("英語補完: Shift+Tabで未選択", back?["candidates"]?["selected"]?.GetValue<int>() == -1 && Text(back) == Text(three));
    document.Type("\t");
    Check("英語補完: Escで元に戻る", Text(document.Key(0x1B)?["result"]?["view"]) == Text(three));
    document.Type("\t\n");
    Check("英語補完: Enterで確定", document.Text == candidates.FirstOrDefault());
    document.Text = "";
    var again = document.Type("dec")?["result"]?["view"];
    var clicked = document.Send("CandidateClicked", new() { ["index"] = 0 });
    Check("英語補完: クリックで確定", clicked?["result"]?["view"] is null && document.Text == Items(again).FirstOrDefault());
    document.Text = "";
    var single = document.Type("decision")?["result"]?["view"];
    Check("英語補完: 1件の候補も取得", Items(single).SequenceEqual(["decisions"]));
    document.Type("\t\n");
    Check("英語補完: 1件の候補も確定", document.Text == "decisions");
    return failures == 0 ? 0 : 1;
}

static List<string> Items(JsonNode? view) =>
    view?["candidates"]?["items"]?.AsArray().Select(item => item!.GetValue<string>()).ToList() ?? [];

static string? Text(JsonNode? view) => view?["text"]?.GetValue<string>();

/// <summary>入力欄の代わり (確定した文字とアプリに通した文字)。キーごとにキャレットの前として本体に渡す。</summary>
internal sealed class Document(ImeHost host)
{
    public string Text { get; set; } = "";

    public JsonNode? Send(string type, JsonObject? fields = null)
    {
        var e = new JsonObject { ["version"] = 1, ["type"] = type, ["instance"] = "self-test", ["field"] = new JsonObject { ["before"] = Text } };
        foreach (var (key, value) in fields ?? []) e[key] = value?.DeepClone();
        var output = JsonNode.Parse(host.Handle(e.ToJsonString()));
        foreach (var edit in output?["result"]?["commits"]?.AsArray() ?? [])
        {
            // 確定し直しは本体が照合済み: 前の remove を消してから入れる
            var remove = edit?["removeBefore"]?.GetValue<string>()?.Length ?? 0;
            Text = Text[..(Text.Length - Math.Min(remove, Text.Length))] + edit?["text"]?.GetValue<string>();
        }
        return output;
    }

    public JsonNode? Key(int vk, bool shift = false) => Send("KeyPressed", new() { ["key"] = new JsonObject { ["vk"] = vk, ["shift"] = shift } });

    public JsonNode? Type(string text)
    {
        JsonNode? last = null;
        foreach (var rune in text.EnumerateRunes())
        {
            var key = new JsonObject { ["shift"] = Rune.IsUpper(rune) };
            switch (rune.Value)
            {
                case ' ': key["vk"] = 0x20; key["ch"] = 0x20; break;
                case '\n': key["vk"] = 0x0D; break;
                case '\t': key["vk"] = 0x09; break;
                default: key["ch"] = rune.Value; break;
            }
            last = Send("KeyPressed", new() { ["key"] = key });
            if (last?["result"]?["consumed"]?.GetValue<bool>() != true && rune.Value is not '\n' and not '\t') Text += rune.ToString();
        }
        return last;
    }
}

/// <summary>Mac・Linux の環境 (src/Meltype.Core.CApi/Exports.cs の NativeEnvironment と同じ)。</summary>
internal sealed class LocalEnvironment(SnippetStore snippets) : IImeEnvironment
{
    public Meltype.Config.InputMode? InputMethod => null;

    public SnippetStore Snippets => snippets;

    public string? ClipboardText => null;

    public string? OtherTipVersion => null;
}
