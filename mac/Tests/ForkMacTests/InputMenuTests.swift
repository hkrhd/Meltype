// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import XCTest
@testable import MeltypeIME

/// 入力メニューの中身。操作は自動更新の適用だけにし、辞書の置き場所と自動反映の説明を出す。
final class InputMenuTests: XCTestCase {
    func testMenuShowsOnlyDictionaryNotesWithoutUpdate() {
        let contents = MeltypeInputController.menuContents(updateBuild: nil)
        XCTAssertEqual(contents.notes.count, 2, "説明は2件だけ")
        XCTAssertTrue(contents.notes[0].contains("自動で反映"), "自動反映の説明: \(contents.notes[0])")
        XCTAssertTrue(contents.notes[1].contains("dictionaries") && contents.notes[1].contains("english.txt"),
            "辞書の置き場所の説明: \(contents.notes[1])")
        XCTAssertNil(contents.updateTitle, "更新が無ければ操作項目は無い")
    }

    func testMenuAddsOnlyUpdateActionWhenReady() {
        let contents = MeltypeInputController.menuContents(updateBuild: 2999)
        XCTAssertEqual(contents.notes.count, 2, "説明は更新があっても2件のまま")
        XCTAssertEqual(contents.updateTitle, MacUpdatePrompt.menuTitle(build: 2999), "操作は自動更新の適用だけ")
    }
}
