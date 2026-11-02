// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import Foundation
import Darwin

/// ファイルの直接書込と、親ディレクトリ経由の作成・置換・削除を検知する。
/// start / reconcile と変更処理は、呼出元の直列キューだけで実行する。
final class DictionaryFileMonitor {
    private struct Watch {
        let device: dev_t
        let inode: ino_t
        let source: DispatchSourceFileSystemObject
    }

    private let queue: DispatchQueue
    private let directories: Set<String>
    private let files: () throws -> Set<String>
    private let changed: () -> Void
    private var watches: [String: Watch] = [:]

    init(queue: DispatchQueue, directories: Set<String>, files: @escaping () throws -> Set<String>,
         changed: @escaping () -> Void) {
        self.queue = queue
        self.directories = directories
        self.files = files
        self.changed = changed
    }

    deinit {
        for watch in watches.values { watch.source.cancel() }
    }

    @discardableResult
    func reconcile() throws -> Bool {
        let paths = try directories.union(files())
        var replaced = false
        for path in Set(watches.keys).subtracting(paths) {
            watches.removeValue(forKey: path)?.source.cancel()
            replaced = true
        }
        for path in paths {
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else {
                guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if let removed = watches.removeValue(forKey: path) {
                    removed.source.cancel()
                    replaced = true
                }
                continue
            }
            if let watch = watches[path], watch.device == metadata.st_dev, watch.inode == metadata.st_ino { continue }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                if errno == ENOENT { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0 else {
                let error = errno
                close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: queue)
            source.setCancelHandler { close(descriptor) }
            source.setEventHandler { [weak self] in
                guard let self else { return }
                do {
                    let replaced = try self.reconcile()
                    // 親の無関係なファイル変更では辞書を読み直さない。
                    if !self.directories.contains(path) || replaced { self.changed() }
                } catch {
                    NSLog("Meltype 辞書監視: %@", error.localizedDescription)
                }
            }
            watches.removeValue(forKey: path)?.source.cancel()
            watches[path] = Watch(device: opened.st_dev, inode: opened.st_ino, source: source)
            source.resume()
            replaced = true
        }
        return replaced
    }
}
