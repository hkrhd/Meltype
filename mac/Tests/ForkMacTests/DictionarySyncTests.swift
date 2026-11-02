// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hrmcngs

import AppKit
import SQLite3
import XCTest
@testable import MeltypeIME

final class DictionarySyncTests: XCTestCase {
    private var root: URL!
    private var database: URL { root.appendingPathComponent("TextReplacements.db") }
    private var directory: URL { root.appendingPathComponent("output") }
    private var destination: URL { directory.appendingPathComponent("userdict.txt") }
    private var connection: OpaquePointer?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try openDatabase()
    }

    override func tearDownWithError() throws {
        sqlite3_close(connection)
        connection = nil
        try FileManager.default.removeItem(at: root)
    }

    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(connection, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw NSError(domain: "FixtureSQLite", code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(connection))])
        }
    }

    private func openDatabase(_ source: URL? = nil) throws {
        XCTAssertEqual(sqlite3_open((source ?? database).path, &connection), SQLITE_OK)
        try execute("PRAGMA journal_mode=WAL")
        try execute("CREATE TABLE ZTEXTREPLACEMENTENTRY (ZSHORTCUT TEXT, ZPHRASE TEXT, ZWASDELETED INTEGER)")
    }

    private func replace(_ values: String) throws {
        try execute("DELETE FROM ZTEXTREPLACEMENTENTRY")
        if !values.isEmpty { try execute("INSERT INTO ZTEXTREPLACEMENTENTRY VALUES " + values) }
    }

    private func synchronizer() -> MacUserDictionarySync {
        MacUserDictionarySync(directory: directory.path, database: database)
    }

    private func words() throws -> Set<String> {
        let content = try String(contentsOf: destination, encoding: .utf8)
        return Set(content.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init))
    }

    private func waitForWords(_ expected: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if (try? words()) == expected { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(try words(), expected, file: file, line: line)
    }

    func testSystemDictionaryReplacesChangesAndDeletesWords() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "どくじ\tMeltype独自\n".write(to: destination, atomically: true, encoding: .utf8)
        try replace("(' カイシャ ', ' 株式会社テスト ', 0), ('かいしゃ', '株式会社テスト', 0), "
            + "('とうろく', '削除済み', 1), ('あ', '短い読み', 0), ('から', '', 0), "
            + "('ふくすう', '複数' || char(10) || '行', 0), ('たぶ', 'タブ' || char(9), 0), "
            + "('ぬる', '不正' || char(0) || '文字', 0)")
        let sync = synchronizer()
        try sync.sync()
        // 前後の空白・タブは取り込みメニューと同様に除去する。
        XCTAssertEqual(try words(), ["かいしゃ\t株式会社テスト", "たぶ\tタブ"])
        try replace("('かいしゃ', '変更後', 0)")
        try sync.sync()
        XCTAssertEqual(try words(), ["かいしゃ\t変更後"])
        try replace("")
        try sync.sync()
        XCTAssertEqual(try words(), [])
    }

    func testIdenticalDictionaryIsNotRewritten() throws {
        try replace("('よみ', '単語', 0)")
        let sync = synchronizer()
        try sync.sync()
        let timestamp = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: destination.path)
        try sync.sync()
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, timestamp)
    }

    func testUnreadableDatabasePreservesDictionaryAndDoesNotCreateSource() throws {
        try replace("('よみ', '保持する単語', 0)")
        let sync = synchronizer()
        try sync.sync()
        let original = try Data(contentsOf: destination)
        try replace("(NULL, '不正な行', 0)")
        XCTAssertThrowsError(try sync.sync())
        XCTAssertEqual(try Data(contentsOf: destination), original)
        try execute("DROP TABLE ZTEXTREPLACEMENTENTRY")
        XCTAssertThrowsError(try sync.sync())
        XCTAssertEqual(try Data(contentsOf: destination), original)
        sqlite3_close(connection)
        connection = nil
        try FileManager.default.removeItem(at: database)
        XCTAssertThrowsError(try sync.sync())
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testRunningIMEFollowsWALChangesAndEmptyDictionary() throws {
        try replace("('さいしょ', '初回', 0)")
        let sync = synchronizer()
        sync.start()
        waitForWords(["さいしょ\t初回"])
        try replace("('ついか', '追加', 0), ('へんこう', '変更', 0)")
        waitForWords(["ついか\t追加", "へんこう\t変更"])
        try replace("")
        waitForWords([])
        withExtendedLifetime(sync) {}
    }

    func testDatabaseReplacementAndNewWALAreFollowed() throws {
        try replace("('さいしょ', '初回', 0)")
        let sync = synchronizer()
        sync.start()
        waitForWords(["さいしょ\t初回"])
        sqlite3_close(connection)
        connection = nil
        let previous = root.appendingPathComponent("previous.db")
        try FileManager.default.moveItem(at: database, to: previous)
        try openDatabase()
        try replace("('いれかえ', '新しいDB', 0)")
        waitForWords(["いれかえ\t新しいDB"])
        try replace("('つぎ', '新しいWALの更新', 0)")
        waitForWords(["つぎ\t新しいWALの更新"])
        withExtendedLifetime(sync) {}
    }

    func testDatabaseDirectoryCreatedAfterIMEStartupIsDetected() throws {
        sqlite3_close(connection)
        connection = nil
        let deferred = root.appendingPathComponent("KeyboardServices/TextReplacements.db")
        let sync = MacUserDictionarySync(directory: directory.path, database: deferred)
        sync.start()
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        try FileManager.default.createDirectory(at: deferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        try openDatabase(deferred)
        try replace("('あとから', '起動後の登録', 0)")
        waitForWords(["あとから\t起動後の登録"])
        withExtendedLifetime(sync) {}
    }

    func testSystemChangesReloadWithoutScreenSleep() throws {
        let sync = synchronizer()
        try sync.sync()
        var reloads = 0
        var expectedReload: XCTestExpectation? = expectation(description: "起動時の辞書反映")
        let watcher = MacDictionaryWatcher(directory: directory.path) {
            XCTAssertTrue(Thread.isMainThread)
            reloads += 1
            expectedReload?.fulfill()
        }
        watcher.start()
        wait(for: [expectedReload!], timeout: 3)
        sync.start()
        expectedReload = expectation(description: "テキスト置換をスリープなしで反映")
        try replace("('ついか', '追加した単語', 0)")
        wait(for: [expectedReload!], timeout: 3)
        XCTAssertEqual(try words(), ["ついか\t追加した単語"])
        expectedReload = expectation(description: "空辞書も即時反映")
        try replace("")
        wait(for: [expectedReload!], timeout: 3)
        XCTAssertEqual(try words(), [])
        expectedReload = nil
        let count = reloads
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(reloads, count, "変更がなければ復帰時にも再読込しない")
        withExtendedLifetime((sync, watcher)) {}
    }

    func testExistingDictionaryIsLoadedAfterRestartWithoutPendingMarker() throws {
        try replace("('よみ', '再起動前の変更', 0)")
        try synchronizer().sync()
        let reloaded = expectation(description: "既存辞書を起動時に反映")
        let watcher = MacDictionaryWatcher(directory: directory.path) { reloaded.fulfill() }
        watcher.start()
        wait(for: [reloaded], timeout: 3)
        XCTAssertEqual(try words(), ["よみ\t再起動前の変更"])
        withExtendedLifetime(watcher) {}
    }
}
