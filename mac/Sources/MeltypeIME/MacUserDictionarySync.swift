// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hrmcngs

import AppKit
import SQLite3

// TextReplacements.db は非公開形式。未知の形式を空辞書として扱わない。
private struct DictionarySyncError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func log(_ message: String) {
    NSLog("Meltype 辞書同期: %@", message)
}

private func dictionaryData(from url: URL) throws -> (Data, Int, Int) {
    var database: OpaquePointer?
    let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
    defer { if let database { sqlite3_close(database) } }
    guard openResult == SQLITE_OK, let database else {
        throw DictionarySyncError(message: "システム辞書DBを読み取り専用で開けません (SQLite \(openResult))")
    }
    sqlite3_busy_timeout(database, 2000)
    // WAL を含めた単一 SELECT のスナップショット。DB/WAL 本体には書き込まない。
    var statement: OpaquePointer?
    let sql = "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0"
    let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    guard prepareResult == SQLITE_OK else {
        throw DictionarySyncError(message: "システム辞書DBの形式を読めません (SQLite \(prepareResult))")
    }
    var lines = Set<String>()
    var skipped = 0
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_column_type(statement, 1) == SQLITE_TEXT,
              let shortcut = sqlite3_column_text(statement, 0),
              let phrase = sqlite3_column_text(statement, 1) else {
            throw DictionarySyncError(message: "システム辞書DBの読み・単語が文字列ではありません")
        }
        let raw = String(decoding: UnsafeBufferPointer(start: shortcut, count: Int(sqlite3_column_bytes(statement, 0))), as: UTF8.self)
        let reading = (raw.applyingTransform(.hiraganaToKatakana, reverse: true) ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let word = String(decoding: UnsafeBufferPointer(start: phrase, count: Int(sqlite3_column_bytes(statement, 1))), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Meltype の MacUserDictionary.entries と同じ条件。
        if reading.utf16.count >= 2, !word.isEmpty,
           !reading.contains(where: { "\t\n\r\0".contains($0) }),
           !word.contains(where: { "\t\n\r\0".contains($0) }) {
            lines.insert(reading + "\t" + word)
        } else {
            skipped += 1
        }
        result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
        throw DictionarySyncError(message: "システム辞書DBを読み切れません (SQLite \(result))")
    }
    let header = "# macOSユーザ辞書から自動生成。編集はシステム設定で行う。\n"
    let content = header + lines.sorted().map { $0 + "\n" }.joined()
    return (Data(content.utf8), lines.count, skipped)
}

/// macOS のテキスト置換を正として userdict.txt を生成する。start はメインスレッドで呼ぶ。反映は MacDictionaryWatcher が担う。
final class MacUserDictionarySync {
    private let database: URL
    private let destination: URL
    // DB のロック待ちやファイル I/O で IME のキー処理を止めない。
    private let syncQueue = DispatchQueue(label: "Meltype.dictionary-sync", qos: .utility)
    private var monitor: DictionaryFileMonitor?
    private var scheduledSync: DispatchWorkItem?
    private var observer: NSObjectProtocol?
    private var lastError: String?

    init(directory: String, database: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/KeyboardServices/TextReplacements.db")) {
        self.database = database
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        destination = folder.appendingPathComponent("userdict.txt")
    }

    deinit {
        scheduledSync?.cancel()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func sync() throws {
        let (data, count, skipped) = try dictionaryData(from: database)
        let manager = FileManager.default
        let existing = manager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination) : nil
        if existing != data {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            log("同期: \(count)語、除外\(skipped)件。変更通知で再読込")
        }
    }

    private func syncAndReport() {
        do {
            try sync()
            if lastError != nil { log("辞書同期が復旧しました") }
            lastError = nil
        } catch {
            let message = error.localizedDescription
            if message != lastError { log("エラー: \(message)") }
            lastError = message
        }
    }

    private func scheduleSync() {
        scheduledSync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncAndReport() }
        scheduledSync = work
        syncQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.syncQueue.async { [weak self] in
                    guard let self else { return }
                    do { try self.monitor?.reconcile() }
                    catch { log("監視エラー: \(error.localizedDescription)") }
                    self.scheduleSync()
                }
            }
        syncQueue.async { [weak self] in
            guard let self else { return }
            let directory = self.database.deletingLastPathComponent()
            let database = self.database.path
            self.monitor = DictionaryFileMonitor(queue: self.syncQueue,
                directories: [directory.deletingLastPathComponent().path, directory.path],
                files: { [database, database + "-wal"] },
                changed: { [weak self] in self?.scheduleSync() })
            do { try self.monitor?.reconcile() }
            catch { log("監視エラー: \(error.localizedDescription)") }
            self.syncAndReport()
            // 旧版のスリープ待ち記録は不要。辞書ファイル自体を起動時に読み込む。
            let obsolete = self.destination.deletingLastPathComponent()
                .appendingPathComponent("mac-dictionary-sync/pending-reload")
            if FileManager.default.fileExists(atPath: obsolete.path) {
                do { try FileManager.default.removeItem(at: obsolete) }
                catch { log("旧反映待ち状態を削除できません: \(error.localizedDescription)") }
            }
        }
        log("OSの変更通知を待機中 (定期ポーリングなし)")
    }
}
