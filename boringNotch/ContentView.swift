//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var lockScreenState = LockScreenState.shared
    @ObservedObject var caffeineManager = CaffeineManager.shared
    @ObservedObject var voiceRecorderManager = VoiceRecorderManager.shared
    @ObservedObject var clockManager = ClockManager.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var systemStats = SystemStatsManager.shared
    @ObservedObject var screenshotManager = ScreenshotManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero
    @State private var horizontalMediaGestureTriggered = false
    @State private var horizontalMediaGestureFeedback: CGFloat = .zero
    @State private var isHoveringMusicArea = false

    @State private var haptics: Bool = false

    // F-04: the window's origin and the mouse's screen position at the start
    // of the current Option-drag, captured once per drag so
    // `floatingRepositionGesture` can compute an absolute new origin each
    // event instead of accumulating per-event deltas (see that property's
    // doc comment for why the accumulated-delta approach drifted).
    @State private var floatingDragOrigin: NSPoint?
    @State private var floatingDragStartMouse: NSPoint?

    @Namespace var albumArtNamespace

    @Default(.showNotHumanFace) var showNotHumanFace
    // Read as preferences rather than through `Defaults[…]` so toggling them
    // redraws the closed notch straight away.
    @Default(.clockEnabled) var clockEnabled
    @Default(.clockShowOnClosedNotch) var clockShowOnClosedNotch

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    // MARK: - Corner Radius Scaling
    private var cornerRadiusScaleFactor: CGFloat? {
        guard Defaults[.cornerRadiusScaling] else { return nil }
        let effectiveHeight = displayClosedNotchHeight
        guard effectiveHeight > 0 else { return nil }
        return effectiveHeight / 38.0
    }
    
    private var topCornerRadius: CGFloat {
        // If the notch is open, return the opened radius.
        if vm.notchState == .open {
            return cornerRadiusInsets.opened.top
        }

        // For the closed notch, scale if enabled
        let baseClosedTop = cornerRadiusInsets.closed.top
        guard let scaleFactor = cornerRadiusScaleFactor else {
            return displayClosedNotchHeight > 0 ? baseClosedTop : 0
        }
        return max(0, baseClosedTop * scaleFactor)
    }

    // F-04: a notchless display has no bezel for a square-topped cutout to
    // blend into, so it gets a fully-rounded floating pill instead. Every
    // other call site (hover, drag-and-drop, tabs) is unchanged — only the
    // shape differs, per `Style.floating` never being read anywhere else.
    private var currentNotchShape: AnyShape {
        // Scale bottom corner radius for closed notch shape when scaling is enabled.
        let baseClosedBottom = cornerRadiusInsets.closed.bottom
        let bottomCorner: CGFloat

        if vm.notchState == .open {
            bottomCorner = cornerRadiusInsets.opened.bottom
        } else if let scaleFactor = cornerRadiusScaleFactor {
            bottomCorner = max(0, baseClosedBottom * scaleFactor)
        } else {
            bottomCorner = displayClosedNotchHeight > 0 ? baseClosedBottom : 0
        }

        guard vm.hasNotch else {
            return AnyShape(IslandShape(cornerRadius: max(topCornerRadius, bottomCorner)))
        }

        return AnyShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCorner
        ))
    }

    /// F-04: Option-drag repositions the floating pill anywhere on a
    /// notchless display, rather than only through the settings sliders.
    ///
    /// This moves the actual `NSWindow`, not a SwiftUI offset — the window is
    /// a small fixed-size canvas near the top of the screen, and a content
    /// offset can only slide the pill around *inside* that canvas. Past its
    /// edge the pill would be pushed outside the window's own bounds and
    /// clipped to invisibility despite the stored offset still "existing",
    /// which is how it previously got lost. Clamping to `screen.frame` here
    /// guarantees the window can never end up somewhere it can't be dragged
    /// back from.
    ///
    /// Gated on Option so an ordinary drag — dropping a file onto the shelf,
    /// or a media gesture — is never mistaken for a reposition; on a notched
    /// display it does nothing, since there is nothing to reposition.
    ///
    /// Deliberately ignores the gesture's own `value.translation`: that is
    /// measured relative to this view's window, which is the very thing being
    /// moved — as the window chases the cursor, the view-relative distance
    /// between them stops reflecting how far the mouse actually moved, so the
    /// window either drifts (over-corrects) or stutters (under-corrects).
    /// `NSEvent.mouseLocation` is screen-absolute and has no such feedback
    /// loop, so positions are computed as start-of-drag-plus-total-mouse-delta
    /// rather than accumulated per-event deltas.
    private var floatingRepositionGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                guard !vm.hasNotch, NSEvent.modifierFlags.contains(.option),
                      let window = vm.hostWindow, let screen = window.screen
                else { return }

                if floatingDragOrigin == nil {
                    floatingDragOrigin = window.frame.origin
                    floatingDragStartMouse = NSEvent.mouseLocation
                }
                guard let startOrigin = floatingDragOrigin, let startMouse = floatingDragStartMouse else { return }

                let currentMouse = NSEvent.mouseLocation
                let newOrigin = NSPoint(
                    x: startOrigin.x + (currentMouse.x - startMouse.x),
                    y: startOrigin.y + (currentMouse.y - startMouse.y)
                )
                window.setFrameOrigin(clampedOrigin(newOrigin, size: window.frame.size, in: screen.frame))
            }
            .onEnded { _ in
                floatingDragOrigin = nil
                floatingDragStartMouse = nil
                guard !vm.hasNotch, let window = vm.hostWindow, let screen = window.screen else { return }

                let screenFrame = screen.frame
                let defaultOrigin = NSPoint(
                    x: screenFrame.origin.x + screenFrame.width / 2 - window.frame.width / 2,
                    y: screenFrame.origin.y + screenFrame.height - window.frame.height
                )
                // Persisted as an offset from the default centered/top spot,
                // matching what the settings sliders read and write.
                Defaults[.floatingNotchHorizontalOffset] = window.frame.origin.x - defaultOrigin.x
                Defaults[.floatingNotchTopGap] = defaultOrigin.y - window.frame.origin.y
            }
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, in screenFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width),
            y: min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height)
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .caffeine && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.caffeineEnabled] && Defaults[.caffeineLiveActivity]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .bluetooth && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.bluetoothLiveActivity]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .download && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.enableDownloadListener]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .notification && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.notificationsEnabled] && Defaults[.notificationsLiveActivity]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .screenshot && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.screenshotCatcherEnabled]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .vpn && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.vpnStatusEnabled] && Defaults[.vpnStatusLiveActivity]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .meeting && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.meetingIndicatorEnabled]
        {
            chinWidth = liveActivityWidth
        } else if coordinator.expandingView.type == .agentProgress && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.agentProgressEnabled]
        {
            chinWidth = liveActivityWidth
        } else if voiceRecorderManager.isRecording && vm.notchState == .closed && Defaults[.voiceRecorderEnabled] {
            chinWidth = liveActivityWidth
        } else if lockScreenState.isLocked && Defaults[.lockScreenWidgetsEnabled]
            && Defaults[.showOnLockScreen] && vm.notchState == .closed
        {
            chinWidth = liveActivityWidth
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            let sideWidth = showsClockInMusicActivity
                ? ClockClosedIndicator.trailingWidth
                : max(0, displayClosedNotchHeight - 12)
            chinWidth += (2 * sideWidth + 20 + 2 * liveActivityEdgeMargin + 2)
        } else if showsDownloadClosedIndicator {
            chinWidth += 2 * DownloadClosedIndicator.trailingWidth
        } else if showsClockClosedIndicator {
            chinWidth += 2 * ClockClosedIndicator.trailingWidth
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && !vm.hideOnClosed
            && Defaults[.caffeineEnabled] && Defaults[.caffeineNotchCountdown]
            && caffeineManager.isActive
        {
            chinWidth += 2 * (caffeineManager.formattedRemaining == nil ? 24 : 62)
        } else if showsSystemStatsIndicator {
            chinWidth += 2 * SystemStatsClosedIndicator.sideWidth
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    /// Height of the opened panel, with room added for the downloads strip
    /// while it is showing — otherwise it would eat into the tab's own space.
    private var openPanelHeight: CGFloat {
        vm.notchSize.height
            + (showsDownloadOpenBar ? DownloadOpenNotchBar.height : 0)
            + (showsScreenshotOpenBar ? ScreenshotOpenNotchBar.height : 0)
    }

    private var showsDownloadOpenBar: Bool {
        vm.notchState == .open && DownloadClosedIndicator.isActive
    }

    /// The screenshot preview only appears while there is a fresh capture to
    /// act on; it clears itself after that.
    private var showsScreenshotOpenBar: Bool {
        vm.notchState == .open && Defaults[.screenshotCatcherEnabled] && screenshotManager.latest != nil
    }

    /// A download in flight sits on the closed notch until it finishes, rather
    /// than only flashing a banner as it starts. It outranks the clock and Keep
    /// Awake readings: it is the one that ends on its own.
    private var showsDownloadClosedIndicator: Bool {
        !coordinator.expandingView.show && vm.notchState == .closed
            && !musicManager.isPlaying && musicManager.isPlayerIdle && !vm.hideOnClosed
            && DownloadClosedIndicator.isActive
    }

    /// System load is the lowest-priority thing the closed notch can show: it
    /// is always true, so anything with an actual event behind it wins.
    private var showsSystemStatsIndicator: Bool {
        !coordinator.expandingView.show && vm.notchState == .closed
            && !musicManager.isPlaying && musicManager.isPlayerIdle && !vm.hideOnClosed
            && SystemStatsClosedIndicator.isActive
    }

    /// A running countdown or stopwatch takes the closed notch when there is no
    /// live activity or playing music competing for it — the same slot, and the
    /// same conditions, as the Keep Awake countdown, which it outranks.
    ///
    /// While music holds that slot the reading is not dropped: it takes the
    /// spectrum's place instead, see `showsClockInMusicActivity`.
    private var showsClockClosedIndicator: Bool {
        !coordinator.expandingView.show && vm.notchState == .closed
            && !musicManager.isPlaying && musicManager.isPlayerIdle && !vm.hideOnClosed
            && ClockClosedIndicator.isActive
    }

    /// The music live activity gives up its spectrum to a running timer or
    /// stopwatch: a countdown is worth more than a decoration, and this way
    /// neither the artwork nor the reading has to be dropped.
    private var showsClockInMusicActivity: Bool {
        ClockClosedIndicator.isActive
    }

    // If the closed notch height is 0 (any display/setting), display a 10pt nearly-invisible notch
    // instead of fully hiding it. This preserves layout while avoiding visual artifacts.
    private var isNotchHeightZero: Bool { vm.effectiveClosedNotchHeight == 0 }

    private var displayClosedNotchHeight: CGFloat { isNotchHeightZero ? 10 : vm.effectiveClosedNotchHeight }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                          .overlay(alignment: .top) {
                              displayClosedNotchHeight.isZero && vm.notchState == .closed ? nil
                        : Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    // Removed conditional bottom padding when using custom 0 notch to keep layout stable
                    .opacity((isNotchHeightZero && vm.notchState == .closed) ? 0.01 : 1)
                
                mainLayout
                    // Fixed-height tabs (player, shelf, clock) keep their
                    // envelope so their controls do not jump about. Top-aligned
                    // so that if a tab's content ever outgrows this height
                    // regardless, the overflow spills below the panel instead
                    // of both ways — pushing the top off the screen, which is
                    // otherwise invisible and unrecoverable since the window
                    // is already pinned to the screen's top edge.
                    .frame(
                        height: (vm.notchState == .open && !coordinator.currentView.hugsContent)
                            ? openPanelHeight : nil,
                        alignment: .top
                    )
                    // Content-hugging tabs get no height frame at all,
                    // deliberately: a frame with a `maxHeight` takes the whole
                    // height it is offered rather than shrinking to its child,
                    // so the panel — and with it the hover area — stayed the
                    // size of the envelope however little was in it. Those
                    // views size themselves against `openSize`, so leaving the
                    // panel to its content makes it exactly as tall as what it
                    // is showing.
                    .conditionalModifier(true) { view in
                        return view
                            .animation(vm.notchState == .open ? StandardAnimations.open : StandardAnimations.close, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(floatingRepositionGesture)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.enableHorizontalMediaGestures] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .left) { translation, phase in
                                handleNextTrackGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handlePreviousTrackGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: coordinator.currentView) { _, newView in
                        // Tabs can request different envelopes, so resize when
                        // switching between them with the notch already open.
                        guard vm.notchState == .open else { return }
                        withAnimation(StandardAnimations.open) {
                            vm.notchSize = newView.openSize
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        // An exact height, not a ceiling: the root has to be the window's own
        // height for the panel to land against its top edge. Sized to its
        // content instead, the root sits at the window's bottom-left origin and
        // the panel hangs below the menu bar by whatever height it is missing —
        // worse the taller the window. `maxHeight` does not fix that, because a
        // hosting view that sizes to fit never proposes the full height for an
        // `.infinity` frame to take up.
        .frame(maxWidth: windowSize.width)
        .frame(height: windowSize.height, alignment: .top)
        .ignoresSafeArea(.all)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if Defaults[.boringShelf] && vm.notchState == .closed {
                    if doOpen() {
                        coordinator.currentView = .shelf
                    }
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    maxAdapterWatts: batteryModel.maxAdapterWatts,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: displayClosedNotchHeight, alignment: .center)
                      } else if coordinator.expandingView.type == .caffeine && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.caffeineEnabled] && Defaults[.caffeineLiveActivity]
                      {
                          CaffeineLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .bluetooth && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.bluetoothLiveActivity]
                      {
                          BluetoothLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .download && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.enableDownloadListener]
                      {
                          DownloadLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .notification && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.notificationsEnabled] && Defaults[.notificationsLiveActivity]
                      {
                          NotificationLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .screenshot && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.screenshotCatcherEnabled]
                      {
                          ScreenshotLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .vpn && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.vpnStatusEnabled] && Defaults[.vpnStatusLiveActivity]
                      {
                          VPNLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .meeting && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.meetingIndicatorEnabled]
                      {
                          MeetingLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.expandingView.type == .agentProgress && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.agentProgressEnabled]
                      {
                          AgentProgressLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if voiceRecorderManager.isRecording && vm.notchState == .closed && Defaults[.voiceRecorderEnabled] {
                          VoiceRecorderLiveActivity(closedNotchHeight: displayClosedNotchHeight)
                      } else if coordinator.shouldShowSneakPeek(on: vm.screenUUID) && Defaults[.inlineOSD] && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && vm.notchState == .closed {
                          InlineOSD(
                              type: coordinator.binding(for: vm.screenUUID).type,
                              value: coordinator.binding(for: vm.screenUUID).value,
                              icon: coordinator.binding(for: vm.screenUUID).icon,
                              accent: coordinator.binding(for: vm.screenUUID).accent,
                              hoverAnimation: $isHovering,
                              gestureProgress: $gestureProgress
                          )
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if lockScreenState.isLocked && Defaults[.lockScreenWidgetsEnabled]
                        && Defaults[.showOnLockScreen] && vm.notchState == .closed {
                          LockScreenWidgetBar(closedNotchHeight: displayClosedNotchHeight)
                      } else if showsDownloadClosedIndicator {
                          DownloadClosedIndicator(closedNotchHeight: displayClosedNotchHeight)
                      } else if showsClockClosedIndicator {
                          ClockClosedIndicator(closedNotchHeight: displayClosedNotchHeight)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed
                        && (!musicManager.isPlaying && musicManager.isPlayerIdle) && !vm.hideOnClosed
                        && Defaults[.caffeineEnabled] && Defaults[.caffeineNotchCountdown]
                        && CaffeineManager.shared.isActive {
                          CaffeineClosedIndicator(closedNotchHeight: displayClosedNotchHeight)
                      } else if showsSystemStatsIndicator {
                          SystemStatsClosedIndicator(closedNotchHeight: displayClosedNotchHeight)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, displayClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       }
                        // New case to enable compact notch on external displays
                        else if !vm.hasNotch {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: 11) // idle notch height is halved on non notch display
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: displayClosedNotchHeight)
                       }

                      if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                          if (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && !Defaults[.inlineOSD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: coordinator.binding(for: vm.screenUUID).type,
                                  value: coordinator.binding(for: vm.screenUUID).value,
                                  icon: coordinator.binding(for: vm.screenUUID).icon,
                                  accent: coordinator.binding(for: vm.screenUUID).accent,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeekState(for: vm.screenUUID).type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeekState(for: vm.screenUUID).type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(musicManager.songTitle + " - " + musicManager.artistName,  color: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, delayDuration: 1.0, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(1)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .player:
                        NotchPlayerView(
                            albumArtNamespace: albumArtNamespace,
                            horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                            isHoveringMusicArea: $isHoveringMusicArea
                        )
                    case .shelf:
                        ShelfView()
                    case .calendar:
                        // Spans the tab's whole envelope rather than the old
                        // sidebar slot it used to occupy in the home view, so
                        // event titles have room to be read.
                        CalendarView()
                            .frame(width: NotchViews.calendar.contentWidth)
                            .onHover { vm.isHoveringCalendar = $0 }
                    case .weather:
                        WeatherView()
                    case .clipboard:
                        ClipboardView()
                    case .apps:
                        AppSwitcherView()
                    case .clock:
                        ClockView()
                    case .systemStats:
                        SystemStatsView()
                    case .bluetooth:
                        BluetoothDevicesView()
                    case .board:
                        BoardView()
                    case .launcher:
                        LauncherView()
                    }
                }
                // No explicit width: the panel hugs whatever the current view
                // needs, up to the envelope. Each view is responsible for
                // having an intrinsic width rather than expanding to fill.
                // Spans the panel and stays centred on it. The enclosing stack
                // is leading-aligned, so a view narrower than the panel would
                // otherwise hug the left edge and read as a notch that has
                // drifted off centre.
                .frame(maxWidth: coordinator.currentView.contentWidth)
                .frame(maxWidth: .infinity)
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)

                // Downloads sit under whichever tab is open: they are not tied
                // to one destination, and they end on their own. The panel is
                // grown by `DownloadOpenNotchBar.height` to fit this.
                if showsScreenshotOpenBar {
                    ScreenshotOpenNotchBar()
                        .frame(maxWidth: coordinator.currentView.contentWidth)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(1)
                }

                if showsDownloadOpenBar {
                    DownloadOpenNotchBar()
                        .frame(maxWidth: coordinator.currentView.contentWidth)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(1)
                }
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 20)
            let faceScale = min(1.0, displayClosedNotchHeight / 30.0)
            MinimalFaceFeatures(height: 24.0 * faceScale, width: 30.0 * faceScale)
        }.frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack(spacing: 0) {
            // Closed-mode album art: scale padding and corner radius according to cornerRadiusScaleFactor
            let baseArtSize = displayClosedNotchHeight - 12
            let scaledArtSize: CGFloat = {
                if let scale = cornerRadiusScaleFactor {
                    return displayClosedNotchHeight - 12 * scale
                }
                return baseArtSize
            }()

            let closedCornerRadius: CGFloat = {
                let base = MusicPlayerImageSizes.cornerRadiusInset.closed
                if let scale = cornerRadiusScaleFactor {
                    return max(0, base * scale)
                }
                return base
            }()

            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: closedCornerRadius)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: scaledArtSize,
                    height: scaledArtSize
                )
                // Both sides have to match in width or the opaque spacer stops
                // lining up with the physical notch.
                .frame(
                    width: showsClockInMusicActivity ? ClockClosedIndicator.trailingWidth : scaledArtSize,
                    alignment: .leading
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                musicManager.songTitle,
                                color: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                delayDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width - 4 + (2 * liveActivityEdgeMargin)
                )

            HStack {
                if showsClockInMusicActivity {
                    ClockClosedReading()
                } else {
                    AudioSpectrumView(
                        isPlaying: musicManager.isPlaying,
                        tintColor: Defaults[.coloredSpectrogram]
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.5)
                        : Color.gray
                    )
                    .frame(width: 18, height: 12)
                }
            }
            .frame(
                width: showsClockInMusicActivity
                    ? ClockClosedIndicator.trailingWidth
                    : max(
                        0,
                        displayClosedNotchHeight - 12
                            + gestureProgress / 2
                    ),
                height: max(
                    0,
                    displayClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    @discardableResult
    private func doOpen() -> Bool {
        var didOpen = false
        withAnimation(animationSpring) {
            didOpen = vm.open()
        }
        return didOpen
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.shouldShowSneakPeek(on: vm.screenUUID),
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.shouldShowSneakPeek(on: self.vm.screenUUID) else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func handleNextTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: -1) {
            musicManager.nextTrack()
        }
    }

    private func handlePreviousTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: 1) {
            musicManager.previousTrack()
        }
    }

    private func handleHorizontalMediaGesture(
        translation: CGFloat,
        phase: NSEvent.Phase,
        feedback: CGFloat,
        action: () -> Void
    ) {
        guard isHorizontalMediaGestureContext else {
            resetHorizontalMediaGesture()
            return
        }
        guard phase != .ended else {
            resetHorizontalMediaGesture()
            return
        }
        guard !horizontalMediaGestureTriggered else { return }
        guard translation > Defaults[.gestureSensitivity] else { return }

        horizontalMediaGestureTriggered = true
        triggerHorizontalMediaFeedback(feedback)
        action()

        if Defaults[.enableHaptics] {
            haptics.toggle()
        }
    }

    private func resetHorizontalMediaGesture() {
        horizontalMediaGestureTriggered = false
    }

    private func triggerHorizontalMediaFeedback(_ feedback: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.62)) {
            horizontalMediaGestureFeedback = feedback
            if vm.notchState == .closed {
                gestureProgress = 2
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(animationSpring) {
                horizontalMediaGestureFeedback = .zero
                if vm.notchState == .closed {
                    gestureProgress = .zero
                }
            }
        }
    }

    private var isHorizontalMediaGestureContext: Bool {
        switch vm.notchState {
        case .closed:
            guard !vm.hideOnClosed else { return false }

            if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                return coordinator.sneakPeekState(for: vm.screenUUID).type == .music
            }

            guard !coordinator.expandingView.show || coordinator.expandingView.type == .music else {
                return false
            }

            return coordinator.musicLiveActivityEnabled && (musicManager.isPlaying || !musicManager.isPlayerIdle)

        case .open:
            return coordinator.currentView == .player && !musicManager.isPlayerIdle && isHoveringMusicArea
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
