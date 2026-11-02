// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import AppKit
import Darwin

// 本番の監視コードとビルド済み dylib を同一プロセスで動かす。個人辞書は使わない。
@main
struct DictionaryReloadCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("MELTYPE_DATA_DIR", root.path, 1)
        guard CommandLine.arguments.count == 2,
              let library = dlopen(CommandLine.arguments[1], RTLD_NOW) else { fatalError("dylib を開けません") }
        // NativeAOT はプロセス存続中アンロードしない。
        func symbol<T>(_ name: String, _: T.Type) -> T {
            guard let address = dlsym(library, name) else { fatalError("C ABI がありません: \(name)") }
            return unsafeBitCast(address, to: T.self)
        }
        typealias Clauses = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        typealias Candidates = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        typealias IsWord = @convention(c) (UnsafePointer<CChar>?) -> Int32
        typealias Init = @convention(c) (Clauses, Candidates, IsWord) -> Int32
        typealias Create = @convention(c) () -> UnsafeMutableRawPointer?
        typealias Destroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
        typealias Reload = @convention(c) () -> Int32
        typealias Key = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        typealias Free = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        let initialize = symbol("meltype_init", Init.self)
        let create = symbol("meltype_create", Create.self)
        let destroy = symbol("meltype_destroy", Destroy.self)
        let reload = symbol("meltype_reload_dictionaries", Reload.self)
        let key = symbol("meltype_handle_key", Key.self)
        let free = symbol("meltype_free", Free.self)
        precondition(initialize({ _, _ in nil }, { _ in nil }, { _ in 0 }) == 1)
        try "{\"LiveConversion\":false}".write(to: root.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        func check(_ value: Bool, _ message: String = "入力結果が一致しません") {
            precondition(value, message)
        }
        func type(_ text: String, in session: UnsafeMutableRawPointer) throws -> (String?, String) {
            var shown: String?
            var committed = ""
            for character in text {
                let code = Int32(String(character).utf16.first!)
                let vk: Int32 = character == "\n" ? 0x0D : Int32(character.uppercased().utf16.first!)
                guard let result = key(session, vk, code, 0, nil, nil) else { fatalError("キー入力に失敗しました") }
                defer { free(result) }
                let json = try JSONSerialization.jsonObject(with: Data(String(cString: result).utf8)) as! [String: Any]
                shown = (json["view"] as? [String: Any])?["text"] as? String
                committed += (json["commits"] as! [[String: Any]]).map { $0["text"] as! String }.joined()
            }
            return (shown, committed)
        }
        guard let composing = create(), let originalIdle = create() else { fatalError("入力欄を作れません") }
        var idle = originalIdle
        defer { destroy(composing); destroy(idle) }
        let original = try type("papitto", in: idle).0
        precondition(original != "papitto")
        _ = try type("\n", in: idle)
        let pending = try type("mos", in: composing).0
        var updates = 0
        let watcher = MacDictionaryWatcher(directory: root.path) {
            precondition(reload() == 1)
            guard let replacement = create() else { fatalError("更新後の入力欄を作れません") }
            destroy(idle)
            idle = replacement
            updates += 1
        }
        func waitForUpdate(_ count: Int) {
            let deadline = Date().addingTimeInterval(3)
            while updates < count && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(updates == count, "辞書更新を検知できませんでした")
        }
        watcher.start()
        waitForUpdate(1)
        let dictionaries = root.appendingPathComponent("dictionaries")
        let english = dictionaries.appendingPathComponent("english.txt")
        try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
        let saved = Date()
        try "mosh\npapitto\n".write(to: english, atomically: true, encoding: .utf8)
        waitForUpdate(2)
        let latency = Date().timeIntervalSince(saved)
        check(try type("mosh", in: idle).0 == "mosh")
        check(try type("\n", in: idle).1 == "mosh")
        check(try type("papitto", in: idle).0 == "papitto")
        _ = try type("\n", in: idle)
        check(try type("\n", in: composing).1 == pending, "入力中の文字が変化しました")
        try FileManager.default.removeItem(at: english)
        waitForUpdate(3)
        check(try type("papitto", in: idle).0 == original)
        print(String(format: "PASS 辞書保存→OS通知→C ABI→入力・確定、削除反映、入力途中の保持 (反映 %.3f秒)", latency))
        withExtendedLifetime(watcher) {}
    }
}
