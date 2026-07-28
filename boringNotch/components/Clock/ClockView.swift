//
//  ClockView.swift
//  boringNotch
//
//  Clock, countdown timer and stopwatch, shown as a notch tab.
//

import Defaults
import SwiftUI

struct ClockView: View {
    @ObservedObject private var clock = ClockManager.shared
    @Default(.clockMode) private var mode

    private var contentWidth: CGFloat { NotchViews.clock.contentWidth }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            modePicker

            Divider()
                .overlay(Color.white.opacity(0.12))

            Group {
                switch mode {
                case .clock: ClockFaceView()
                case .timer: TimerFaceView()
                case .stopwatch: StopwatchFaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    /// Vertical rail rather than a segmented control across the top: it costs
    /// width the panel has to spare instead of height it does not, and leaves
    /// the whole right side to the active face.
    private var modePicker: some View {
        VStack(spacing: 6) {
            ForEach(ClockMode.allCases) { item in
                let selected = mode == item
                Button {
                    withAnimation(.smooth(duration: 0.2)) { mode = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 13))
                        Text(item.label)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? .white : .gray)
                    .frame(width: 62, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color(nsColor: .secondarySystemFill) : .clear)
                    )
                    // Running work keeps its badge while another face is shown,
                    // so a countdown left running is never invisible.
                    .overlay(alignment: .topTrailing) {
                        if runningBadge(for: item) {
                            Circle()
                                .fill(Color.effectiveAccent)
                                .frame(width: 5, height: 5)
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func runningBadge(for item: ClockMode) -> Bool {
        switch item {
        case .clock: return false
        case .timer: return clock.isTimerActive
        case .stopwatch: return clock.isStopwatchActive
        }
    }
}

// MARK: - Closed notch

/// Countdown or stopwatch reading beside the closed notch, so a running timer
/// is visible without opening anything.
///
/// Laid out symmetrically about the notch cutout like the other closed-notch
/// indicators: the notch is opaque, so the spacer standing in for it only lines
/// up with the hardware when the content either side of it balances.
struct ClockClosedIndicator: View {
    @EnvironmentObject var vm: BoringViewModel

    let closedNotchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.trailingWidth, height: closedNotchHeight)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 2 * liveActivityEdgeMargin)

            ClockClosedReading()
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }

    /// Wide enough for `h:mm:ss`, so the notch does not resize as a long
    /// countdown crosses the hour.
    static let trailingWidth: CGFloat = 72

    /// Whether there is a reading to show at all. Drives both this indicator
    /// and the slot it borrows from the music live activity.
    @MainActor
    static var isActive: Bool {
        guard Defaults[.clockEnabled], Defaults[.clockShowOnClosedNotch] else { return false }
        return ClockManager.shared.isTimerRunning || ClockManager.shared.isStopwatchRunning
    }
}

/// The reading itself: icon plus time, sized to `ClockClosedIndicator.trailingWidth`.
struct ClockClosedReading: View {
    @ObservedObject private var clock = ClockManager.shared

    /// A running countdown outranks the stopwatch: it is the one with a
    /// deadline attached.
    private var showsTimer: Bool { clock.isTimerRunning }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 4) {
                Image(systemName: showsTimer ? "timer" : "stopwatch")
                    .foregroundStyle(Color.effectiveAccent)
                    .font(.system(size: 11))
                // A countdown rounds up (4.2s left still reads 0:05); elapsed
                // time rounds down, the way a stopwatch counts.
                Text(ClockManager.formatDuration(
                    showsTimer ? clock.timerRemaining : clock.stopwatchElapsed.rounded(.down)
                ))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: ClockClosedIndicator.trailingWidth, alignment: .leading)
            .padding(.leading, 4)
        }
    }
}

// MARK: - Clock

private struct ClockFaceView: View {
    @Default(.clockShowSeconds) private var showSeconds
    @Default(.clockShowAnalogFace) private var showAnalogFace
    @Default(.clockFollowSystemFormat) private var followSystemFormat
    @Default(.clockUse24Hour) private var use24Hour

    var body: some View {
        TimelineView(.periodic(from: .now, by: showSeconds ? 1 : 15)) { context in
            let now = context.date

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeString(now))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)

                    Text(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showAnalogFace {
                    AnalogClockFace(date: now, showSeconds: showSeconds)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        if followSystemFormat {
            // "j" resolves to whichever of 12/24-hour the locale uses.
            formatter.setLocalizedDateFormatFromTemplate(showSeconds ? "jmmss" : "jmm")
        } else if use24Hour {
            formatter.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            formatter.dateFormat = showSeconds ? "h:mm:ss a" : "h:mm a"
        }
        return formatter.string(from: date)
    }
}

/// Simple analog dial. Gives the tab something to fill the panel with, and is
/// quicker to read at a glance than digits.
private struct AnalogClockFace: View {
    let date: Date
    let showSeconds: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let second = Double(components.second ?? 0)
            let minute = Double(components.minute ?? 0) + second / 60
            let hour = Double((components.hour ?? 0) % 12) + minute / 60

            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5)

                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(Color.white.opacity(tick % 3 == 0 ? 0.55 : 0.25))
                        .frame(width: 1.5, height: tick % 3 == 0 ? radius * 0.16 : radius * 0.09)
                        .offset(y: -radius * 0.86)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }

                hand(length: radius * 0.5, width: 3.5, angle: hour * 30, color: .white)
                hand(length: radius * 0.74, width: 2.5, angle: minute * 6, color: .white.opacity(0.85))
                if showSeconds {
                    hand(length: radius * 0.82, width: 1.2, angle: second * 6, color: .effectiveAccent)
                }

                Circle()
                    .fill(Color.effectiveAccent)
                    .frame(width: 5, height: 5)
            }
            .frame(width: size, height: size)
            .position(center)
        }
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Timer

