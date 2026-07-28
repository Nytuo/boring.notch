//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

// MARK: - File System Paths
private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

struct AppLanguage: RawRepresentable, Hashable, Identifiable, Defaults.Serializable {
    static let system = AppLanguage(rawValue: "system")

    var id: String { rawValue }
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static var allCases: [AppLanguage] {
        let languages = Bundle.main.localizations
            .filter(isSelectableLocalization)
            .map(AppLanguage.init(rawValue:))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        return [.system] + languages
    }

    var displayName: String {
        if self == .system {
            return NSLocalizedString(
                "System default",
                comment: "Language picker option: follow the system app language"
            )
        }

        let displayName = nativeLocale.localizedString(forIdentifier: rawValue) ?? rawValue
        return displayName.capitalized(with: nativeLocale)
    }

    private var nativeLocale: Locale {
        Locale(identifier: rawValue)
    }

    private static func isSelectableLocalization(_ identifier: String) -> Bool {
        guard identifier != "Base" else { return false }
        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: identifier
        ) else {
            return false
        }

        guard
            let data = try? Data(contentsOf: url),
            let strings = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String]
        else {
            return false
        }

        return strings.values.contains { !$0.isEmpty }
    }

    func applyAppleLanguagesOverride() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

// Define notification names at file scope
extension Notification.Name {
    // MARK: - Media
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
    
    // MARK: - Display
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    
    // MARK: - Shelf
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    
    // MARK: - Clock
    static let clockTimerFinished = Notification.Name("clockTimerFinished")

    // MARK: - System
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
    
    // MARK: - Sharing
    static let sharingDidFinish = Notification.Name("com.boringNotch.sharingDidFinish")
    
    // MARK: - UI
    static let accentColorChanged = Notification.Name("AccentColorChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying
    case appleMusic
    case spotify
    case youtubeMusic
    
    var id: String { self.rawValue }

    var localizedString: String {
        switch self {
        case .nowPlaying:
            return NSLocalizedString("Now Playing", comment: "")
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .youtubeMusic:
            return "YouTube Music"
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case inline
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .standard:
            return NSLocalizedString("sneak_peek_standard", comment: "Sneak Peek style: Default")
        case .inline:
            return NSLocalizedString("sneak_peek_inline", comment: "Sneak Peek style: Inline")
        }
    }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings
    case showOSD
    case none

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .openSettings:
            return NSLocalizedString("option_key_open_system_settings", comment: "Option (⌥) key behavior: Open System Settings")
        case .showOSD:
            return NSLocalizedString("option_key_show_osd", comment: "Option (⌥) key behavior: Show OSD")
        case .none:
            return NSLocalizedString("option_key_no_action", comment: "Option (⌥) key behavior: No action")
        }
    }
}

// Source/provider for OSD control (user-facing: "Source")
enum OSDControlSource: String, CaseIterable, Identifiable, Defaults.Serializable {
    case builtin
    case betterDisplay = "BetterDisplay"
    case lunar = "Lunar"

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .builtin:
            return NSLocalizedString("osd_sources_built_in", comment: "OSD Sources: Built-in")
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }
}

extension Defaults.Keys {
    // MARK: General
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableOpeningAnimation = Key<Bool>("enableOpeningAnimation", default: true)
    static let animationSpeedMultiplier = Key<Double>("animationSpeedMultiplier", default: 1.0)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let isMirrored = Key<Bool>("isMirrored", default: true)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let mirrorCameraID = Key<String?>("mirrorCameraID", default: nil)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let enableHorizontalMediaGestures = Key<Bool>("enableHorizontalMediaGestures", default: false)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let realtimeAudioWaveform = Key<Bool>("realtimeAudioWaveform", default: false)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    static let showChargingWattage = Key<Bool>("showChargingWattage", default: true)
    
    // MARK: Layout
    static let notchHeaderItems = Key<[NotchHeaderItem]>(
        "notchHeaderItems",
        default: NotchHeaderItem.defaultOrder
    )
    static let notchTabOrder = Key<[NotchTabItem]>(
        "notchTabOrder",
        default: NotchTabItem.defaultOrder
    )
    static let notchDefaultTab = Key<NotchTabItem>("notchDefaultTab", default: NotchTabItem.player)
    /// The tab the notch was last showing, so "Remember last tab" survives a
    /// relaunch and not just a close.
    static let lastOpenedTab = Key<NotchTabItem>("lastOpenedTab", default: NotchTabItem.player)

    // MARK: Lock screen
    static let lockScreenWidgetsEnabled = Key<Bool>("lockScreenWidgetsEnabled", default: false)
    static let lockScreenWidgets = Key<[LockScreenWidget]>(
        "lockScreenWidgets",
        default: LockScreenWidget.defaultSelection
    )

