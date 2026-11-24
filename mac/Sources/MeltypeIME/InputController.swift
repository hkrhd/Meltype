// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro
// Copyright (C) 2026 aster-void
// Copyright (C) 2026 HarukiKubota

import Carbon.HIToolbox
import Cocoa
import InputMethodKit

/// 入力欄 (クライアント) ごとの IME。Input Method Kit から読んだ事実 (キー・キャレットの前後の文字) を本体 (libMeltypeNative.dylib の ImeHost) に渡し、
/// 返ってきた指示 (確定する文字・変換中の表示・候補・入力モードの表示) を入力欄に反映する。入力モードは本体が決めるので、ここでは持たない。
/// Info.plist の InputMethodServerControllerClass に書いた名前で、Input Method Kit が作る。
@objc(MeltypeInputController)
final class MeltypeInputController: IMKInputController, ModeServiceTarget {
    /// 本体が最後に返した表示のモード (入力メニューのチェックに使う)
    private var japanese = true
    private var hasMarkedText = false
    private let modeIndicator = ModeIndicator.shared
    /// 候補と案内のパネル。表示するのは今の入力欄の分だけなので、すべての入力欄で 1 つを共有する。
    private static let compositionPanel = CompositionPanel(choose: { index in
        active?.sendCandidate("CandidateClicked", index: index)
    }, highlight: { index in
        active?.sendCandidate("CandidateHighlighted", index: index)
    })

    /// ロック画面と OS の認証ダイアログを Password として送り、Core でアプリ別設定より優先する (#1752)。
    private static let authenticationApps: Set<String> = ["com.apple.loginwindow", "com.apple.SecurityAgent"]

    /// 判定の文脈とコードの行の判定に使う、キャレットの前の文字数
    private static let beforeLength = 4000
    private static let afterLength = 20

    /// フォーカスのある入力欄。背景の変換の結果が届いたら、この入力欄の表示を作り直す。メインスレッドからだけ使う。
    nonisolated(unsafe) static weak var active: MeltypeInputController?

    /// 入力の本体 (ImeHost)。Input Method Kit は入力欄ごとにこのクラスを作るが、入力モードはすべての入力欄で同じにするので、プロセスで 1 つにする。
    /// メインスレッドからだけ使う。
    nonisolated(unsafe) private static var host = NativeCore.shared.createHost()
    nonisolated(unsafe) private static var dictionaryReloadPending = false

    /// 辞書を読み直したら (MacDictionaryWatcher → NativeCore.reloadDictionaries)、入力欄の本体を作り直して反映する。
    /// 送るのは同じプロセスだけなので、ほかのプロセスから届く分散通知では受けない
    nonisolated(unsafe) private static let dictionaryObserver = NotificationCenter.default.addObserver(
        forName: Notification.Name("MeltypeUserDictionaryChanged"), object: nil, queue: .main
    ) { _ in
        MeltypeInputController.dictionaryReloadPending = true
        MeltypeInputController.active?.reloadDictionaryIfIdle()
    }

    private func reloadDictionaryIfIdle() {
        guard Self.dictionaryReloadPending, !hasMarkedText,
              let replacement = NativeCore.shared.createHost() else { return }
        NativeCore.shared.destroyHost(Self.host)
        Self.host = replacement
        Self.dictionaryReloadPending = false
        _ = NativeCore.shared.send(Self.host, ["version": 1, "instance": "mac",
            "type": japanese ? "JapaneseModeSelected" : "AlphanumericModeSelected"])
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        _ = Self.dictionaryObserver
    }

    // ---- 本体とのやり取り ----

