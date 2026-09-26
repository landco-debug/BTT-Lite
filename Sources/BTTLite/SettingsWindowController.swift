import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    private let store: ConfigStore

    private let profilePopup = NSPopUpButton()
    private let scopeTable = NSTableView()
    private let categoryControl = NSSegmentedControl(
        labels: ["All", "Keyboard", "Mouse", "Trackpad", "Other"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let rulesTable = NSTableView()
    private let editorScroll = NSScrollView()
    private let editorDocument = NSView()

    private let nameField = NSTextField()
    private let enabledCheck = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let scopePopup = NSPopUpButton()
    private let appNameField = NSTextField()
    private let bundleIDField = NSTextField()
    private let triggerTypePopup = NSPopUpButton()

    private let keyCodeField = NSTextField()
    private let displayKeyField = NSTextField()
    private let modifiersField = NSTextField()
    private let fingersField = NSTextField()
    private let gesturePopup = NSPopUpButton()
    private let directionPopup = NSPopUpButton()
    private let systemKeyCodeField = NSTextField()
    private let systemKeyNameField = NSTextField()
    private let triggerShortcutButton = NSButton(title: "Record Shortcut…", target: nil, action: nil)
    private let differentiateSidesCheck = NSButton(checkboxWithTitle: "Distinguish left/right modifiers", target: nil, action: nil)
    private let gestureModifierButton = NSButton(title: "Capture Held Modifiers", target: nil, action: nil)

    private let actionPopup = NSPopUpButton()
    private let actionKindPopup = NSPopUpButton()
    private let actionTitleField = NSTextField()
    private let actionEnabledCheck = NSButton(checkboxWithTitle: "Action enabled", target: nil, action: nil)
    private let primaryLabel = NSTextField(labelWithString: "Value")
    private let primaryText = NSTextView()
    private let primaryScroll = NSScrollView()
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let secondaryField = NSTextField()
    private let actionShortcutButton = NSButton(title: "Record Shortcut…", target: nil, action: nil)

    private enum ScopeItem: Equatable {
        case global
        case application(name: String, bundleIdentifier: String)

        var title: String {
            switch self {
            case .global: return "For All Apps"
            case let .application(name, _): return name.isEmpty ? "Application" : name
            }
        }

        var ruleScope: RuleScope {
            switch self {
            case .global: return .global
            case let .application(name, bundleIdentifier):
                return .application(name: name, bundleIdentifier: bundleIdentifier)
            }
        }
    }

    private var scopeItems: [ScopeItem] = [.global]
    private var selectedScope: ScopeItem = .global
    private var visibleRules: [Rule] = []
    private var shortcutMonitor: Any?
    private enum ShortcutRecordTarget { case trigger, action }
    private var shortcutRecordTarget: ShortcutRecordTarget?
    private var selectedRuleID: UUID?
    private var selectedActionID: UUID?
    private var isReloading = false

    init(store: ConfigStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BTT Lite Settings"
        // A menu-bar/accessory application otherwise can remain behind a regular
        // application such as Chrome even after activation.
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.setFrameAutosaveName("BTTLite.Settings")
        super.init(window: window)
        window.delegate = self
        buildUI()
        store.onChange = { [weak self] in self?.reloadAll(keepSelection: true) }
        reloadAll(keepSelection: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.level = .floating
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(top)

        top.addArrangedSubview(NSTextField(labelWithString: "Profile:"))
        profilePopup.target = self
        profilePopup.action = #selector(profileChanged)
        top.addArrangedSubview(profilePopup)
        top.addArrangedSubview(makeButton("New", #selector(newProfile)))
        top.addArrangedSubview(makeButton("Duplicate", #selector(duplicateProfile)))
        top.addArrangedSubview(makeButton("Delete", #selector(deleteProfile)))
        top.addArrangedSubview(NSView())
        top.addArrangedSubview(makeButton("Import BTT Preset…", #selector(importPreset)))

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        let scopes = buildScopePane()
        let rules = buildRulesPane()
        let right = buildEditorPane()
        split.addArrangedSubview(scopes)
        split.addArrangedSubview(rules)
        split.addArrangedSubview(right)
        scopes.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        scopes.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true
        rules.widthAnchor.constraint(greaterThanOrEqualToConstant: 450).isActive = true
        right.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true

        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            top.heightAnchor.constraint(equalToConstant: 28),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func buildScopePane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Applications")
        heading.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(heading)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(scroll)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scope"))
        column.title = "Applications"
        column.width = 210
        scopeTable.addTableColumn(column)
        scopeTable.headerView = nil
        scopeTable.rowHeight = 34
        scopeTable.dataSource = self
        scopeTable.delegate = self
        scroll.documentView = scopeTable

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            heading.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -8),
            heading.topAnchor.constraint(equalTo: pane.topAnchor, constant: 13),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        ])
        return pane
    }

    private func buildRulesPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        categoryControl.selectedSegment = 0
        categoryControl.segmentStyle = .rounded
        categoryControl.target = self
        categoryControl.action = #selector(categoryChanged)
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(categoryControl)

        let symbols = ["square.grid.2x2", "keyboard", "computermouse", "rectangle.and.hand.point.up.left", "ellipsis.circle"]
        for (index, symbol) in symbols.enumerated() {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: categoryControl.label(forSegment: index)) {
                categoryControl.setImage(image, forSegment: index)
            }
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(scroll)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.title = "Triggers"
        column.width = 390
        rulesTable.addTableColumn(column)
        rulesTable.headerView = nil
        rulesTable.rowHeight = 54
        rulesTable.dataSource = self
        rulesTable.delegate = self
        rulesTable.target = self
        rulesTable.doubleAction = #selector(duplicateRule)
        scroll.documentView = rulesTable

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(buttons)
        buttons.addArrangedSubview(makeButton("+", #selector(addRule)))
        buttons.addArrangedSubview(makeButton("−", #selector(deleteRule)))
        buttons.addArrangedSubview(makeButton("Duplicate", #selector(duplicateRule)))
        buttons.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            categoryControl.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            categoryControl.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -10),
            categoryControl.topAnchor.constraint(equalTo: pane.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            buttons.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            buttons.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -6),
            buttons.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -10),
            buttons.heightAnchor.constraint(equalToConstant: 28)
        ])
        return pane
    }

    private func buildEditorPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.drawsBackground = false
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(editorScroll)

        editorDocument.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.documentView = editorDocument

        var y: CGFloat = 18
        addSectionTitle("Rule", y: &y)
        addLabeledField("Name", field: nameField, y: &y, selector: #selector(ruleFieldChanged))
        enabledCheck.target = self
        enabledCheck.action = #selector(ruleFieldChanged)
        place(enabledCheck, x: 130, y: &y, height: 24)

        scopePopup.addItems(withTitles: ["Global", "Application"])
        scopePopup.target = self
        scopePopup.action = #selector(ruleFieldChanged)
        addLabeledControl("Scope", control: scopePopup, y: &y)
        addLabeledField("App name", field: appNameField, y: &y, selector: #selector(ruleFieldChanged))
        addLabeledField("Bundle ID", field: bundleIDField, y: &y, selector: #selector(ruleFieldChanged))

        addSectionTitle("Trigger", y: &y)
        triggerTypePopup.addItems(withTitles: ["Keyboard", "Magic Mouse", "Trackpad", "System Key", "Unsupported"])
        triggerTypePopup.target = self
        triggerTypePopup.action = #selector(triggerTypeChanged)
        addLabeledControl("Type", control: triggerTypePopup, y: &y)
        addLabeledField("Key code", field: keyCodeField, y: &y, selector: #selector(ruleFieldChanged))
        addLabeledField("Display key", field: displayKeyField, y: &y, selector: #selector(ruleFieldChanged))
        addLabeledField("Modifiers", field: modifiersField, y: &y, selector: #selector(ruleFieldChanged))
        modifiersField.placeholderString = "Raw NSEvent modifier flags, e.g. 1048576"
        triggerShortcutButton.target = self
        triggerShortcutButton.action = #selector(recordTriggerShortcut)
        triggerShortcutButton.toolTip = "Press the shortcut you want this keyboard trigger to recognize"
        addLabeledControl("Shortcut", control: triggerShortcutButton, y: &y)
        differentiateSidesCheck.target = self
        differentiateSidesCheck.action = #selector(ruleFieldChanged)
        place(differentiateSidesCheck, x: 130, y: &y, height: 24)
        gestureModifierButton.target = self
        gestureModifierButton.action = #selector(captureGestureModifiers)
        gestureModifierButton.toolTip = "Hold the desired modifier keys, then click this button"
        addLabeledControl("Gesture modifiers", control: gestureModifierButton, y: &y)
        addLabeledField("Fingers", field: fingersField, y: &y, selector: #selector(ruleFieldChanged))
        gesturePopup.addItems(withTitles: GestureKind.allCases.map(\.displayName))
        gesturePopup.target = self
        gesturePopup.action = #selector(ruleFieldChanged)
        addLabeledControl("Gesture", control: gesturePopup, y: &y)
        directionPopup.addItems(withTitles: ["None"] + GestureDirection.allCases.map { $0.rawValue.capitalized })
        directionPopup.target = self
        directionPopup.action = #selector(ruleFieldChanged)
        addLabeledControl("Direction", control: directionPopup, y: &y)
        addLabeledField("System code", field: systemKeyCodeField, y: &y, selector: #selector(ruleFieldChanged))
        addLabeledField("System name", field: systemKeyNameField, y: &y, selector: #selector(ruleFieldChanged))

        addSectionTitle("Actions", y: &y)
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 6
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(actionRow)
        actionPopup.target = self
        actionPopup.action = #selector(actionSelectionChanged)
        actionRow.addArrangedSubview(actionPopup)
        actionRow.addArrangedSubview(makeButton("+", #selector(addAction)))
        actionRow.addArrangedSubview(makeButton("−", #selector(deleteAction)))
        NSLayoutConstraint.activate([
            actionRow.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 130),
            actionRow.trailingAnchor.constraint(equalTo: editorDocument.trailingAnchor, constant: -20),
            actionRow.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y),
            actionRow.heightAnchor.constraint(equalToConstant: 26)
        ])
        y += 34

        actionEnabledCheck.target = self
        actionEnabledCheck.action = #selector(actionFieldChanged)
        place(actionEnabledCheck, x: 130, y: &y, height: 24)

        actionKindPopup.addItems(withTitles: ActionKind.allCases.map(\.displayName))
        actionKindPopup.target = self
        actionKindPopup.action = #selector(actionKindChanged)
        addLabeledControl("Action type", control: actionKindPopup, y: &y)
        addLabeledField("Action title", field: actionTitleField, y: &y, selector: #selector(actionFieldChanged))

        primaryLabel.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(primaryLabel)
        primaryScroll.hasVerticalScroller = true
        primaryScroll.borderType = .bezelBorder
        primaryScroll.translatesAutoresizingMaskIntoConstraints = false
        primaryText.isRichText = false
        primaryText.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        primaryText.delegate = self
        primaryScroll.documentView = primaryText
        editorDocument.addSubview(primaryScroll)
        NSLayoutConstraint.activate([
            primaryLabel.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 20),
            primaryLabel.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y + 4),
            primaryLabel.widthAnchor.constraint(equalToConstant: 100),
            primaryScroll.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 130),
            primaryScroll.trailingAnchor.constraint(equalTo: editorDocument.trailingAnchor, constant: -20),
            primaryScroll.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y),
            primaryScroll.heightAnchor.constraint(equalToConstant: 150)
        ])
        y += 160

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(secondaryLabel)
        secondaryField.target = self
        secondaryField.action = #selector(actionFieldChanged)
        secondaryField.delegate = self
        secondaryField.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(secondaryField)
        NSLayoutConstraint.activate([
            secondaryLabel.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 20),
            secondaryLabel.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y + 4),
            secondaryLabel.widthAnchor.constraint(equalToConstant: 100),
            secondaryField.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 130),
            secondaryField.trailingAnchor.constraint(equalTo: editorDocument.trailingAnchor, constant: -20),
            secondaryField.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y),
            secondaryField.heightAnchor.constraint(equalToConstant: 24)
        ])
        y += 42

        actionShortcutButton.target = self
        actionShortcutButton.action = #selector(recordActionShortcut)
        actionShortcutButton.toolTip = "Press the keyboard shortcut this action should send"
        addLabeledControl("Shortcut", control: actionShortcutButton, y: &y)

        let note = NSTextField(wrappingLabelWithString: "Configuration is stored as a small JSON file in Application Support. The settings window is created only when opened; the background agent does not keep these editor controls alive unnecessarily.")
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(note)
        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 20),
            note.trailingAnchor.constraint(equalTo: editorDocument.trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y)
        ])
        y += 70

        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            editorScroll.topAnchor.constraint(equalTo: pane.topAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            editorDocument.widthAnchor.constraint(equalTo: editorScroll.contentView.widthAnchor),
            editorDocument.heightAnchor.constraint(greaterThanOrEqualToConstant: y)
        ])
        return pane
    }

    private func addSectionTitle(_ title: String, y: inout CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y)
        ])
        y += 32
    }

    private func addLabeledField(_ title: String, field: NSTextField, y: inout CGFloat, selector: Selector) {
        field.target = self
        field.action = selector
        field.delegate = self
        addLabeledControl(title, control: field, y: &y)
    }

    private func addLabeledControl(_ title: String, control: NSView, y: inout CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(label)
        editorDocument.addSubview(control)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y + 4),
            label.widthAnchor.constraint(equalToConstant: 100),
            control.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: 130),
            control.trailingAnchor.constraint(equalTo: editorDocument.trailingAnchor, constant: -20),
            control.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y),
            control.heightAnchor.constraint(equalToConstant: 24)
        ])
        y += 32
    }

    private func place(_ control: NSView, x: CGFloat, y: inout CGFloat, height: CGFloat) {
        control.translatesAutoresizingMaskIntoConstraints = false
        editorDocument.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: editorDocument.leadingAnchor, constant: x),
            control.topAnchor.constraint(equalTo: editorDocument.topAnchor, constant: y),
            control.heightAnchor.constraint(equalToConstant: height)
        ])
        y += height + 8
    }

    private func makeButton(_ title: String, _ selector: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .rounded
        return button
    }

    private func reloadAll(keepSelection: Bool) {
        isReloading = true
        let priorRule = keepSelection ? selectedRuleID : nil
        let priorAction = keepSelection ? selectedActionID : nil

        profilePopup.removeAllItems()
        profilePopup.addItems(withTitles: store.configuration.profiles.map(\.name))
        if let index = store.configuration.activeProfileIndex { profilePopup.selectItem(at: index) }

        rebuildScopeItems()
        scopeTable.reloadData()
        if let scopeIndex = scopeItems.firstIndex(of: selectedScope) {
            scopeTable.selectRowIndexes(IndexSet(integer: scopeIndex), byExtendingSelection: false)
        }

        rebuildVisibleRules()
        rulesTable.reloadData()

        if let priorRule, let row = visibleRules.firstIndex(where: { $0.id == priorRule }) {
            rulesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectedRuleID = priorRule
            selectedActionID = priorAction
        } else if let first = visibleRules.first {
            selectedRuleID = first.id
            rulesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectedActionID = first.actions.first?.id
        } else {
            selectedRuleID = nil
            selectedActionID = nil
        }
        reloadEditor()
        isReloading = false
    }

    private func rebuildScopeItems() {
        guard let profile = store.activeProfile() else {
            scopeItems = [.global]
            selectedScope = .global
            return
        }

        let previous = selectedScope
        var next: [ScopeItem] = [.global]
        var seen = Set<String>()
        for rule in profile.rules {
            guard case let .application(name, bundleIdentifier) = rule.scope else { continue }
            let key = bundleIdentifier.isEmpty ? "name:" + name : "bundle:" + bundleIdentifier
            if seen.insert(key).inserted {
                next.append(.application(name: name, bundleIdentifier: bundleIdentifier))
            }
        }
        scopeItems = next
        selectedScope = next.contains(previous) ? previous : .global
    }

    private func selectedCategory() -> RuleCategory {
        switch categoryControl.selectedSegment {
        case 1: return .keyboard
        case 2: return .magicMouse
        case 3: return .trackpad
        case 4: return .other
        default: return .all
        }
    }

    private func scopeMatches(_ scope: RuleScope) -> Bool {
        switch (selectedScope, scope) {
        case (.global, .global):
            return true
        case let (.application(selectedName, selectedBundle), .application(name, bundle)):
            if !selectedBundle.isEmpty || !bundle.isEmpty { return selectedBundle == bundle }
            return selectedName == name
        default:
            return false
        }
    }

    private func rebuildVisibleRules() {
        guard let profile = store.activeProfile() else { visibleRules = []; return }
        let category = selectedCategory()
        visibleRules = profile.rules.filter { rule in
            guard scopeMatches(rule.scope) else { return false }
            if category == .all { return true }
            return rule.trigger.category == category
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === scopeTable ? scopeItems.count : visibleRules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === scopeTable {
            guard row >= 0, row < scopeItems.count else { return nil }
            return makeScopeCell(scopeItems[row])
        }
        guard row >= 0, row < visibleRules.count else { return nil }
        return makeRuleCell(visibleRules[row])
    }

    private func makeScopeCell(_ item: ScopeItem) -> NSView {
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(
            systemSymbolName: item == .global ? "globe" : "app",
            accessibilityDescription: item.title
        )
        icon.contentTintColor = .secondaryLabelColor
        cell.addSubview(icon)

        let text = NSTextField(labelWithString: item.title)
        text.font = NSFont.systemFont(ofSize: 13)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeRuleCell(_ rule: Rule) -> NSView {
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(
            systemSymbolName: triggerIconName(for: rule.trigger),
            accessibilityDescription: rule.trigger.compactDisplayName
        )
        icon.contentTintColor = rule.enabled ? .labelColor : .tertiaryLabelColor
        cell.addSubview(icon)

        let title = NSTextField(labelWithString: rule.trigger.compactDisplayName)
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: actionListSummary(for: rule))
        detail.font = NSFont.systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        cell.textField = title
        cell.alphaValue = rule.enabled ? 1.0 : 0.55
        cell.toolTip = rule.name

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func triggerIconName(for trigger: Trigger) -> String {
        switch trigger {
        case .keyboard: return "keyboard"
        case let .gesture(gesture):
            return gesture.device == .magicMouse ? "computermouse" : "rectangle.and.hand.point.up.left"
        case .systemKey: return "keyboard.badge.ellipsis"
        case .unsupported: return "questionmark.square.dashed"
        }
    }

    private func actionListSummary(for rule: Rule) -> String {
        let enabled = rule.actions.filter(\.enabled)
        let actions = enabled.isEmpty ? rule.actions : enabled
        guard let first = actions.first else { return "No actions" }
        let disabledSuffix = enabled.isEmpty ? " (disabled)" : ""
        if actions.count == 1 {
            return "Action: " + first.displaySummary + disabledSuffix
        }
        return "Action: " + first.displaySummary + " and " + String(actions.count - 1) + " more" + disabledSuffix
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading, let tableView = notification.object as? NSTableView else { return }

        if tableView === scopeTable {
            let row = scopeTable.selectedRow
            guard row >= 0, row < scopeItems.count else { return }
            selectedScope = scopeItems[row]
            selectedRuleID = nil
            selectedActionID = nil
            rebuildVisibleRules()
            rulesTable.reloadData()
            if let first = visibleRules.first {
                selectedRuleID = first.id
                selectedActionID = first.actions.first?.id
                rulesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
            reloadEditor()
            return
        }

        guard tableView === rulesTable else { return }
        let row = rulesTable.selectedRow
        guard row >= 0, row < visibleRules.count else { return }
        selectedRuleID = visibleRules[row].id
        selectedActionID = visibleRules[row].actions.first?.id
        reloadEditor()
    }

    private func reloadEditor() {
        isReloading = true
        defer { isReloading = false }
        guard let rule = selectedRule() else {
            setEditorEnabled(false)
            return
        }
        setEditorEnabled(true)
        nameField.stringValue = rule.name
        enabledCheck.state = rule.enabled ? .on : .off
        switch rule.scope {
        case .global:
            scopePopup.selectItem(at: 0)
            appNameField.stringValue = ""
            bundleIDField.stringValue = ""
        case let .application(name, bundleIdentifier):
            scopePopup.selectItem(at: 1)
            appNameField.stringValue = name
            bundleIDField.stringValue = bundleIdentifier
        }

        hideAllTriggerFields()
        switch rule.trigger {
        case let .keyboard(k):
            triggerTypePopup.selectItem(at: 0)
            keyCodeField.stringValue = String(k.keyCode)
            displayKeyField.stringValue = k.displayKey
            modifiersField.stringValue = String(k.modifiers.rawValue)
            differentiateSidesCheck.state = k.differentiateModifierSides == true ? .on : .off
            [keyCodeField, displayKeyField, modifiersField, triggerShortcutButton, differentiateSidesCheck].forEach { $0.isHidden = false }
            triggerShortcutButton.title = "Record…  " + shortcutDisplay(
                keyCode: k.keyCode,
                modifiers: k.modifiers,
                modifierSides: k.differentiateModifierSides == true ? (k.modifierSides ?? []) : [],
                displayKey: k.displayKey
            )
        case let .gesture(g):
            triggerTypePopup.selectItem(at: g.device == .magicMouse ? 1 : 2)
            fingersField.stringValue = String(g.fingers)
            gesturePopup.selectItem(withTitle: g.gesture.displayName)
            directionPopup.selectItem(withTitle: g.direction?.rawValue.capitalized ?? "None")
            modifiersField.stringValue = String((g.modifiers ?? []).rawValue)
            differentiateSidesCheck.state = g.differentiateModifierSides == true ? .on : .off
            gestureModifierButton.title = "Capture Held: " + gestureModifierDisplay(
                modifiers: g.modifiers ?? [],
                modifierSides: g.differentiateModifierSides == true ? (g.modifierSides ?? []) : []
            )
            [fingersField, gesturePopup, directionPopup, modifiersField, differentiateSidesCheck, gestureModifierButton].forEach { $0.isHidden = false }
        case let .systemKey(k):
            triggerTypePopup.selectItem(at: 3)
            systemKeyCodeField.stringValue = String(k.code)
            systemKeyNameField.stringValue = k.displayName
            [systemKeyCodeField, systemKeyNameField].forEach { $0.isHidden = false }
        case let .unsupported(description, rawType):
            triggerTypePopup.selectItem(at: 4)
            displayKeyField.stringValue = description
            keyCodeField.stringValue = rawType.map(String.init) ?? ""
            [keyCodeField, displayKeyField].forEach { $0.isHidden = false }
        }

        actionPopup.removeAllItems()
        actionPopup.addItems(withTitles: rule.actions.enumerated().map { "\($0.offset + 1). \($0.element.title)" })
        if let selectedActionID, let idx = rule.actions.firstIndex(where: { $0.id == selectedActionID }) {
            actionPopup.selectItem(at: idx)
        } else if let first = rule.actions.first {
            selectedActionID = first.id
            actionPopup.selectItem(at: 0)
        }
        reloadActionEditor()
    }

    private func hideAllTriggerFields() {
        [keyCodeField, displayKeyField, modifiersField, triggerShortcutButton, differentiateSidesCheck, gestureModifierButton, fingersField, gesturePopup, directionPopup, systemKeyCodeField, systemKeyNameField].forEach { $0.isHidden = true }
    }

    private func reloadActionEditor() {
        guard let action = selectedAction() else {
            [actionPopup, actionKindPopup, actionTitleField, actionEnabledCheck, primaryLabel, secondaryField, secondaryLabel, actionShortcutButton].forEach { $0.isEnabled = false }
            actionShortcutButton.isHidden = true
            primaryText.isEditable = false
            primaryScroll.alphaValue = 0.5
            primaryText.string = ""
            return
        }
        [actionPopup, actionKindPopup, actionTitleField, actionEnabledCheck, primaryLabel, secondaryField, secondaryLabel, actionShortcutButton].forEach { $0.isEnabled = true }
        primaryText.isEditable = true
        primaryScroll.alphaValue = 1.0
        if let idx = ActionKind.allCases.firstIndex(of: action.kind) { actionKindPopup.selectItem(at: idx) }
        actionTitleField.stringValue = action.title
        actionEnabledCheck.state = action.enabled ? .on : .off

        let fields = actionFields(for: action.kind)
        primaryLabel.stringValue = fields.primaryLabel ?? ""
        secondaryLabel.stringValue = fields.secondaryLabel ?? ""
        primaryLabel.isHidden = fields.primaryKey == nil
        primaryScroll.isHidden = fields.primaryKey == nil
        secondaryLabel.isHidden = fields.secondaryKey == nil
        secondaryField.isHidden = fields.secondaryKey == nil
        primaryText.string = fields.primaryKey.flatMap { action.parameters[$0] } ?? ""
        secondaryField.stringValue = fields.secondaryKey.flatMap { action.parameters[$0] } ?? ""
        actionShortcutButton.isHidden = action.kind != .sendShortcut
        if action.kind == .sendShortcut {
            let code = UInt16(action.parameters["keyCode"] ?? "")
            let mods = ModifierSet(rawValue: UInt64(action.parameters["modifiers"] ?? "") ?? 0)
            let display = action.parameters["displayKey"] ?? ""
            if let code {
                let sides = ModifierSideSet(rawValue: UInt64(action.parameters["modifierSides"] ?? "") ?? 0)
                actionShortcutButton.title = "Record…  " + shortcutDisplay(keyCode: code, modifiers: mods, modifierSides: sides, displayKey: display)
            } else {
                actionShortcutButton.title = "Record Shortcut…"
            }
        }
    }

    private func actionFields(for kind: ActionKind) -> (primaryKey: String?, primaryLabel: String?, secondaryKey: String?, secondaryLabel: String?) {
        switch kind {
        case .sendShortcut: ("keyCode", "Key code", "modifiers", "Modifiers")
        case .runShortcut: ("name", "Shortcut", nil, nil)
        case .launchPath: ("path", "Path", nil, nil)
        case .openURL: ("url", "URL", nil, nil)
        case .terminalCommand: ("command", "Command", nil, nil)
        case .shellScript, .appleScript, .javascriptTransform: ("script", "Script", nil, nil)
        case .waitForClipboardChange: ("timeout", "Timeout", nil, nil)
        case .toggleBluetoothDevice: ("deviceName", "Device", "address", "Address")
        case .builtIn, .unsupported: ("name", "Name", "bttActionType", "BTT type")
        default: (nil, nil, nil, nil)
        }
    }

    private func setEditorEnabled(_ enabled: Bool) {
        editorDocument.subviews.forEach { $0.alphaValue = enabled ? 1 : 0.45 }
    }

    private func selectedRule() -> Rule? {
        guard let id = selectedRuleID else { return nil }
        return store.activeProfile()?.rules.first(where: { $0.id == id })
    }

    private func selectedAction() -> RuleAction? {
        guard let rule = selectedRule(), let id = selectedActionID else { return nil }
        return rule.actions.first(where: { $0.id == id })
    }

    private func updateSelectedRule(_ body: (inout Rule) -> Void) {
        guard let id = selectedRuleID, var profile = store.activeProfile(), let index = profile.rules.firstIndex(where: { $0.id == id }) else { return }
        body(&profile.rules[index])
        store.replaceActiveProfile(with: profile)
    }

    private func updateSelectedAction(_ body: (inout RuleAction) -> Void) {
        guard let actionID = selectedActionID else { return }
        updateSelectedRule { rule in
            guard let idx = rule.actions.firstIndex(where: { $0.id == actionID }) else { return }
            body(&rule.actions[idx])
        }
    }

    @objc private func profileChanged() {
        guard !isReloading, profilePopup.indexOfSelectedItem >= 0 else { return }
        let id = store.configuration.profiles[profilePopup.indexOfSelectedItem].id
        selectedScope = .global
        selectedRuleID = nil
        selectedActionID = nil
        store.setActiveProfile(id)
    }

    @objc private func categoryChanged() { reloadAll(keepSelection: false) }

    @objc private func newProfile() { store.addProfile(named: "New Profile") }
    @objc private func duplicateProfile() { store.duplicateActiveProfile() }
    @objc private func deleteProfile() { store.deleteActiveProfile() }

    @objc private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = "Choose a BetterTouchTool .bttpreset file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try BTTImporter().importPreset(from: url)
            selectedScope = .global
            store.mutate { config in
                config.profiles.append(imported)
                config.activeProfileID = imported.id
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func addRule() {
        var profile = store.activeProfile() ?? Profile(name: "Default", rules: [])
        let category = selectedCategory()

        let trigger: Trigger
        let scope = selectedScope.ruleScope
        var name = "New Trigger"

        switch category {
        case .trackpad:
            trigger = .gesture(GestureTrigger(device: .trackpad, fingers: 3, gesture: .swipe, direction: .down))
            name = "New Trackpad Trigger"
        case .magicMouse:
            trigger = .gesture(GestureTrigger(device: .magicMouse, fingers: 3, gesture: .swipe, direction: .left))
            name = "New Magic Mouse Trigger"
        case .other:
            trigger = .unsupported(description: "New Unsupported Trigger", rawType: nil)
            name = "New Other Trigger"
        case .applications, .all, .global, .keyboard:
            trigger = .keyboard(KeyboardTrigger(keyCode: 0, displayKey: "A", modifiers: []))
            name = "New Keyboard Trigger"
        }

        let rule = Rule(
            name: name,
            scope: scope,
            trigger: trigger,
            actions: [RuleAction(kind: .sendShortcut, title: "Send Keyboard Shortcut", parameters: [:])]
        )
        profile.rules.append(rule)
        selectedRuleID = rule.id
        selectedActionID = rule.actions.first?.id
        store.replaceActiveProfile(with: profile)
    }

    @objc private func deleteRule() {
        guard let id = selectedRuleID, var profile = store.activeProfile() else { return }
        profile.rules.removeAll { $0.id == id }
        selectedRuleID = nil
        selectedActionID = nil
        store.replaceActiveProfile(with: profile)
    }

    @objc private func duplicateRule() {
        guard var profile = store.activeProfile(), let rule = selectedRule() else { return }
        var copy = rule
        copy.id = UUID()
        copy.name += " Copy"
        copy.actions = copy.actions.map { action in
            var a = action
            a.id = UUID()
            return a
        }
        profile.rules.append(copy)
        selectedRuleID = copy.id
        selectedActionID = copy.actions.first?.id
        store.replaceActiveProfile(with: profile)
    }

    @objc private func ruleFieldChanged() {
        guard !isReloading else { return }
        updateSelectedRule { rule in
            rule.name = nameField.stringValue
            rule.enabled = enabledCheck.state == .on
            if scopePopup.indexOfSelectedItem == 0 {
                rule.scope = .global
            } else {
                rule.scope = .application(name: appNameField.stringValue, bundleIdentifier: bundleIDField.stringValue)
            }
            rule.trigger = currentTriggerFromEditor(existing: rule.trigger)
        }
    }

    @objc private func triggerTypeChanged() {
        guard !isReloading else { return }
        updateSelectedRule { rule in
            switch triggerTypePopup.indexOfSelectedItem {
            case 0: rule.trigger = .keyboard(KeyboardTrigger(keyCode: 0, displayKey: "A", modifiers: []))
            case 1: rule.trigger = .gesture(GestureTrigger(device: .magicMouse, fingers: 3, gesture: .swipe, direction: .left))
            case 2: rule.trigger = .gesture(GestureTrigger(device: .trackpad, fingers: 3, gesture: .swipe, direction: .left))
            case 3: rule.trigger = .systemKey(SystemKeyTrigger(code: 0, displayName: "System Key"))
            default: rule.trigger = .unsupported(description: "Unsupported trigger", rawType: nil)
            }
        }
    }

    private func currentTriggerFromEditor(existing: Trigger) -> Trigger {
        switch triggerTypePopup.indexOfSelectedItem {
        case 0:
            let existingKeyboard: KeyboardTrigger? = {
                if case let .keyboard(value) = existing { return value }
                return nil
            }()
            return .keyboard(KeyboardTrigger(
                keyCode: UInt16(clamping: Int(keyCodeField.stringValue) ?? 0),
                displayKey: displayKeyField.stringValue,
                modifiers: ModifierSet(rawValue: UInt64(modifiersField.stringValue) ?? 0),
                modifierSides: existingKeyboard?.modifierSides,
                differentiateModifierSides: differentiateSidesCheck.state == .on
            ))
        case 1, 2:
            let device: GestureDevice = triggerTypePopup.indexOfSelectedItem == 1 ? .magicMouse : .trackpad
            let gesture = GestureKind.allCases[gesturePopup.indexOfSelectedItem.clamped(to: 0...(GestureKind.allCases.count - 1))]
            let direction: GestureDirection? = directionPopup.indexOfSelectedItem == 0 ? nil : GestureDirection.allCases[(directionPopup.indexOfSelectedItem - 1).clamped(to: 0...(GestureDirection.allCases.count - 1))]
            let existingGesture: GestureTrigger? = {
                if case let .gesture(value) = existing { return value }
                return nil
            }()
            return .gesture(GestureTrigger(
                device: device,
                fingers: max(1, Int(fingersField.stringValue) ?? 1),
                gesture: gesture,
                direction: direction,
                modifiers: ModifierSet(rawValue: UInt64(modifiersField.stringValue) ?? 0),
                modifierSides: existingGesture?.modifierSides,
                differentiateModifierSides: differentiateSidesCheck.state == .on
            ))
        case 3:
            return .systemKey(SystemKeyTrigger(code: Int(systemKeyCodeField.stringValue) ?? 0, displayName: systemKeyNameField.stringValue))
        default:
            return .unsupported(description: displayKeyField.stringValue, rawType: Int(keyCodeField.stringValue))
        }
    }

    @objc private func actionSelectionChanged() {
        guard let rule = selectedRule(), actionPopup.indexOfSelectedItem >= 0, actionPopup.indexOfSelectedItem < rule.actions.count else { return }
        selectedActionID = rule.actions[actionPopup.indexOfSelectedItem].id
        reloadActionEditor()
    }

    @objc private func addAction() {
        let action = RuleAction(kind: .sendShortcut, title: "Send Keyboard Shortcut", parameters: ["keyCode": "0", "modifiers": "0"])
        selectedActionID = action.id
        updateSelectedRule { $0.actions.append(action) }
    }

    @objc private func deleteAction() {
        guard let id = selectedActionID else { return }
        selectedActionID = nil
        updateSelectedRule { rule in
            rule.actions.removeAll { $0.id == id }
            selectedActionID = rule.actions.first?.id
        }
    }

    @objc private func actionKindChanged() {
        guard !isReloading else { return }
        let kind = ActionKind.allCases[actionKindPopup.indexOfSelectedItem.clamped(to: 0...(ActionKind.allCases.count - 1))]
        updateSelectedAction { action in
            action.kind = kind
            action.title = kind.displayName
            action.parameters = [:]
        }
    }

    @objc private func actionFieldChanged() {
        guard !isReloading else { return }
        updateActionFieldsFromEditor()
    }

    @objc private func recordTriggerShortcut() {
        beginShortcutRecording(target: .trigger)
    }

    @objc private func recordActionShortcut() {
        beginShortcutRecording(target: .action)
    }

    private func beginShortcutRecording(target: ShortcutRecordTarget) {
        endShortcutRecording()
        shortcutRecordTarget = target
        let button = target == .trigger ? triggerShortcutButton : actionShortcutButton
        button.title = "Press shortcut…  (Esc cancels)"
        window?.makeKeyAndOrderFront(nil)

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.endShortcutRecording()
                self.reloadEditor()
                return nil
            }

            let modifiers = self.modifierSet(from: event.modifierFlags)
            let sides = self.modifierSides(from: event.modifierFlags)
            let displayKey = self.displayKey(for: event)
            switch self.shortcutRecordTarget {
            case .trigger:
                self.updateSelectedRule { rule in
                    rule.trigger = .keyboard(KeyboardTrigger(
                        keyCode: UInt16(event.keyCode),
                        displayKey: displayKey,
                        modifiers: modifiers,
                        modifierSides: sides,
                        differentiateModifierSides: self.differentiateSidesCheck.state == .on
                    ))
                }
            case .action:
                self.updateSelectedAction { action in
                    action.kind = .sendShortcut
                    action.title = "Send Keyboard Shortcut"
                    action.parameters["keyCode"] = String(event.keyCode)
                    action.parameters["modifiers"] = String(modifiers.rawValue)
                    action.parameters["modifierSides"] = String(sides.rawValue)
                    action.parameters["displayKey"] = displayKey
                }
            case .none:
                break
            }
            self.endShortcutRecording()
            self.reloadEditor()
            return nil
        }
    }

    private func endShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        shortcutRecordTarget = nil
    }

    private func modifierSet(from flags: NSEvent.ModifierFlags) -> ModifierSet {
        let independent = flags.intersection(.deviceIndependentFlagsMask)
        var result: ModifierSet = []
        if independent.contains(.capsLock) { result.insert(.capsLock) }
        if independent.contains(.shift) { result.insert(.shift) }
        if independent.contains(.control) { result.insert(.control) }
        if independent.contains(.option) { result.insert(.option) }
        if independent.contains(.command) { result.insert(.command) }
        if independent.contains(.function) { result.insert(.function) }
        return result
    }

    private func modifierSides(from flags: NSEvent.ModifierFlags) -> ModifierSideSet {
        ModifierSideSet(rawValue: UInt64(flags.rawValue)).intersection(.all)
    }

    @objc private func captureGestureModifiers() {
        guard let selected = selectedRule(),
              case .gesture = selected.trigger else { return }
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let modifiers = modifierSet(from: flags)
        let sides = modifierSides(from: flags)
        updateSelectedRule { rule in
            guard case let .gesture(current) = rule.trigger else { return }
            var gesture = current
            gesture.modifiers = modifiers
            gesture.modifierSides = sides
            gesture.differentiateModifierSides = self.differentiateSidesCheck.state == .on
            rule.trigger = .gesture(gesture)
        }
    }

    private func displayKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let value = event.charactersIgnoringModifiers, !value.isEmpty {
                return value.uppercased()
            }
            return "Key " + String(event.keyCode)
        }
    }

    private func shortcutDisplay(
        keyCode: UInt16,
        modifiers: ModifierSet,
        modifierSides: ModifierSideSet = [],
        displayKey: String
    ) -> String {
        let key = displayKey.isEmpty ? "Key " + String(keyCode) : displayKey
        let prefix = modifierSides.isEmpty ? modifiers.symbols : modifierSides.symbols(generic: modifiers)
        return prefix + key
    }

    private func gestureModifierDisplay(modifiers: ModifierSet, modifierSides: ModifierSideSet) -> String {
        if modifiers.isEmpty { return "None" }
        return modifierSides.isEmpty ? modifiers.symbols : modifierSides.symbols(generic: modifiers)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isReloading else { return }
        if let field = obj.object as? NSTextField, field === primaryLabel || field === secondaryLabel { return }
        if let field = obj.object as? NSTextField,
           field === actionTitleField || field === secondaryField {
            updateActionFieldsFromEditor()
        } else {
            ruleFieldChanged()
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !isReloading, notification.object as? NSTextView === primaryText else { return }
        updateActionFieldsFromEditor()
    }

    func windowWillClose(_ notification: Notification) {
        endShortcutRecording()
    }

    private func updateActionFieldsFromEditor() {
        let kind = ActionKind.allCases[actionKindPopup.indexOfSelectedItem.clamped(to: 0...(ActionKind.allCases.count - 1))]
        let fields = actionFields(for: kind)
        updateSelectedAction { action in
            action.enabled = actionEnabledCheck.state == .on
            action.kind = kind
            action.title = actionTitleField.stringValue
            if let key = fields.primaryKey { action.parameters[key] = primaryText.string }
            if let key = fields.secondaryKey { action.parameters[key] = secondaryField.stringValue }
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
