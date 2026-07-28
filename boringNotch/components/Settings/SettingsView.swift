//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case layout
    case media
    case calendar
    case clock
    case systemStats
    case osd
    case battery
    case caffeine
    case bluetooth
    case weather
    case shelf
    case clipboard
    case appSwitcher
    case downloads
    case screenshots
    case functionButtons
    case notifications
    case extensions
    case lockScreen
    case mirror
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .layout: "Layout"
        case .media: "Media"
        case .calendar: "Calendar"
        case .clock: "Clock"
        case .systemStats: "System Stats"
        case .osd: "OSD"
        case .battery: "Battery"
        case .caffeine: "Keep Awake"
        case .bluetooth: "Bluetooth"
        case .weather: "Weather"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .appSwitcher: "App Switcher"
        case .downloads: "Downloads"
        case .screenshots: "Screenshots"
        case .functionButtons: "Function Buttons"
        case .notifications: "Notifications"
        case .extensions: "Extensions"
        case .lockScreen: "Lock Screen"
        case .mirror: "Mirror"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .appearance: "eye"
        case .layout: "rectangle.3.group"
        case .media: "play.laptopcomputer"
        case .calendar: "calendar"
        case .clock: "clock"
        case .systemStats: "gauge.with.dots.needle.bottom.50percent"
        case .osd: "dial.medium.fill"
        case .battery: "battery.100.bolt"
        case .caffeine: "cup.and.saucer.fill"
        case .bluetooth: "wave.3.right.circle"
        case .weather: "cloud.sun.fill"
        case .shelf: "books.vertical"
        case .clipboard: "doc.on.clipboard"
        case .appSwitcher: "square.grid.2x2"
        case .downloads: "arrow.down.circle"
        case .screenshots: "camera.viewfinder"
        case .functionButtons: "button.programmable"
        case .notifications: "bell.badge"
        case .extensions: "puzzlepiece.extension"
        case .lockScreen: "lock.display"
        case .mirror: "camera"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .appearance:
                    Appearance()
                case .layout:
                    LayoutSettings()
                case .media:
                    Media()
                case .calendar:
                    CalendarSettings()
                case .clock:
                    ClockSettings()
                case .systemStats:
                    SystemStatsSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    Charge()
                case .caffeine:
                    CaffeineSettings()
                case .bluetooth:
                    BluetoothSettings()
                case .weather:
                    WeatherSettings()
                case .shelf:
                    Shelf()
                case .clipboard:
                    ClipboardSettings()
                case .appSwitcher:
                    AppSwitcherSettings()
                case .downloads:
                    DownloadSettings()
                case .screenshots:
                    ScreenshotSettings()
                case .functionButtons:
                    FunctionButtonSettings()
                case .notifications:
                    NotificationSettings()
                case .extensions:
                    ExtensionsSettings()
                case .lockScreen:
                    LockScreenSettings()
                case .mirror:
                    MirrorSettings()
                case .shortcuts:
                    Shortcuts()
                case .advanced:
                    Advanced()
                case .about:
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}
