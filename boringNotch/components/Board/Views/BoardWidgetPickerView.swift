//
//  BoardWidgetPickerView.swift
//  boringNotch
//
//  F-11: the "+" sheet — every widget from an enabled extension that isn't
//  already on this screen's board.
//

import SwiftUI

struct BoardWidgetPickerView: View {
    let availableWidgets: [BoardWidgetDescriptor]
    let placedWidgetIDs: Set<String>
    let onAdd: (BoardWidgetDescriptor) -> Void
    let onDone: () -> Void

    private var addable: [BoardWidgetDescriptor] {
        availableWidgets.filter { !placedWidgetIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("board_add_widget_title", comment: "Title of the add-widget sheet"))
                    .font(.headline)
                Spacer()
                Button(NSLocalizedString("board_done", comment: "Close the add-widget sheet")) {
                    onDone()
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            if addable.isEmpty {
                Text(NSLocalizedString("board_no_more_widgets", comment: "Shown when every available widget is already on the board"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(addable) { widget in
                            Button {
                                onAdd(widget)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: widget.iconName)
                                        .foregroundStyle(Color.effectiveAccent)
                                        .frame(width: 20)
                                    Text(widget.title)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 320, height: 360)
    }
}