    // MARK: Notifications
    static let notificationsEnabled = Key<Bool>("notificationsEnabled", default: false)
    static let notificationsLiveActivity = Key<Bool>("notificationsLiveActivity", default: true)
    static let notificationsShowBody = Key<Bool>("notificationsShowBody", default: true)
    static let notificationsExcludedApps = Key<[String]>("notificationsExcludedApps", default: [])

    // MARK: Function buttons
    static let functionButtonsEnabled = Key<Bool>("functionButtonsEnabled", default: false)
    static let functionButtonsShowLabels = Key<Bool>("functionButtonsShowLabels", default: true)
    static let functionButtons = Key<[FunctionButton]>("functionButtons", default: [])

    // MARK: Clipboard history
    static let clipboardHistoryEnabled = Key<Bool>("clipboardHistoryEnabled", default: false)
    static let clipboardShowInNotch = Key<Bool>("clipboardShowInNotch", default: true)
    static let clipboardHistoryLimit = Key<Int>("clipboardHistoryLimit", default: 100)
    static let clipboardIgnoreConfidential = Key<Bool>("clipboardIgnoreConfidential", default: true)
    static let clipboardStoreImages = Key<Bool>("clipboardStoreImages", default: true)
    static let clipboardPersistHistory = Key<Bool>("clipboardPersistHistory", default: false)
    static let clipboardExcludedApps = Key<[String]>(
        "clipboardExcludedApps",
        default: ["com.agilebits.onepassword7", "com.1password.1password", "com.apple.keychainaccess"]
    )

    // MARK: App switcher
    static let appSwitcherEnabled = Key<Bool>("appSwitcherEnabled", default: false)
    static let appSwitcherShowTab = Key<Bool>("appSwitcherShowTab", default: true)
    static let appSwitcherIncludeMinimized = Key<Bool>("appSwitcherIncludeMinimized", default: true)

    // MARK: Screenshots
    static let screenshotCatcherEnabled = Key<Bool>("screenshotCatcherEnabled", default: false)
    /// Folder macOS writes screenshots to, granted once by the user.
    static let screenshotFolderBookmark = Key<Data?>("screenshotFolderBookmark", default: nil)
    static let screenshotAddToShelf = Key<Bool>("screenshotAddToShelf", default: false)
    static let screenshotPreviewSeconds = Key<Int>("screenshotPreviewSeconds", default: 30)

    // MARK: System stats
    static let systemStatsEnabled = Key<Bool>("systemStatsEnabled", default: false)
    static let systemStatsShowOnClosedNotch = Key<Bool>("systemStatsShowOnClosedNotch", default: true)
    /// Stats icon in the opened notch header, which opens the graphs.
    static let systemStatsNotchIcon = Key<Bool>("systemStatsNotchIcon", default: true)
    static let systemStatsShowCPU = Key<Bool>("systemStatsShowCPU", default: true)
    static let systemStatsShowMemory = Key<Bool>("systemStatsShowMemory", default: true)
    static let systemStatsShowNetwork = Key<Bool>("systemStatsShowNetwork", default: true)

    // MARK: Clock, timer and stopwatch
    static let clockEnabled = Key<Bool>("clockEnabled", default: true)
    static let clockShowInNotch = Key<Bool>("clockShowInNotch", default: true)
    static let clockMode = Key<ClockMode>("clockMode", default: ClockMode.clock)
    static let clockShowSeconds = Key<Bool>("clockShowSeconds", default: true)
    static let clockUse24Hour = Key<Bool>("clockUse24Hour", default: false)
    /// Follow the system's 12/24-hour setting instead of `clockUse24Hour`.
    static let clockFollowSystemFormat = Key<Bool>("clockFollowSystemFormat", default: true)
    static let clockShowAnalogFace = Key<Bool>("clockShowAnalogFace", default: true)
    static let clockDefaultTimerMinutes = Key<Int>("clockDefaultTimerMinutes", default: 5)
    /// Keeps a running countdown or stopwatch on the closed notch.
    static let clockShowOnClosedNotch = Key<Bool>("clockShowOnClosedNotch", default: true)
    /// Play a sound when a timer reaches zero.
    static let clockTimerSound = Key<Bool>("clockTimerSound", default: true)
    /// Open the notch when a timer reaches zero, so it is noticed.
    static let clockTimerOpensNotch = Key<Bool>("clockTimerOpensNotch", default: true)