    /// 出来事を本体に送り、返ってきた指示を入力欄に出す。本体が処理できなければ nil。
    @discardableResult
    private func send(_ type: String, client: IMKTextInput?, _ fields: [String: Any] = [:], keyEvent: NSEvent? = nil) -> ImeOutput? {
        var event: [String: Any] = ["version": 1, "type": type, "instance": "mac"]
        let app = client?.bundleIdentifier()
        if let app, Self.authenticationApps.contains(app) {
            // ユーザー名は通常自動で入るため、SecurityAgent ではユーザー名欄も含めて打鍵を通す。
            // 未確定入力の取消に必要な属性だけを送り、打鍵の内容や周辺文字列は Core に渡さない。
            event["field"] = ["traits": ["Password"]]
        } else {
            if let client {
                event["field"] = field(of: client, app: app)
            }
            if let keyEvent { event["key"] = key(of: keyEvent) }
        }
        event.merge(fields) { _, new in new }
        guard let output = NativeCore.shared.send(Self.host, event) else { return nil }
        japanese = output.state.languageMode == .japanese
        if let client { apply(output.result, to: client) }
        reloadDictionaryIfIdle()
        if output.state.modeIndicatorMs > 0 {
            modeIndicator.show(japanese ? .japanese : .direct, caret: client.flatMap { modeIndicatorCaret($0) }, milliseconds: output.state.modeIndicatorMs)
        }
        return output
    }

    /// 入力欄の事実 (ImeField)。キャレットの前後は、変換中なら変換中の文字の前後
    private func field(of client: IMKTextInput, app: String?) -> [String: Any] {
        var field: [String: Any] = ["composing": hasMarkedText]
        if let app { field["app"] = app }
        let marked = client.markedRange()
        let anchor = marked.location != NSNotFound && marked.length > 0 ? marked : client.selectedRange()
        guard anchor.location != NSNotFound else {
            noteBefore(unreadable: true) { "selectedRange が NSNotFound" }
            return field
        }
        if anchor.length > 0, !hasMarkedText, let selection = client.attributedSubstring(from: anchor)?.string { field["selection"] = selection }
        let start = max(0, anchor.location - Self.beforeLength)
        let requested = NSRange(location: start, length: anchor.location - start)
        let before = client.attributedSubstring(from: requested)?.string
        if let before { field["before"] = before }
        noteBefore(unreadable: before == nil) {
            // 原因を調べるために、短い範囲なら読めるかも書く
            let shortStart = max(0, anchor.location - 20)
            let short = client.attributedSubstring(from: NSRange(location: shortStart, length: anchor.location - shortStart)) != nil
            return "頼んだ範囲 \(NSStringFromRange(requested))・selectedRange \(NSStringFromRange(client.selectedRange()))・" +
                "markedRange \(NSStringFromRange(marked))・20 文字前からなら\(short ? "読めた" : "読めない")"
        }
        if let after = client.attributedSubstring(from: NSRange(location: anchor.location + anchor.length, length: Self.afterLength))?.string { field["after"] = after }
        return field
    }

    /// キャレットの前の文字を読めないか (読めない入力欄を調べられるように、変わったときだけ Console に書く)
    private var beforeUnreadable = false

    private func noteBefore(unreadable: Bool, _ detail: () -> String) {
        guard unreadable != beforeUnreadable else { return }
        beforeUnreadable = unreadable
        NSLog("Meltype: %@", unreadable ? "キャレットの前の文字を読めません (\(detail()))" : "キャレットの前の文字を読めるようになりました")
    }

    func refreshConversion() {
        send("ConversionFinished", client: client())
    }

