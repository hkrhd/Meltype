// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace Meltype.Tests;

/// <summary>このフォークのリリースからの Windows 版の自動更新。</summary>
internal static class ForkUpdaterTests
{
    [Test]
    public static void Fork_Updater_ComparesBuildNumbers()
    {
        Assert.True(Updater.IsNewer("1.6.1-pre.1.hkrhd.2913.gbbb", "1.6.0-hkrhd.2912.gaaa"), "upstream のプレリリースを土台にした次のビルド");
        Assert.True(Updater.IsNewer("1.6.1-hkrhd.2990.gccc", "1.6.1-pre.2.hkrhd.2950.gbbb"), "upstream の正式版を土台にした後のビルド");
        Assert.True(!Updater.IsNewer("1.6.0-hkrhd.2912.gaaa", "1.6.0-hkrhd.2912.gaaa.dirty"), "手元で作った同じビルド");
    }

    [Test]
    public static void Fork_UpdateScript_DownloadsNewestPublishedWindowsBuild()
    {
        var root = Path.Combine(Path.GetTempPath(), "meltype-fork-update-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var prefix = $"http://localhost:{((IPEndPoint)probe.LocalEndpoint).Port}/";
        probe.Stop();
        using var server = new HttpListener();
        server.Prefixes.Add(prefix);
        server.Start();
        try
        {
            var setup = "fixture setup"u8.ToArray();
            var digest = "sha256:" + Convert.ToHexString(SHA256.HashData(setup)).ToLowerInvariant();
            object Release(string tag, bool draft, params string[] assets) => new
            {
                tag_name = tag, draft, prerelease = true,
                assets = assets.Select(name => new { name, browser_download_url = prefix + name, digest }).ToArray(),
            };
            var list = JsonSerializer.SerializeToUtf8Bytes(new[]
            {
                Release("hkrhd-build-3000-3-1", true, "Meltype-1.6.0-hkrhd.3000.gddd-setup.exe"),
                Release("hkrhd-build-2960-2-1", false, "Meltype-1.6.0-hkrhd.2960.gccc-mac.zip"),
                Release("hkrhd-build-2950-1-1", false, "Meltype-1.6.0-hkrhd.2950.gaaa-setup.exe", "Meltype-1.6.0-hkrhd.2950.gaaa-windows-portable.zip"),
                Release("hkrhd-release-43816268893-1", false, "Meltype-1.6.0-hkrhd.174.g97c-setup.exe"),
            });
            var serving = Task.Run(() =>
            {
                while (server.IsListening)
                {
                    HttpListenerContext context;
                    try { context = server.GetContext(); } catch (HttpListenerException) { return; }
                    var body = context.Request.Url!.AbsolutePath == "/releases" ? list : setup;
                    context.Response.OutputStream.Write(body);
                    context.Response.Close();
                }
            });

            string Run(string current, string directory)
            {
                var script = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "packaging", "update.ps1");
                var start = new ProcessStartInfo(Updater.PowerShell) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
                foreach (var arg in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.GetFullPath(script), "-Repository", "hkrhd/Meltype",
                             "-CurrentVersion", current, "-Directory", directory, "-Prerelease", "-ReleasesUri", prefix + "releases" })
                    start.ArgumentList.Add(arg);
                // CI は PowerShell 7 からテストを起動する。サインイン時の Meltype と同じく、その場所を Windows PowerShell に渡さない。
                start.Environment.Remove("PSModulePath");
                using var process = Process.Start(start)!;
                return Updater.ReadOutput(process, 120_000)?.Trim() ?? "timeout";
            }

            var updates = Path.Combine(root, "update");
            Assert.Equal("ready 1.6.0-hkrhd.2950.gaaa", Run("1.6.0-hkrhd.2909.gzzz", updates), "公開済みで Windows 版のある最新のビルド");
            var installer = Path.Combine(updates, "Meltype-1.6.0-hkrhd.2950.gaaa-setup.exe");
            Assert.True(File.Exists(installer), "インストーラーをダウンロードする");
            Assert.Equal("1.6.0-hkrhd.2950.gaaa\t" + installer, File.ReadAllText(Path.Combine(updates, "ready.txt")), "ready.txt に版とインストーラーの場所");
            Assert.Equal("none", Run("1.6.0-hkrhd.2950.gaaa", Path.Combine(root, "current")), "同じビルドなら更新しない");
            server.Stop();
            serving.Wait(5_000);
        }
        finally
        {
            if (server.IsListening) server.Stop();
            Directory.Delete(root, recursive: true);
        }
    }
}
