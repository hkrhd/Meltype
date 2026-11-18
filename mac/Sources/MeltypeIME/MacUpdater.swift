// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import CoreGraphics
import CryptoKit
import Darwin
import Foundation

/// このフォークの Releases から新しい Mac 版を取得し、入力のない間に同梱の install.sh で入れ替える。
/// 入れ替え・失敗時の復旧は install.sh に任せ、試したビルドは成否にかかわらず再試行しない。
final class MacUpdater {
    struct Release: Equatable {
        let build: Int
        let zip: URL
        let sha256: String
    }

    enum Outcome: Equatable {
        case upToDate
        case waiting(Int)
        case launched(Int)
        case failed(String)
    }

    static let releasesURL = URL(string: "https://api.github.com/repos/hkrhd/Meltype/releases?per_page=30")!

    private let releases: URL
    private let directory: URL
    private let currentBuild: Int
    private let enabled: () -> Bool
    private let idleSeconds: () -> TimeInterval
    private let requiredIdle: TimeInterval
    private let queue = DispatchQueue(label: "Meltype.update", qos: .utility)
    private var checkTimer: DispatchSourceTimer?
    private var idleTimer: DispatchSourceTimer?
    private var prepared: (release: Release, installer: URL)?

    init(releases: URL = MacUpdater.releasesURL, directory: URL, currentBuild: Int,
         enabled: @escaping () -> Bool = { true },
         idleSeconds: @escaping () -> TimeInterval = MacUpdater.systemIdleSeconds,
         requiredIdle: TimeInterval = 600) {
        self.releases = releases
        self.directory = directory
        self.currentBuild = currentBuild
        self.enabled = enabled
        self.idleSeconds = idleSeconds
        self.requiredIdle = requiredIdle
    }

    static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }

    /// 起動直後の負荷を避け、以降は数時間ごとにまとめて確認する。
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: .now() + 600, repeating: 6 * 3600, leeway: .seconds(1800))
        timer.setEventHandler { [weak self] in
            guard let self, self.idleTimer == nil, self.enabled() else { return }
            let outcome = self.checkNow()
            if case .failed(let reason) = outcome { NSLog("Meltype: 更新できませんでした: %@", reason) }
            if case .waiting = outcome { self.watchIdle() }
        }
        timer.resume()
        checkTimer = timer
    }

    private func watchIdle() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: .now() + 300, repeating: 300, leeway: .seconds(60))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.enabled() else { self.stopIdleWatch(); return }
            let outcome = self.launchIfIdle()
            if case .waiting = outcome { return }
            if case .failed(let reason) = outcome { NSLog("Meltype: 更新できませんでした: %@", reason) }
            self.stopIdleWatch()
        }
        timer.resume()
        idleTimer = timer
    }

    private func stopIdleWatch() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    /// 公開済みで Mac の ZIP があるリリースのうち、ビルド番号が after より大きい最新のもの。
    static func newest(in data: Data, after build: Int) -> Release? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let tag = try! NSRegularExpression(pattern: "^hkrhd-build-([0-9]+)-")
        var best: Release?
        for release in list where release["draft"] as? Bool == false {
            guard let name = release["tag_name"] as? String,
                  let match = tag.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name), let number = Int(name[range]),
                  number > (best?.build ?? build) else { continue }
            let assets = release["assets"] as? [[String: Any]] ?? []
            guard let asset = assets.first(where: {
                      guard let name = $0["name"] as? String else { return false }
                      return name.hasPrefix("Meltype-") && name.hasSuffix("-mac.zip")
                  }),
                  let link = asset["browser_download_url"] as? String, let url = URL(string: link),
                  let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") else { continue }
            best = Release(build: number, zip: url, sha256: String(digest.dropFirst(7)).lowercased())
        }
        return best
    }

    private var attemptedFile: URL { directory.appendingPathComponent("attempted") }

    private var attemptedBuild: Int {
        (try? String(contentsOf: attemptedFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    }

    /// 新しい版を取得・検証して展開し、入力がなければ install.sh を起動する。
    func checkNow() -> Outcome {
        let data: Data
        do { data = try fetch(releases) } catch { return .failed("リリース一覧: \(error.localizedDescription)") }
        guard let release = Self.newest(in: data, after: max(currentBuild, attemptedBuild)) else {
            removeWork(except: nil)
            return .upToDate
        }
        removeWork(except: release.build)
        do {
            prepared = (release, try prepare(release))
        } catch {
            return .failed("\(release.build): \(error.localizedDescription)")
        }
        return launchIfIdle()
    }

    func launchIfIdle() -> Outcome {
        guard let (release, installer) = prepared else { return .upToDate }
        guard idleSeconds() >= requiredIdle else { return .waiting(release.build) }
        prepared = nil
        do {
            // 起動前に記録し、入れ替えに失敗した版を繰り返し試さない。
            try "\(release.build)\n".write(to: attemptedFile, atomically: true, encoding: .utf8)
            try spawnDetached(installer)
        } catch {
            return .failed("\(release.build): \(error.localizedDescription)")
        }
        NSLog("Meltype: ビルド %d に更新します", release.build)
        return .launched(release.build)
    }

    private func removeWork(except build: Int?) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where Int(entry.lastPathComponent) != nil && Int(entry.lastPathComponent) != build {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Meltype-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        var result: Result<Data, Error> = .failure(Failure("応答がありません"))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { result = .failure(Failure("HTTP \(status)")) }
            else if let data { result = .success(data) }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    /// 展開済みの install.sh を返す。ZIP のハッシュと、中の版がリリースのビルド番号と一致しなければ使わない。
    private func prepare(_ release: Release) throws -> URL {
        let work = directory.appendingPathComponent(String(release.build), isDirectory: true)
        let installer = work.appendingPathComponent("Meltype-mac/install.sh")
        let ready = work.appendingPathComponent("ready")
        if FileManager.default.fileExists(atPath: ready.path) { return installer }
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("Meltype-mac.zip")
        try download(release.zip, to: zip)
        guard try sha256(of: zip) == release.sha256 else { throw Failure("ZIP のハッシュが違います") }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        try FileManager.default.removeItem(at: zip)
        let info = work.appendingPathComponent("Meltype-mac/Meltype.app/Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: info), (plist["CFBundleVersion"] as? String).flatMap(Int.init) == release.build,
              FileManager.default.fileExists(atPath: installer.path) else { throw Failure("ZIP の中身がリリースと一致しません") }
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        return installer
    }

    private func download(_ url: URL, to destination: URL) throws {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Meltype-Updater", forHTTPHeaderField: "User-Agent")
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.downloadTask(with: request) { location, response, error in
            if let error { failure = error }
            else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { failure = Failure("HTTP \(status)") }
            else if let location {
                do { try FileManager.default.moveItem(at: location, to: destination) } catch { failure = error }
            }
            done.signal()
        }.resume()
        done.wait()
        if let failure { throw failure }
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("\(executable) が失敗しました (\(process.terminationStatus))") }
    }

    /// install.sh はこのプロセスを終了させるので、別セッションで起動して結果をログに残す。
    private func spawnDetached(_ installer: URL) throws {
        let log = directory.appendingPathComponent("install.log").path
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let arguments = ["/bin/bash", installer.path].map { strdup($0) } + [nil]
        defer { arguments.forEach { free($0) } }
        var pid = pid_t()
        let status = posix_spawn(&pid, "/bin/bash", &actions, &attributes, arguments, environ)
        guard status == 0 else { throw Failure("install.sh を起動できません: \(String(cString: strerror(status)))") }
    }
}
