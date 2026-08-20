//
//  AudioOutputPickerView.swift
//  boringNotch
//
//  F-21: the output-picker popover, opened from a slot button in the player
//  row. Two sections: CoreAudio devices (enumerable, switchable directly)
//  and AirPlay (not — `AVRoutePickerView` is the system's own picker, since
//  there's no public API to enumerate or select AirPlay targets ourselves).
//

import AVKit
import SwiftUI

struct AudioOutputPickerView: View {
    @ObservedObject private var audioOutput = AudioOutputManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("audio_output_title", comment: "Audio output picker title"))
                .font(.headline)
                .padding(12)

            Divider()

            if audioOutput.availableDevices.isEmpty {
                Text(NSLocalizedString("audio_output_none", comment: "No output devices found"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                VStack(spacing: 2) {
                    ForEach(audioOutput.availableDevices) { device in
                        Button {
                            audioOutput.selectDevice(device)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .opacity(device.id == audioOutput.currentDeviceID ? 1 : 0)
                                    .frame(width: 14)
                                Text(device.name)
                                    .font(.callout)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            HStack {
                Text(NSLocalizedString("audio_output_airplay", comment: "AirPlay section label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                AirPlayRouteButton()
                    .frame(width: 20, height: 20)
            }
            .padding(10)
        }
        .frame(width: 240)
        .onAppear { audioOutput.refresh() }
    }
}

/// Thin `NSViewRepresentable` around the system AirPlay picker — AirPlay
/// targets aren't publicly enumerable, so this is the honest way in rather
/// than pretending to list them ourselves.
private struct AirPlayRouteButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
