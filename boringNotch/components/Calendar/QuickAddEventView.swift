//
//  QuickAddEventView.swift
//  boringNotch
//

import SwiftUI

struct QuickAddEventView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var isPresented: Bool

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var draft: ParsedEventDraft? {
        CalendarQuickAddParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(NSLocalizedString("calendar_quickadd_placeholder", comment: "Placeholder for natural-language event entry"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit(commit)

            if let draft, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.effectiveAccent)
                        .font(.caption)
                    Text(draft.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(previewDateText(draft))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 280)
        .onAppear { isFocused = true }
    }

    private func previewDateText(_ draft: ParsedEventDraft) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: draft.start)
    }

    private func commit() {
        guard let draft else { return }
        Task {
            await calendarManager.createEvent(from: draft)
        }
        text = ""
        isPresented = false
    }
}
