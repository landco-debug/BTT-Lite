import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    private let store: ConfigStore

    private let profilePopup = NSPopUpButton()
    private let categoryPopup = NSPopUpButton()
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

    private let actionPopup = NSPopUpButton()
    private let actionKindPopup = NSPopUpButton()
    private let actionTitleField = NSTextField()
    private let actionEnabledCheck = NSButton(checkboxWithTitle: "Action enabled", target: nil, action: nil)
    private let primaryLabel = NSTextField(labelWithString: "Value")
    private let primaryText = NSTextView()
    private let primaryScroll = NSScrollView()
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let secondaryField = NSTextField()

    private var visibleRules: [Rule] = []
    private var selectedRuleID: UUID?
    private var selectedActionID: UUID?
    private var isReloading = false

    init(store: ConfigStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
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

        let left = buildRulesPane()
        let right = buildEditorPane()
        split.addArrangedSubview(left)
        split.addArrangedSubview(right)
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 390).isActive = true
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

    private func buildRulesPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false

        categoryPopup.addItems(withTitles: RuleCategory.allCases.map(\.rawValue))
        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged)
        categoryPopup.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(categoryPopup)

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
        rulesTable.rowHeight = 42
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
            categoryPopup.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            categoryPopup.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -10),
            categoryPopup.topAnchor.constraint(equalTo: pane.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: categoryPopup.bottomAnchor, constant: 8),
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

    private func rebuildVisibleRules() {
        guard let profile = store.activeProfile() else { visibleRules = []; return }
        let category = RuleCategory.allCases[categoryPopup.indexOfSelectedItem.clamped(to: 0...(RuleCategory.allCases.count - 1))]
        visibleRules = profile.rules.filter { rule in
            switch category {
            case .all: true
            case .global:
                if case .global = rule.scope { true } else { false }
            case .keyboard, .magicMouse, .trackpad, .other: rule.trigger.category == category
            case .applications:
                if case .application = rule.scope { true } else { false }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = visibleRules[row]
        let id = NSUserInterfaceItemIdentifier("RuleCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let text = NSTextField(wrappingLabelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let state = rule.enabled ? "●" : "○"
        let actions = rule.actions.filter(\.enabled).map(\.title).joined(separator: " + ")
        cell.textField?.stringValue = "\(state)  \(rule.trigger.displayName)\n\(actions.isEmpty ? "No enabled actions" : actions)"
        cell.textField?.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
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
            [keyCodeField, displayKeyField, modifiersField].forEach { $0.isHidden = false }
        case let .gesture(g):
            triggerTypePopup.selectItem(at: g.device == .magicMouse ? 1 : 2)
            fingersField.stringValue = String(g.fingers)
            gesturePopup.selectItem(withTitle: g.gesture.displayName)
            directionPopup.selectItem(withTitle: g.direction?.rawValue.capitalized ?? "None")
            [fingersField, gesturePopup, directionPopup].forEach { $0.isHidden = false }
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
        [keyCodeField, displayKeyField, modifiersField, fingersField, gesturePopup, directionPopup, systemKeyCodeField, systemKeyNameField].forEach { $0.isHidden = true }
    }

    private func reloadActionEditor() {
        guard let action = selectedAction() else {
            [actionPopup, actionKindPopup, actionTitleField, actionEnabledCheck, primaryLabel, secondaryField, secondaryLabel].forEach { $0.isEnabled = false }
            primaryText.isEditable = false
            primaryScroll.alphaValue = 0.5
            primaryText.string = ""
            return
        }
        [actionPopup, actionKindPopup, actionTitleField, actionEnabledCheck, primaryLabel, secondaryField, secondaryLabel].forEach { $0.isEnabled = true }
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
        let rule = Rule(
            name: "New Trigger",
            trigger: .keyboard(KeyboardTrigger(keyCode: 0, displayKey: "A", modifiers: [])),
            actions: [RuleAction(kind: .sendShortcut, title: "Send Keyboard Shortcut", parameters: ["keyCode": "0", "modifiers": "0"])]
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
            return .keyboard(KeyboardTrigger(
                keyCode: UInt16(clamping: Int(keyCodeField.stringValue) ?? 0),
                displayKey: displayKeyField.stringValue,
                modifiers: ModifierSet(rawValue: UInt64(modifiersField.stringValue) ?? 0)
            ))
        case 1, 2:
            let device: GestureDevice = triggerTypePopup.indexOfSelectedItem == 1 ? .magicMouse : .trackpad
            let gesture = GestureKind.allCases[gesturePopup.indexOfSelectedItem.clamped(to: 0...(GestureKind.allCases.count - 1))]
            let direction: GestureDirection? = directionPopup.indexOfSelectedItem == 0 ? nil : GestureDirection.allCases[(directionPopup.indexOfSelectedItem - 1).clamped(to: 0...(GestureDirection.allCases.count - 1))]
            return .gesture(GestureTrigger(device: device, fingers: max(1, Int(fingersField.stringValue) ?? 1), gesture: gesture, direction: direction))
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
