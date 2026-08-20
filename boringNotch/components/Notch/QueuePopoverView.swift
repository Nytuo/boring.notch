//
//  QueuePopoverView.swift
//  boringNotch
//
//  F-20: the "Up Next" popover, opened from a slot button in the player row.
//

import SwiftUI

struct QueuePopoverView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var items: [QueueItem]?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("queue_title", comment: "Up Next popover title"))
                .font(.headline)
                .padding(12)

            Divider()

            content
        }
        .frame(width: 260, height: 300)
        .task {
            items = await musicManager.queue()
            isLoading = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let items, !items.isEmpty {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            musicManager.playQueueItem(at: index)
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let artist = item.artist, !artist.isEmpty {
                                        Text(artist)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("queue_empty", comment: "No upcoming tracks available"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
