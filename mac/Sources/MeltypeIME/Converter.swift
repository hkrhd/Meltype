// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// azooKey の変換エンジン (AzooKeyKanaKanjiConverter) で、ひらがなを漢字かな混じりに変換する。
/// azooKey の API が変わったときは、このファイルだけ直せばよいようにしてある。
final class MeltypeConverter {
    static let shared = MeltypeConverter()
    // 通常入力は2回まで。CLIでの比較計測に限り明示した上限を使える。
    static let inferenceLimit: Int = {
        let arguments = CommandLine.arguments
        guard arguments.contains("--benchmark-conversion") || arguments.contains("--convert"),
              let index = arguments.firstIndex(of: "--inference-limit") else { return 2 }
        guard index + 1 < arguments.count, let limit = Int(arguments[index + 1]), (1...5).contains(limit) else {
            fatalError("--inference-limit must be between 1 and 5")
        }
        return limit
    }()

    // 同梱の辞書 (KanaKanjiConverterModuleWithDefaultDictionary) を使う変換エンジン。
    // azooKey の withDefaultDictionary() は辞書を Bundle.module で探すが、Bundle.module は Meltype.app の直下か
    // ビルドしたマシンのフォルダーしか見ない。辞書のバンドルは Contents/Resources に入れているので、見つからずに落ちていた (#26)。
    // (Meltype.app の直下には置けない: 署名が通らない)。なので、辞書の場所をこちらで渡す。
    private let converter = KanaKanjiConverter(dicdataStore: DicdataStore(dictionaryURL: MeltypeConverter.resource("Dictionary")))
    private let options: ConvertRequestOptions
    private let candidateOptions: ConvertRequestOptions
    private let dictionaryCandidateOptions: ConvertRequestOptions
    private var expectedZenzaiStatus: String?
    private enum RequestPurpose: Hashable {
        case composition, candidateList
    }
    private struct CacheKey: Hashable {
        let reading: String
        let purpose: RequestPurpose
    }
    private var resultCache: [CacheKey: [Candidate]] = [:]
    private var cacheOrder: [CacheKey] = []
    private(set) var candidateRequestCount = 0

    /// 同梱の辞書のバンドル (Contents/Resources に入れている) の中のフォルダー。
    private static func resource(_ name: String) -> URL {
        let bundleName = "AzooKeyKanaKanjiConverter_KanaKanjiConverterModuleWithDefaultDictionary.bundle"
        let url = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(bundleName, isDirectory: true)
        return (Bundle(url: url)?.resourceURL ?? url).appendingPathComponent(name, isDirectory: true)
    }

    /// 絵文字の辞書 (azooKey の withDefaultEmojiDictionary() と同じ選び方。こちらも Bundle.module を使わない)。
    private static func emojiDictionary() -> URL {
        let directory = resource("EmojiDictionary")
        if #available(macOS 15.3, *) { return directory.appendingPathComponent("emoji_all_E16.0.txt", isDirectory: false) }
        if #available(macOS 14.4, *) { return directory.appendingPathComponent("emoji_all_E15.1.txt", isDirectory: false) }
        return directory.appendingPathComponent("emoji_all_E15.0.txt", isDirectory: false)
    }

