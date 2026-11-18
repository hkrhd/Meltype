// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import CryptoKit
import XCTest
@testable import MeltypeIME

final class UpdaterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func release(_ tag: String, draft: Bool = false, mac: Bool = true, sha256: String = "00", zip: URL? = nil) -> [String: Any] {
        var assets: [[String: Any]] = [["name": "Meltype-x-windows.zip", "browser_download_url": "https://example.invalid/w.zip", "digest": "sha256:11"]]
        if mac {
            assets.append(["name": "Meltype-x-mac.zip", "browser_download_url": (zip ?? URL(string: "https://example.invalid/\(tag).zip")!).absoluteString,
                           "digest": "sha256:\(sha256)"])
        }
        return ["tag_name": tag, "draft": draft, "prerelease": true, "assets": assets]
    }

    private func json(_ releases: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: releases) }

    func testSelectsNewestPublishedMacRelease() throws {
        let list = try json([
            release("hkrhd-build-3000-1-1", draft: true),
            release("hkrhd-build-2960-3-1", mac: false),
            release("hkrhd-build-2950-2-1"),
            release("hkrhd-release-43816268893-1"),
        ])
        XCTAssertEqual(MacUpdater.newest(in: list, after: 2909)?.build, 2950)
        XCTAssertNil(MacUpdater.newest(in: list, after: 2950))
    }

    func testFailedBuildIsNotRetriedButNewerOneIs() throws {
        let directory = root.appendingPathComponent("update")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "2950\n".write(to: directory.appendingPathComponent("attempted"), atomically: true, encoding: .utf8)
        let releases = root.appendingPathComponent("releases.json")
        try json([release("hkrhd-build-2950-2-1")]).write(to: releases)
        let updater = MacUpdater(releases: releases, directory: directory, currentBuild: 2909, idleSeconds: { 3600 })
        XCTAssertEqual(updater.checkNow(), .upToDate)
        XCTAssertEqual(MacUpdater.newest(in: try json([release("hkrhd-build-2950-2-1"), release("hkrhd-build-2970-4-1")]), after: 2950)?.build, 2970)
    }

    /// install.sh が印を書くだけの、リリースと同じ構成の ZIP。
    private func package(build: Int, marker: URL) throws -> (URL, String) {
        let folder = root.appendingPathComponent("pkg/Meltype-mac")
        let contents = folder.appendingPathComponent("Meltype.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": String(build)], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try "#!/bin/bash\ntouch '\(marker.path)'\n".write(to: folder.appendingPathComponent("install.sh"), atomically: true, encoding: .utf8)
        let zip = root.appendingPathComponent("Meltype-x-mac.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        return (zip, hash)
    }

    private func check(idle: TimeInterval, wrongHash: Bool = false) throws -> (MacUpdater.Outcome, Bool) {
        let marker = root.appendingPathComponent("installed")
        let (zip, hash) = try package(build: 2950, marker: marker)
        let releases = root.appendingPathComponent("releases.json")
        try json([release("hkrhd-build-2950-2-1", sha256: wrongHash ? String(repeating: "0", count: 64) : hash, zip: zip)]).write(to: releases)
        let updater = MacUpdater(releases: releases, directory: root.appendingPathComponent("update"), currentBuild: 2909, idleSeconds: { idle })
        let outcome = updater.checkNow()
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline, case .launched = outcome {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (outcome, FileManager.default.fileExists(atPath: marker.path))
    }

    func testVerifiedPackageInstallsWhenIdle() throws {
        let (outcome, installed) = try check(idle: 3600)
        XCTAssertEqual(outcome, .launched(2950))
        XCTAssertTrue(installed)
    }

    func testHashMismatchDoesNotInstall() throws {
        let (outcome, installed) = try check(idle: 3600, wrongHash: true)
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(installed)
    }

    func testRecentInputDefersInstallation() throws {
        let (outcome, installed) = try check(idle: 5)
        XCTAssertEqual(outcome, .waiting(2950))
        XCTAssertFalse(installed)
    }
}
