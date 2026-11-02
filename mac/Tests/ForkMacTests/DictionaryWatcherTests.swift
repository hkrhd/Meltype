// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import AppKit
import XCTest
@testable import MeltypeIME

final class DictionaryWatcherTests: XCTestCase {
    private var root: URL!
    private var folder: URL { root.appendingPathComponent("data") }
    private var dictionaries: URL { folder.appendingPathComponent("dictionaries") }
    private var english: URL { dictionaries.appendingPathComponent("english.txt") }
    private var watcher: MacDictionaryWatcher?
    private var reloads = 0
    private var expectedReload: XCTestExpectation?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expectedReload = expectation(description: "監視開始時の反映")
        watcher = MacDictionaryWatcher(directory: folder.path) { [weak self] in
            guard let self else { return }
            XCTAssertTrue(Thread.isMainThread)
            self.reloads += 1
            self.expectedReload?.fulfill()
        }
        watcher?.start()
        wait(for: [expectedReload!], timeout: 3)
        expectedReload = nil
    }

    override func tearDownWithError() throws {
        watcher = nil
        try FileManager.default.removeItem(at: root)
    }

    private func update(_ description: String, _ action: () throws -> Void) throws {
        expectedReload = expectation(description: description)
        try action()
        wait(for: [expectedReload!], timeout: 3)
        expectedReload = nil
    }

    func testRunningIMEFollowsCreationDirectWritesAtomicReplacementAndDeletion() throws {
        try update("起動後に作った辞書") {
            try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
            try "mosh\n".write(to: english, atomically: false, encoding: .utf8)
        }
        try update("直接書込") {
            try "mosh\nrepo\n".write(to: english, atomically: false, encoding: .utf8)
        }
        try update("一時ファイルからの置換保存") {
            try "mosh\nsudo\n".write(to: english, atomically: true, encoding: .utf8)
        }
        try update("辞書の削除") { try FileManager.default.removeItem(at: english) }
        try update("削除後の再作成") {
            try "mosh\n".write(to: english, atomically: true, encoding: .utf8)
        }
        try update("辞書ディレクトリの削除") { try FileManager.default.removeItem(at: dictionaries) }
        try update("辞書ディレクトリの再作成") {
            try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
            try "repo\n".write(to: english, atomically: true, encoding: .utf8)
        }
    }

    func testUserDictionaryAndImportedPlistChangesAreFollowed() throws {
        try update("ユーザー辞書を追加") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "よみ\t単語\n".write(to: folder.appendingPathComponent("userdict.txt"), atomically: true, encoding: .utf8)
        }
        let imported = dictionaries.appendingPathComponent("UserDictionary.plist")
        try update("plist を追加") {
            try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: [["shortcut": "よみ", "phrase": "取込語"]],
                format: .xml, options: 0)
            try data.write(to: imported, options: .atomic)
        }
        try update("plist を削除") { try FileManager.default.removeItem(at: imported) }
        try update("データディレクトリを置換") {
            try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("previous"))
            try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
            try "mosh\n".write(to: english, atomically: true, encoding: .utf8)
        }
    }

    func testIdenticalSavesLearningTemporaryFilesAndIdleDoNotReload() throws {
        try update("辞書を追加") {
            try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
            try "mosh\n".write(to: english, atomically: true, encoding: .utf8)
        }
        let count = reloads
        try "mosh\n".write(to: english, atomically: false, encoding: .utf8)
        try "mosh\n".write(to: english, atomically: true, encoding: .utf8)
        for name in ["languages.json", "conversions.json", "phrases.txt", "config.json"] {
            try "{}".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "temporary".write(to: dictionaries.appendingPathComponent(".english.txt.swp"), atomically: false, encoding: .utf8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(reloads, count, "同じ保存・学習・一時ファイルでは辞書を再構築しない")
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(reloads, count, "待機中に周期的な再読込をしない")
    }
}
