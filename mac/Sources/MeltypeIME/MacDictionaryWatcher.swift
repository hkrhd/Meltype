// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import AppKit

/// Core が外部から読み込む辞書だけを監視する。学習データの保存は対象外。
final class MacDictionaryWatcher {
    private let folder: URL
    private let dictionaries: URL
    private let reload: () -> Void
    private let queue = DispatchQueue(label: "Meltype.dictionary-watch", qos: .utility)
    private var monitor: DictionaryFileMonitor?
    private var scheduled: DispatchWorkItem?
    private var observer: NSObjectProtocol?
    private var contents: [String: Data]?

    init(directory: String, reload: @escaping () -> Void) {
        folder = URL(fileURLWithPath: directory, isDirectory: true)
        dictionaries = folder.appendingPathComponent("dictionaries", isDirectory: true)
        self.reload = reload
    }

    deinit {
        scheduled?.cancel()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func files() throws -> Set<String> {
        let names = ["english.txt", "japanese.txt", "romaji.txt", "propernouns.txt",
                     "candidates.txt", "emoji.txt", "contexts.txt", "misspellings.txt"]
        var paths = Set(names.map { dictionaries.appendingPathComponent($0).path })
        paths.insert(folder.appendingPathComponent("userdict.txt").path)
        if FileManager.default.fileExists(atPath: dictionaries.path) {
            let entries = try FileManager.default.contentsOfDirectory(at: dictionaries, includingPropertiesForKeys: nil)
            paths.formUnion(entries.filter { $0.pathExtension == "plist" }.map(\.path))
        }
        return paths
    }

    private func readChanges() {
        do {
            // 親フォルダー作成の通知時には、子の辞書がまだ存在しないことがある。
            // 反映を通知する前に監視対象を確定し、その直後の直接書込も取りこぼさない。
            try monitor?.reconcile()
            // 通知時だけ内容を比較する。同一内容の再保存・置換では Core を更新しない。
            var current: [String: Data] = [:]
            for path in try files() {
                do { current[path] = try Data(contentsOf: URL(fileURLWithPath: path)) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            }
            guard current != contents else { return }
            contents = current
            DispatchQueue.main.async { [weak self] in self?.reload() }
        } catch {
            NSLog("Meltype 辞書監視: 辞書を読めませんでした: %@", error.localizedDescription)
        }
    }

    private func schedule() {
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.readChanges() }
        scheduled = work
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    do { try self.monitor?.reconcile() }
                    catch { NSLog("Meltype 辞書監視: %@", error.localizedDescription) }
                    self.schedule()
                }
            }
        queue.async { [weak self] in
            guard let self else { return }
            self.monitor = DictionaryFileMonitor(queue: self.queue,
                directories: [self.folder.deletingLastPathComponent().path, self.folder.path, self.dictionaries.path],
                files: { [weak self] in try self?.files() ?? [] },
                changed: { [weak self] in self?.schedule() })
            do { try self.monitor?.reconcile() }
            catch { NSLog("Meltype 辞書監視: %@", error.localizedDescription) }
            // 監視開始前後の変更と、既存セッションが読んだ辞書との差も反映する。
            self.schedule()
        }
    }
}