    // ---- Input Method Kit からの呼び出し ----

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.active = self
        ModeServices.shared.activate(self)
        send("CaretMoved", client: client(), ["caret": ["moved": true, "passedKey": 0, "focusEntered": true]])
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        return send("KeyPressed", client: client, keyEvent: event)?.result.consumed ?? false
    }

    private func key(of event: NSEvent) -> [String: Any] {
        let flags = event.modifierFlags
        var key: [String: Any] = ["vk": KeyMapping.virtualKey(for: event),
                                  "shift": flags.contains(.shift), "ctrl": flags.contains(.control),
                                  "alt": flags.contains(.option), "command": flags.contains(.command), "repeat": event.isARepeat]
        // event.characters は「見た目の 1 文字」で、UTF-16 要素が複数のことがある
        // (補助面の文字・結合文字・ZWJ 絵文字・異体字セレクター)。1 スカラーならそのコードポイント、複数ならそのまま渡す
        let text = KeyMapping.text(for: event)
        let scalars = Array(text.unicodeScalars)
        if scalars.count > 1 {
            key["text"] = text
        } else if let scalar = scalars.first {
            // JIS キーボードの Option+Space などは全角・ノーブレークの空白を入れる。Space として渡す (本体が全角・半角を決める)
            let space = scalar.value == 0x20 || scalar.value == 0x3000 || scalar.value == 0xA0
            key["ch"] = space ? 0x20 : scalar.value
            if space { key["vk"] = 0x20 }
        }
        return key
    }

    /// フォーカスが外れた・クリックで別の場所に移ったときなど。未確定の内容をそのまま確定する。
    override func commitComposition(_ sender: Any!) {
        guard let client = (sender as? IMKTextInput) ?? self.client() else { return }
        send("CommitRequested", client: client, ["caret": ["moved": true, "passedKey": 0]])
    }

    override func deactivateServer(_ sender: Any!) {
        if Self.active === self { Self.active = nil }
        ModeServices.shared.deactivate(self)
        if let client = (sender as? IMKTextInput) ?? self.client() {
            send("CommitRequested", client: client, ["caret": ["moved": true, "passedKey": 0, "focusLeft": true]])
        }
        Self.compositionPanel.hide()
        super.deactivateServer(sender)
    }

    // ---- メニュー (メニューバーの入力メニュー) ----

    /// 入力メニュー。操作は自動更新の適用だけにし、辞書の置き場所と自動反映の説明を出す。
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let contents = Self.menuContents(updateBuild: MacUpdatePrompt.shared.updater?.readyBuild)
        for line in contents.notes {
            let item = menu.addItem(withTitle: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
        }
        if let title = contents.updateTitle {
            menu.addItem(.separator())
            let updateItem = menu.addItem(withTitle: title, action: #selector(installUpdate(_:)), keyEquivalent: "")
            updateItem.target = self
        }
        return menu
    }

    /// 入力メニューの中身 (NSMenu 自体はテストで作れないので中身だけ切り出す。Actions の Swift テストで検証する)。
    /// notes は操作なしの説明だけ、updateTitle は自動更新の適用だけ。ほかの操作は足さない。
    static func menuContents(updateBuild: Int?) -> (notes: [String], updateTitle: String?) {
        ([dictionaryReloadNote, dictionariesLocationNote],
         updateBuild.map { MacUpdatePrompt.menuTitle(build: $0) })
    }

    private static let dictionaryReloadNote = "辞書を変更すると、入力中でないときに自動で反映されます（再起動は不要）"

    /// 辞書を置くフォルダー (データフォルダーの dictionaries/)。ホームだけ ~ に短縮して出す。
    private static var dictionariesLocationNote: String {
        guard let path = NativeCore.shared.dataDirectory.map({
            URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("dictionaries").path
        }) else { return "macOSのユーザー辞書と dictionaries 以下のファイル（english.txt など）" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shown = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        return "macOSのユーザー辞書と \(shown) 以下のファイル（english.txt など）"
    }

    @objc private func installUpdate(_ sender: Any?) {
        commitComposition(client())
        DispatchQueue.main.async { MacUpdatePrompt.shared.installUpdate() }
    }

    func selectModeFromService(_ action: ModeShortcutAction) -> Bool {
        guard let client = client() else { return false }
        switch action {
        case .japanese: send("JapaneseModeSelected", client: client)
        case .direct: send("AlphanumericModeSelected", client: client)
        case .toggle: send("ModeToggleRequested", client: client)
        }
        return true
    }

    private func modeIndicatorCaret(_ client: IMKTextInput) -> NSRect? {
        // IMK のインライン位置。0 はインラインセッションがない場合の現在の選択を表す。
        let marked = client.markedRange()
        let index = marked.location == NSNotFound ? 0 : marked.length
        var rectangle = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rectangle)
        return ModeIndicator.validCaret(rectangle) ? rectangle : nil
    }

    // ---- 指示を入力欄に反映する ----

    private func apply(_ result: SessionResult, to client: IMKTextInput) {
        for edit in result.commits {
            // 確定し直し: キャレット (変換中の文字があればその先頭) の前の remove を置き換える (本体が照合済み)
            var range = NSRange(location: NSNotFound, length: 0)
            if let remove = edit.removeBefore {
                let length = (remove as NSString).length
                let marked = client.markedRange()
                let caret = marked.location != NSNotFound && marked.length > 0 ? marked.location : client.selectedRange().location
                if caret != NSNotFound && caret >= length { range = NSRange(location: caret - length, length: length) }
            }
            client.insertText(NSAttributedString(string: edit.text), replacementRange: range)
            hasMarkedText = false
        }
        if let view = result.view {
            showComposition(view, client: client)
        } else {
            hideComposition(client: client)
        }
    }

    /// 変換中の文字を入力欄に下線付きで出す (変換中は文節ごと、選んでいる文節は太い下線)。
    private func showComposition(_ view: CompositionView, client: IMKTextInput) {
        let text = NSMutableAttributedString(string: view.text)
        let length = (view.text as NSString).length
        if view.converting && !view.clauses.isEmpty {
            var location = 0
            for (index, clause) in view.clauses.enumerated() {
                let clauseLength = (clause as NSString).length
                let style = index == view.selectedClause ? kTSMHiliteSelectedConvertedText : kTSMHiliteConvertedText
                addMark(style, to: text, range: NSRange(location: location, length: clauseLength))
                location += clauseLength
            }
        } else {
            addMark(kTSMHiliteRawText, to: text, range: NSRange(location: 0, length: length))
        }
        client.setMarkedText(NSAttributedString(attributedString: text), selectionRange: NSRange(location: length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarkedText = length > 0
        showCompositionPanel(view, markedText: view.text as NSString, client: client)
    }

    private func hideComposition(client: IMKTextInput) {
        if hasMarkedText {
            // Keep the payload type consistent when clearing marked text.
            client.setMarkedText(NSAttributedString(string: ""), selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            hasMarkedText = false
        }
        Self.compositionPanel.hide()
    }

    private func showCompositionPanel(_ view: CompositionView, markedText: NSString, client: IMKTextInput) {
        let guide = [view.typedKeys, view.spellingSuggestion, view.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "　")
        guard markedText.length > 0, !guide.isEmpty || view.candidates != nil else {
            Self.compositionPanel.hide()
            return
        }

        // IMK は文書全体からの位置ではなく、未確定文字列の先頭からの UTF-16 オフセットを取る。
        var start = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &start)
        var end = start
        let last = markedText.rangeOfComposedCharacterSequence(at: markedText.length - 1).location
        if last > 0 {
            end = .zero
            _ = client.attributes(forCharacterIndex: last, lineHeightRectangle: &end)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: start.minX, y: start.midY)) }
        let caretPlacement = screen.flatMap { screen in
            screen.frame.contains(NSPoint(x: end.minX, y: end.midY))
                ? CompositionPanelPlacement(start: start, end: end, visible: screen.visibleFrame) : nil
        }
        // 入力位置を返さないアプリでも候補を選べるよう、入力モードの表示と同じくマウスのある画面の下端に出す。
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let placement = caretPlacement ?? mouseScreen.map({ CompositionPanelPlacement(bottomOf: $0.visibleFrame) }) else {
            Self.compositionPanel.hide()
            return
        }

        Self.compositionPanel.show(guide: guide, list: view.candidates, converting: view.converting, clause: view.selectedClause, placement: placement,
                   aboveWindowLevel: client.windowLevel())
    }

    private func sendCandidate(_ event: String, index: Int) {
        guard let client = client() else { return }
        send(event, client: client, ["index": index])
    }

    private func addMark(_ style: Int, to text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, range.location + range.length <= text.length,
              let marks = mark(forStyle: style, at: range) else { return }
        var attributes: [NSAttributedString.Key: Any] = [:]
        for (key, value) in marks {
            if let name = key as? String {
                attributes[NSAttributedString.Key(name)] = value
            } else if let name = key as? NSAttributedString.Key {
                attributes[name] = value
            }
        }
        text.addAttributes(attributes, range: range)
    }
}
