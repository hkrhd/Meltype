// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hrmcngs

import AppKit
import Darwin
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

/// macOS のテキスト置換を正として userdict.txt を生成する。start はメインスレッドで呼ぶ。
final class MacUserDictionarySync {
    private let database: URL
    private let destination: URL
    private let stateDirectory: URL
    private let reload: () -> Void
    // DB のロック待ちやファイル I/O で IME のキー処理を止めない。
    private let syncQueue = DispatchQueue(label: "Meltype.dictionary-sync", qos: .utility)
    private struct Watch {
        let identity: String
        let source: DispatchSourceFileSystemObject
    }
    private var watches: [String: Watch] = [:]
    private var scheduledSync: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var lastError: String?
    private var pendingFile: URL { stateDirectory.appendingPathComponent("pending-reload") }

    init(directory: String, database: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/KeyboardServices/TextReplacements.db"),
        reload: @escaping () -> Void = {
            NotificationCenter.default.post(
                name: Notification.Name("MeltypeUserDictionaryChanged"), object: nil)
        }) {
        self.database = database
        self.reload = reload
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        destination = folder.appendingPathComponent("userdict.txt")
        stateDirectory = folder.appendingPathComponent("mac-dictionary-sync", isDirectory: true)
    }

    deinit {
        scheduledSync?.cancel()
        for watch in watches.values { watch.source.cancel() }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func sync() throws {
        let (data, count, skipped) = try dictionaryData(from: database)
        let manager = FileManager.default
        let existing = manager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination) : nil
        if existing != data {
            try manager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            // 終了・クラッシュを挟んでも反映待ちを失わないよう、辞書より先に記録する。
            try Data().write(to: pendingFile, options: .atomic)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            log("同期: \(count)語、除外\(skipped)件。画面スリープ時に再読込")
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
        syncQueue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    @discardableResult
    private func reconcileWatches() throws -> Bool {
        let directory = database.deletingLastPathComponent().path
        // KeyboardServices 自体の作成・入れ替えも検知し、常駐サービスの再起動に頼らず監視を戻す。
        let parentDirectory = database.deletingLastPathComponent().deletingLastPathComponent().path
        let directories: Set<String> = [parentDirectory, directory]
        let database = self.database.path
        var changed = false
        for path in [parentDirectory, directory, database, database + "-wal"] {
            var metadata = stat()
            let exists = lstat(path, &metadata) == 0
            if !exists {
                guard errno == ENOENT, path != parentDirectory else {
                    throw DictionarySyncError(message: "辞書の監視対象を参照できません (errno \(errno))")
                }
                if let removed = watches.removeValue(forKey: path) {
                    removed.source.cancel()
                    changed = true
                }
                continue
            }
            let identity = "\(metadata.st_dev):\(metadata.st_ino)"
            if watches[path]?.identity == identity { continue }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                // 作成・削除途中の競合は、次の親ディレクトリ通知で再評価する。
                if errno == ENOENT, path != parentDirectory { continue }
                throw DictionarySyncError(message: "辞書の監視を開始できません (errno \(errno))")
            }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0 else {
                close(descriptor)
                throw DictionarySyncError(message: "辞書の監視対象を確認できません")
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete, .revoke], queue: .main)
            source.setCancelHandler { close(descriptor) }
            source.setEventHandler { [weak self] in
                guard let self else { return }
                do {
                    let changed = try self.reconcileWatches()
                    if !directories.contains(path) || changed { self.scheduleSync() }
                } catch { log("監視エラー: \(error.localizedDescription)") }
            }
            watches.removeValue(forKey: path)?.source.cancel()
            watches[path] = Watch(identity: "\(opened.st_dev):\(opened.st_ino)", source: source)
            source.resume()
            changed = true
        }
        return changed
    }

    private func reloadOnScreenSleep() {
        syncAndReport()
        guard FileManager.default.fileExists(atPath: pendingFile.path) else { return }
        reload()
        do {
            try FileManager.default.removeItem(at: pendingFile)
            log("画面スリープ: 辞書再読込の通知を送信しました")
        } catch { log("反映待ち状態を削除できません: \(error.localizedDescription)") }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.scheduledSync?.cancel()
                self.syncQueue.async { [weak self] in self?.reloadOnScreenSleep() }
            })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                do { try self.reconcileWatches() }
                catch { log("監視エラー: \(error.localizedDescription)") }
                self.scheduleSync()
            })
        do { try reconcileWatches() }
        catch { log("監視エラー: \(error.localizedDescription)") }
        // 監視開始後に初回同期し、起動途中の変更も取りこぼさない。
        syncQueue.async { [weak self] in self?.syncAndReport() }
        log("OSの変更通知を待機中 (定期ポーリングなし)")
    }
}
