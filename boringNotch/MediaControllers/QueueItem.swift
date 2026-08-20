//
//  QueueItem.swift
//  boringNotch
//
//  F-20: one upcoming track, provider-agnostic. Deliberately thin — just
//  enough to render a list row; providers that can support more (artwork,
//  duration) can add fields later without this needing to change shape.
//

import Foundation

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String?
}
