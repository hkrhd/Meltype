// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

/// 固定文だけを使い、実変換器またはライブ変換のキーイベント全体を計測する。
enum ConversionBenchmark {
    private struct Example {
        let reading: String
        let roman: String
    }
    private static let examples: [Example] = [
        .init(reading: "でむこうかした", roman: "demukoukashita"),
        .init(reading: "むこうかした", roman: "mukoukashita"),
        .init(reading: "せっていでむこうかした", roman: "setteidemukoukashita"),
        .init(reading: "きょうはにほんごのへんかんせいどをかくにんします", roman: "kyouhanihongonohenkanseidowokakuninshimasu"),
        .init(reading: "あしたのかいぎのしりょうをよういしてください", roman: "ashitanokaiginoshiryouwoyouishitekudasai"),
        .init(reading: "あたらしいへんかんえんじんのそくどとめもりしようりょうをしらべます", roman: "atarashiihenkanenjin'nosokudotomemorishiyouryouwoshirabemasu"),
        .init(reading: "このきのうはせっていがめんでむこうかしたあとにあぷりをさいきどうするとてきようされます", roman: "konokinouhasetteigamendemukoukashitaatoniapuriwosaikidousurutotekiyousaremasu"),
        .init(reading: "らいぶへんかんをつかいながらながいぶんしょうをにゅうりょくしてもひっかからずにそうさできるかをかくにんしています", roman: "raibuhenkanwotsukainagaranagaibunshouwonyuuryokushitemohikkakarazunisousadekirukawokakuninshiteimasu"),
        .init(reading: "きょうはぐーぐるでけんさくしてぎっとはぶにほうこくします", roman: "kyouhagoogledekensakushitegithubnihoukokushimasu"),
    ]

    private static func memory() -> [String: Double] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return [:] }
        return ["residentMiB": Double(info.resident_size) / 1_048_576,
                "footprintMiB": Double(info.phys_footprint) / 1_048_576]
    }

    private static func elapsed(_ start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [:] }
        func percentile(_ p: Double) -> Double {
            sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * p)) - 1)]
        }
        return ["count": Double(sorted.count), "p50Ms": percentile(0.50), "p95Ms": percentile(0.95),
                "p99Ms": percentile(0.99), "maxMs": sorted.last!,
                "meanMs": sorted.reduce(0, +) / Double(sorted.count),
                "over16ms": Double(sorted.filter { $0 > 16.7 }.count),
                "over50ms": Double(sorted.filter { $0 > 50 }.count),
                "over100ms": Double(sorted.filter { $0 > 100 }.count)]
    }

    static func run() {
        let keyEvents = CommandLine.arguments.contains("--key-events")
        let classic = CommandLine.arguments.contains("--classic")
        var report: [String: Any] = ["engine": classic ? "classic" : "zenz-v3.1-small-Q5_K_M-metal",
            "pipeline": keyEvents ? "native-key-events" : "kana-converter",
            "inferenceLimit": classic ? 0 : MeltypeConverter.inferenceLimit, "memoryBefore": memory(), "rounds": 5,
            "cache": "production caches enabled; corpus exceeds 64 readings; no artificial sleeps"]
        let warmUpStart = DispatchTime.now().uptimeNanoseconds
        MeltypeConverter.shared.warmUp()
        report["startupWarmUpMs"] = elapsed(warmUpStart)
        report["memoryAfterWarmUp"] = memory()
        var coldMs = 0.0
        var samples: [[String: Any]] = []
        var durations: [Double] = []
        var firstPass: [Double] = []
        var outputs: [[String: String]] = []
        for round in 0..<5 {
            for example in examples {
                let session = keyEvents ? NativeCore.shared.createSession() : nil
                var prefix = ""
                var output = ""
                var committed = ""
                let input = keyEvents ? example.roman : example.reading
                for (index, character) in input.enumerated() {
                    prefix.append(character)
                    let requestsBefore = MeltypeConverter.shared.candidateRequestCount
                    let start = DispatchTime.now().uptimeNanoseconds
                    autoreleasepool {
                        if keyEvents {
                            let result = NativeCore.shared.handleKey(session,
                                vk: Int32(character.uppercased().utf16.first ?? 0),
                                character: Int32(String(character).utf16.first ?? 0),
                                modifiers: 0, before: nil, after: nil)
                            for edit in result?.commits ?? [] {
                                let previous = committed as NSString
                                committed = previous.substring(to: max(0, previous.length - edit.deleteBefore)) + edit.text
                            }
                            output = committed + (result?.view?.text ?? "")
                        } else {
                            output = MeltypeConverter.shared.clauses(for: prefix, context: nil).map(\.text).joined()
                        }
                    }
                    let ms = elapsed(start)
                    if round == 0 && example.reading == examples[0].reading && index == 0 {
                        coldMs = ms
                        report["memoryAfterFirstConversion"] = memory()
                    } else {
                        durations.append(ms)
                        if round == 0 { firstPass.append(ms) }
                    }
                    samples.append(["round": round, "inputLength": prefix.count, "input": prefix, "ms": ms,
                        "output": output,
                        "candidateRequests": MeltypeConverter.shared.candidateRequestCount - requestsBefore])
                }
                let preview = output
                if keyEvents {
                    autoreleasepool {
                        let result = NativeCore.shared.commit(session)
                        for edit in result?.commits ?? [] {
                            let previous = committed as NSString
                            committed = previous.substring(to: max(0, previous.length - edit.deleteBefore)) + edit.text
                        }
                        output = committed
                        NativeCore.shared.destroySession(session)
                    }
                }
                if round == 0 { outputs.append(["input": input, "preview": preview, "output": output]) }
            }
            report["memoryAfterRound\(round + 1)"] = memory()
        }
        report["firstEventMs"] = coldMs
        report["afterFirstEvent"] = summary(durations)
        report["firstPassAfterFirstEvent"] = summary(firstPass)
        report["outputs"] = outputs
        report["samples"] = samples
        report["memoryAfter"] = memory()
        report["candidateRequests"] = MeltypeConverter.shared.candidateRequestCount
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        print()
    }
}
