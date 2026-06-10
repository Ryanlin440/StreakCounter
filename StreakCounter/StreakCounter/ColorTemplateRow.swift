//
//  ColorTemplateRow.swift
//  StreakCounter
//

import SwiftUI

struct ColorTemplateRow: View {

    let colors: [Color]
    let selected: Color
    var onSelect: (Color) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button {
                        onSelect(color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                )
                            if matches(color, selected) {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func matches(_ a: Color, _ b: Color) -> Bool {
        CodableColor(a) == CodableColor(b)
    }
}
