//
//  LauncherView.swift
//  boringNotch
//
//  F-14: apps + in-app actions in one filtered, keyboard-navigable list.
//

import AppKit
import SwiftUI

private struct LauncherResult: Identifiable {
    enum Kind {
        case app(LauncherAppEntry)
        case action(FunctionButton)
    }

    let id: String
    let title: String
    let iconName: String?
    let icon: NSImage?
    let kind: Kind

    @MainActor
    func run(launcher: UniversalLauncherManager) {
        switch kind {
        case .app(let entry):
            launcher.launch(entry)
        case .action(let button):
            FunctionButtonRunner.run(button)
        }
    }
}

struct LauncherView: View {
    @ObservedObject private var launcher = UniversalLauncherManager.shared
    @EnvironmentObject var vm: BoringViewModel

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var contentWidth: CGFloat { NotchViews.launcher.contentWidth }

    /// A small, curated set — not every `FunctionButtonAction`, just the
    /// ones that make sense to reach for without any configuration.
    private static let quickActions: [FunctionButton] = [
        FunctionButton(title: NSLocalizedString("launcher_action_emoji", comment: "Launcher action: open emoji picker"), action: .openEmojiPicker),
        FunctionButton(title: NSLocalizedString("launcher_action_caffeine", comment: "Launcher action: toggle Keep Awake"), action: .toggleCaffeine),
        FunctionButton(title: NSLocalizedString("launcher_action_voice", comment: "Launcher action: start/stop a voice note"), action: .toggleVoiceRecording),
        FunctionButton(title: NSLocalizedString("launcher_action_screensaver", comment: "Launcher action: start the screen saver"), action: .screenSaver)
    ]

    private var results: [LauncherResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let appResults: [LauncherAppEntry]
        if trimmed.isEmpty {
            let recents = launcher.recentBundleIDs.compactMap { id in launcher.installedApps.first { $0.id == id } }
            let rest = launcher.installedApps.filter { entry in !launcher.recentBundleIDs.contains(entry.id) }
            appResults = Array((recents + rest).prefix(30))
        } else {
            appResults = launcher.installedApps
                .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
                .prefix(20)
                .map { $0 }
        }

        let actionResults = Self.quickActions.filter { trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed) }

        let apps = appResults.map { entry in
            LauncherResult(id: "app.\(entry.id)", title: entry.name, iconName: nil, icon: launcher.icon(for: entry), kind: .app(entry))
        }
        let actions = actionResults.map { button in
            LauncherResult(id: "action.\(button.id)", title: button.title, iconName: button.effectiveIconName, icon: nil, kind: .action(button))
        }

        return apps + actions
    }

    var body: some View {
        VStack(spacing: 6) {
            searchField

            if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: contentWidth)
        .onAppear {
            launcher.ensureScanned()
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(NSLocalizedString("launcher_search_placeholder", comment: "Launcher search field placeholder"), text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(runSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(0, results.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    resultRow(result, isSelected: index == selectedIndex)
                        .onTapGesture {
                            selectedIndex = index
                            runSelected()
                        }
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func resultRow(_ result: LauncherResult, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon = result.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else if let iconName = result.iconName {
                Image(systemName: iconName)
                    .frame(width: 20)
                    .foregroundStyle(Color.effectiveAccent)
            }
            Text(result.title)
                .font(.callout)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.1) : .clear)
        )
    }

    private var emptyState: some View {
        Text(NSLocalizedString("launcher_no_results", comment: "No launcher results for the current query"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 20)
    }

    private func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        results[selectedIndex].run(launcher: launcher)
        vm.close()
    }
}