    // MARK: Weather
    static let weatherEnabled = Key<Bool>("weatherEnabled", default: false)
    static let weatherLocationMode = Key<WeatherLocationMode>(
        "weatherLocationMode",
        default: WeatherLocationMode.automatic
    )
    static let weatherManualPlace = Key<WeatherPlace?>("weatherManualPlace", default: nil)
    /// Cached reverse-geocoded name for the automatic location, so a refresh
    /// does not have to hit the geocoder every time.
    static let weatherResolvedPlace = Key<WeatherPlace?>("weatherResolvedPlace", default: nil)
    static let weatherTemperatureUnit = Key<TemperatureUnit>(
        "weatherTemperatureUnit",
        default: TemperatureUnit.systemDefault
    )
    static let weatherWindSpeedUnit = Key<WindSpeedUnit>("weatherWindSpeedUnit", default: .kmh)
    static let weatherRefreshMinutes = Key<Int>("weatherRefreshMinutes", default: 30)
    static let weatherShowInNotch = Key<Bool>("weatherShowInNotch", default: true)
    static let weatherShowHourlyForecast = Key<Bool>("weatherShowHourlyForecast", default: true)
    static let weatherShowDailyForecast = Key<Bool>("weatherShowDailyForecast", default: true)

    // MARK: Bluetooth
    static let bluetoothLiveActivity = Key<Bool>("bluetoothLiveActivity", default: true)
    static let bluetoothNotifyOnConnect = Key<Bool>("bluetoothNotifyOnConnect", default: true)
    static let bluetoothNotifyOnDisconnect = Key<Bool>("bluetoothNotifyOnDisconnect", default: true)
    static let bluetoothShowBatteryLevel = Key<Bool>("bluetoothShowBatteryLevel", default: true)
    /// Accessory battery list in the opened notch header.
    static let bluetoothNotchIcon = Key<Bool>("bluetoothNotchIcon", default: true)

    // MARK: Caffeine
    static let caffeineEnabled = Key<Bool>("caffeineEnabled", default: true)
    static let caffeineDefaultDuration = Key<CaffeineDuration>(
        "caffeineDefaultDuration",
        default: CaffeineDuration.indefinite
    )
    static let caffeineAllowDisplaySleep = Key<Bool>("caffeineAllowDisplaySleep", default: false)
    static let caffeineActivateOnLaunch = Key<Bool>("caffeineActivateOnLaunch", default: false)
    /// Adds Keep Awake controls to the main Boring Notch menu bar item.
    static let caffeineShowInMenuBar = Key<Bool>("caffeineShowInMenuBar", default: true)
    /// Cup button in the opened notch header, for toggling Keep Awake there.
    static let caffeineNotchIcon = Key<Bool>("caffeineNotchIcon", default: true)
    /// Keeps the remaining time on the closed notch while a timed session runs.
    static let caffeineNotchCountdown = Key<Bool>("caffeineNotchCountdown", default: true)
    static let caffeineLiveActivity = Key<Bool>("caffeineLiveActivity", default: true)
    static let caffeineShowCountdown = Key<Bool>("caffeineShowCountdown", default: true)

    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let enableChromiumDownloads = Key<Bool>("enableChromiumDownloads", default: true)
    static let enableFirefoxDownloads = Key<Bool>("enableFirefoxDownloads", default: true)
    /// Security-scoped bookmark for the Downloads folder. The sandbox grants no
    /// access to it by default, so the user has to pick it once.
    static let downloadsFolderBookmark = Key<Data?>("downloadsFolderBookmark", default: nil)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: OSD
    static let osdReplacement = Key<Bool>("osdReplacement", default: false)
    static let inlineOSD = Key<Bool>("inlineOSD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchOSD = Key<Bool>("showOpenNotchOSD", default: true)
    static let showOpenNotchOSDPercentage = Key<Bool>("showOpenNotchOSDPercentage", default: true)
    static let showClosedNotchOSDPercentage = Key<Bool>("showClosedNotchOSDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    // Brightness/volume/keyboard source selection
    static let osdBrightnessSource = Key<OSDControlSource>("osdBrightnessSource", default: .builtin)
    static let osdVolumeSource = Key<OSDControlSource>("osdVolumeSource", default: .builtin)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    static let reverseShelfOrdering = Key<Bool>("reverseShelfOrdering", default: false)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    static let calendarWeekView = Key<Bool>("calendarWeekView", default: false)
    static let weekStartDay = Key<WeekStartDay>("weekStartDay", default: .system)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: true)
    // Normalize scroll/gesture direction so when macOS "Natural scrolling" is disabled, it doesn't invert gestures
    static let normalizeGestureDirection = Key<Bool>("normalizeGestureDirection", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