private struct TimerFaceView: View {
    @ObservedObject private var clock = ClockManager.shared

    private static let presets: [Int] = [1, 3, 5, 10, 25]

    var body: some View {
        TimelineView(.periodic(from: .now, by: clock.isTimerRunning ? 0.2 : 60)) { _ in
            HStack(spacing: 16) {
                countdownRing

                VStack(alignment: .leading, spacing: 8) {
                    presetRow
                    adjustRow
                    controlRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)

            Circle()
                .trim(from: 0, to: clock.timerProgress)
                .stroke(
                    clock.timerDidFinish ? Color.orange : Color.effectiveAccent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(ClockManager.formatDuration(clock.timerRemaining))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(statusLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }
            .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: .infinity)
    }

    private var statusLabel: String {
        if clock.timerDidFinish { return NSLocalizedString("clock_timer_done", comment: "Countdown reached zero") }
        if clock.isTimerRunning { return NSLocalizedString("clock_timer_running", comment: "Countdown is running") }
        if clock.timerPausedRemaining != nil { return NSLocalizedString("clock_timer_paused", comment: "Countdown is paused") }
        return NSLocalizedString("clock_timer_ready", comment: "Countdown is set but not started")
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets, id: \.self) { minutes in
                Button {
                    clock.setTimerDuration(TimeInterval(minutes * 60))
                } label: {
                    Text("\(minutes)m")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(clock.isTimerRunning)
                .opacity(clock.isTimerRunning ? 0.4 : 1)
            }
        }
    }

    private var adjustRow: some View {
        HStack(spacing: 6) {
            adjustButton(label: "−1m", delta: -60)
            adjustButton(label: "+1m", delta: 60)
            adjustButton(label: "+5m", delta: 300)
        }
    }

    private func adjustButton(label: String, delta: TimeInterval) -> some View {
        Button {
            clock.adjustTimerDuration(by: delta)
        } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Button {
                clock.toggleTimer()
            } label: {
                Label(
                    clock.isTimerRunning
                        ? NSLocalizedString("clock_pause", comment: "Pause button")
                        : NSLocalizedString("clock_start", comment: "Start button"),
                    systemImage: clock.isTimerRunning ? "pause.fill" : "play.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.effectiveAccent))
            }
            .buttonStyle(.plain)
            .disabled(clock.timerRemaining <= 0 && !clock.isTimerRunning)

            Button {
                clock.resetTimer()
            } label: {
                Label(
                    NSLocalizedString("clock_reset", comment: "Reset button"),
                    systemImage: "arrow.counterclockwise"
                )
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!clock.isTimerActive && !clock.timerDidFinish)
        }
    }
}

// MARK: - Stopwatch

private struct StopwatchFaceView: View {
    @ObservedObject private var clock = ClockManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: clock.isStopwatchRunning ? 0.03 : 60)) { _ in
                    Text(ClockManager.formatPreciseDuration(clock.stopwatchElapsed))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                HStack(spacing: 8) {
                    Button {
                        clock.toggleStopwatch()
                    } label: {
                        Label(
                            clock.isStopwatchRunning
                                ? NSLocalizedString("clock_pause", comment: "Pause button")
                                : NSLocalizedString("clock_start", comment: "Start button"),
                            systemImage: clock.isStopwatchRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.effectiveAccent))
                    }
                    .buttonStyle(.plain)

                    Button {
                        clock.recordLap()
                    } label: {
                        Label(
                            NSLocalizedString("clock_lap", comment: "Lap button"),
                            systemImage: "flag.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!clock.isStopwatchRunning)
                    .opacity(clock.isStopwatchRunning ? 1 : 0.4)

                    Button {
                        clock.resetStopwatch()
                    } label: {
                        Label(
                            NSLocalizedString("clock_reset", comment: "Reset button"),
                            systemImage: "arrow.counterclockwise"
                        )
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!clock.isStopwatchActive)
                    .opacity(clock.isStopwatchActive ? 1 : 0.4)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            lapList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Laps fill the space the stopwatch would otherwise waste, newest first.
    @ViewBuilder
    private var lapList: some View {
        if clock.laps.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "flag")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray.opacity(0.6))
                Text("No laps")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .frame(minWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(clock.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("#\(clock.laps.count - index)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.gray)
                            Spacer()
                            Text(ClockManager.formatPreciseDuration(lap))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(index == 0 ? 0.1 : 0.05))
                        )
                    }
                }
            }
            .frame(minWidth: 150, maxWidth: .infinity)
        }
    }
}
