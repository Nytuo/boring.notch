//
//  FunctionButtonSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// The kinds of action a user can pick in the editor. Kept separate from
/// `FunctionButtonAction` because that carries associated values, which do not
/// work directly as `Picker` tags.
private enum ActionKind: String, CaseIterable, Identifiable {
    case openApp
    case openURL
    case runShortcut
    case screenSaver
    case openTab
    case toggleCaffeine
    case toggleMicrophone
    case cycleAudioOutput
    case toggleLowPowerMode
    case openEmojiPicker
    case toggleVoiceRecording

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openApp: return NSLocalizedString("function_kind_open_app", comment: "Action kind: open an app")
        case .openURL: return NSLocalizedString("function_kind_open_url", comment: "Action kind: open a URL")
        case .runShortcut: return NSLocalizedString("function_kind_shortcut", comment: "Action kind: run a Shortcut")
        case .screenSaver: return NSLocalizedString("function_action_screensaver", comment: "Function button: start screen saver")
        case .openTab: return NSLocalizedString("function_kind_open_tab", comment: "Action kind: open a notch tab")
        case .toggleCaffeine: return NSLocalizedString("function_action_caffeine", comment: "Function button: toggle Keep Awake")
        case .toggleMicrophone: return NSLocalizedString("function_action_microphone", comment: "Function button: toggle microphone")
        case .cycleAudioOutput: return NSLocalizedString("function_action_audio_output", comment: "Function button: cycle audio output device")
        case .toggleLowPowerMode: return NSLocalizedString("function_action_low_power", comment: "Function button: toggle Low Power Mode")
        case .openEmojiPicker: return NSLocalizedString("function_action_emoji", comment: "Function button: open the emoji picker")
        case .toggleVoiceRecording: return NSLocalizedString("function_action_voice_recording", comment: "Function button: start/stop a voice note")
        }
    }

    /// Whether this kind needs the free-text parameter field.
    var needsValue: Bool {
        switch self {
        case .openApp, .openURL, .runShortcut: return true
        default: return false
        }
    }

    var valuePrompt: String {
        switch self {
        case .openApp: return NSLocalizedString("function_value_bundle_id", comment: "Prompt for a bundle identifier")
        case .openURL: return NSLocalizedString("function_value_url", comment: "Prompt for a URL")
        case .runShortcut: return NSLocalizedString("function_value_shortcut", comment: "Prompt for a Shortcut name")
        default: return ""
        }
    }

    init(action: FunctionButtonAction) {
        switch action {
        case .openApp: self = .openApp
        case .openURL: self = .openURL
        case .runShortcut: self = .runShortcut
        case .screenSaver: self = .screenSaver
        case .openTab: self = .openTab
        case .toggleCaffeine: self = .toggleCaffeine
        case .toggleMicrophone: self = .toggleMicrophone
        case .cycleAudioOutput: self = .cycleAudioOutput
        case .toggleLowPowerMode: self = .toggleLowPowerMode
        case .openEmojiPicker: self = .openEmojiPicker
        case .toggleVoiceRecording: self = .toggleVoiceRecording
        }
    }

    func makeAction(value: String, tab: NotchTabItem) -> FunctionButtonAction {
        switch self {
        case .openApp: return .openApp(bundleID: value)
        case .openURL: return .openURL(string: value)
        case .runShortcut: return .runShortcut(name: value)
        case .screenSaver: return .screenSaver
        case .openTab: return .openTab(tab: tab)
        case .toggleCaffeine: return .toggleCaffeine
        case .toggleMicrophone: return .toggleMicrophone
        case .cycleAudioOutput: return .cycleAudioOutput
        case .toggleLowPowerMode: return .toggleLowPowerMode
        case .openEmojiPicker: return .openEmojiPicker
        case .toggleVoiceRecording: return .toggleVoiceRecording
        }
    }
}

struct FunctionButtonSettings: View {
    @Default(.functionButtons) private var buttons
    @Default(.functionButtonsEnabled) private var enabled

    @State private var editingID: UUID?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .functionButtonsEnabled) {
                    Text("Enable function buttons")
                }
                Defaults.Toggle(key: .functionButtonsShowLabels) {
                    Text("Show labels")
                }
                .disabled(!enabled)
                HelpText("Adds a row of custom action buttons to the opened notch.")
            } header: {
                Text("General")
            }

            Section {
                if buttons.isEmpty {
                    Text("No buttons configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(buttons) { button in
                        row(for: button)
                    }
                    .onMove { source, destination in
                        buttons.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { indexSet in
                        buttons.remove(atOffsets: indexSet)
                    }
                }

                Button("Add button") {
                    let new = FunctionButton(
                        title: NSLocalizedString("function_new_button", comment: "Default title for a new function button"),
                        action: .screenSaver
                    )
                    buttons.append(new)
                    editingID = new.id
                }
                .disabled(!enabled)
            } header: {
                Text("Buttons")
            } footer: {
                HelpText("Drag to reorder, swipe or use the minus button to remove.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Function Buttons")
    }

    @ViewBuilder
    private func row(for button: FunctionButton) -> some View {
        // Bind through the array so edits write straight back to preferences.
        if let index = buttons.firstIndex(where: { $0.id == button.id }) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { editingID == button.id },
                    set: { editingID = $0 ? button.id : nil }
                )
            ) {
                FunctionButtonEditor(button: $buttons[index])
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: button.effectiveIconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(button.title)
                        Text(button.action.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        buttons.removeAll { $0.id == button.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct FunctionButtonEditor: View {
    @Binding var button: FunctionButton

    @State private var kind: ActionKind
    @State private var value: String
    @State private var tab: NotchTabItem

    init(button: Binding<FunctionButton>) {
        _button = button
        let action = button.wrappedValue.action
        _kind = State(initialValue: ActionKind(action: action))
        _tab = State(initialValue: {
            if case .openTab(let tab) = action { return tab }
            return .player
        }())
        _value = State(initialValue: {
            switch action {
            case .openApp(let bundleID): return bundleID
            case .openURL(let string): return string
            case .runShortcut(let name): return name
            default: return ""
            }
        }())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $button.title)
                .textFieldStyle(.roundedBorder)

            TextField("SF Symbol (optional)", text: $button.iconName)
                .textFieldStyle(.roundedBorder)

            Picker("Action", selection: $kind) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .onChange(of: kind) { _, _ in commit() }

            if kind.needsValue {
                TextField(kind.valuePrompt, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: value) { _, _ in commit() }

                if kind == .openApp {
                    Button("Choose app…") { chooseApp() }
                }
            }

            if kind == .openTab {
                Picker("Tab", selection: $tab) {
                    ForEach(NotchTabItem.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .onChange(of: tab) { _, _ in commit() }
            }
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        button.action = kind.makeAction(value: value, tab: tab)
    }

    /// Picks an app with an open panel and stores its bundle identifier.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier
        else { return }

        value = identifier
        if button.title.isEmpty
            || button.title == NSLocalizedString("function_new_button", comment: "Default title for a new function button") {
            button.title = url.deletingPathExtension().lastPathComponent
        }
        commit()
    }
}