    private init() {
        let model = (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("zenz-v3.2-small-Q5_K_M.gguf")
            // エンジンに渡すパスが相対にならないよう、Bundle の基底URLも解決する。
            .absoluteURL
        // 通常入力の従来変換は計測時の比較用だけ。モデル不在を黙って従来変換に戻さない。
        let classicBenchmark = CommandLine.arguments.contains("--benchmark-conversion")
            && CommandLine.arguments.contains("--classic")
        precondition(classicBenchmark || FileManager.default.isReadableFile(atPath: model.path),
            "Zenzai small model is missing: rebuild Meltype.app")
        expectedZenzaiStatus = classicBenchmark ? nil : "load \(model.absoluteString)"
        // azooKey の学習データ・ユーザー辞書の置き場所 (Meltype では学習しない設定にしているので、ほぼ使わない)。
        let directory = (NativeCore.shared.dataDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Meltype", isDirectory: true))
            .appendingPathComponent("azooKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        options = ConvertRequestOptions(
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: directory,
            sharedContainerURL: directory,
            textReplacer: TextReplacer(emojiDataProvider: { MeltypeConverter.emojiDictionary() }),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: classicBenchmark ? .off : .on(
                weight: model,
                inferenceLimit: Self.inferenceLimit,
                requestRichCandidates: false,
                personalizationMode: nil,
                versionDependentMode: .v3(.init())
            ),
            experimentalZenzaiPredictiveInput: false,
            metadata: .init(versionString: "Meltype \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
        )
        var candidateOptions = options
        if !classicBenchmark {
            candidateOptions.zenzaiMode = .on(
                weight: model,
                inferenceLimit: Self.inferenceLimit,
                requestRichCandidates: true,
                personalizationMode: nil,
                versionDependentMode: .v3(.init())
            )
        }
        self.candidateOptions = candidateOptions
        // モデルの確率しきい値で省かれる同音異義語も、同じエンジンの辞書探索から併記する。
        var dictionaryCandidateOptions = options
        dictionaryCandidateOptions.zenzaiMode = .off
        dictionaryCandidateOptions.N_best = 30
        dictionaryCandidateOptions.typoCorrectionMode = .disabled
        self.dictionaryCandidateOptions = dictionaryCandidateOptions
    }

    /// モデルの読み込み・Metal初期化を最初のキー入力から起動時へ移す。
    func warmUp() {
        autoreleasepool { _ = results(for: "あ") }
        converter.stopComposition()
    }

    /// ひらがな全体に対する変換結果 (入力をすべて使ったものだけ、よい順)。
    private func results(for hiragana: String, purpose: RequestPurpose = .composition) -> [Candidate] {
        let key = CacheKey(reading: hiragana, purpose: purpose)
        if let cached = resultCache[key] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(hiragana, inputStyle: .direct)
        let requests = purpose == .candidateList ? [candidateOptions, dictionaryCandidateOptions] : [options]
        let count = hiragana.count
        var candidates: [Candidate] = []
        for request in requests {
            let results: ConversionResult
            if purpose == .candidateList {
                // 各探索を独立した状態で行い、通常変換の表記による制約を持ち込まない。
                // 辞書・モデルは共有され、通常入力の逐次変換状態も保つ。
                let session = converter.createSession()
                defer { converter.removeSession(session) }
                results = try! converter.withSession(session) {
                    converter.requestCandidates(composing, options: request)
                }
            } else {
                results = converter.requestCandidates(composing, options: request)
            }
            candidateRequestCount += 1
            if let expectedZenzaiStatus {
                precondition(converter.zenzStatus == expectedZenzaiStatus,
                    "Zenzai model could not be loaded: \(converter.zenzStatus)")
            }
            // 入力 (ひらがな) をすべて使った候補だけ (.direct なので入力数 = ひらがな数)。
            candidates.append(contentsOf: results.mainResults.filter {
                $0.composingCount == .inputCount(count) || $0.composingCount == .surfaceCount(count)
            })
        }
        // Keep the engine's previous lattice for incremental conversion; bound retained results.
        if count <= 256 {
            if cacheOrder.count >= 64 {
                resultCache.removeValue(forKey: cacheOrder.removeFirst())
            }
            resultCache[key] = candidates
            cacheOrder.append(key)
        }
        return candidates
    }

    /// 文節に区切った変換結果 (読みをつなげると元のひらがなになる)。変換できなければ空。
    func clauses(for hiragana: String, context: String?) -> [(reading: String, text: String)] {
        guard let best = results(for: hiragana).first else { return [] }
        var clauses: [(reading: String, text: String)] = []
        for element in best.data {
            let reading = element.ruby.applyingTransform(.hiraganaToKatakana, reverse: true) ?? element.ruby
            // 助詞・助動詞 (ひらがなだけの短い語) は前の文節にくっつける (今日|は → 今日は)。
            if let last = clauses.last, element.word == reading, element.word.count <= 3 {
                clauses[clauses.count - 1] = (last.reading + reading, last.text + element.word)
            } else {
                clauses.append((reading, element.word))
            }
        }
        // 読みがずれた (長音などの扱いの違い) ときは、文節に分けずに全体で返す。
        if clauses.map(\.reading).joined() != hiragana {
            return [(hiragana, best.text)]
        }
        return clauses
    }

    /// 読みに対する候補の一覧 (重複なし、30 個まで)。
    func candidates(for reading: String) -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        for candidate in results(for: reading, purpose: .candidateList) where seen.insert(candidate.text).inserted {
            list.append(candidate.text)
            if list.count >= 30 { break }
        }
        return list
    }
}
