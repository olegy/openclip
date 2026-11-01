// SettingsSegmentedControl.swift
// OpenClip
//
// A segmented control drawn in SwiftUI. The native `Picker(.segmented)` is an NSSegmentedControl,
// which re-fits and animates its segment widths whenever its host re-renders; on the action
// editor every edit republishes the action list, so the controls visibly stretched and
// occasionally overflowed their row. Segments here have a width fixed by the layout instead.

import SwiftUI

struct SettingsSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    let accessibilityLabel: LocalizedStringKey

    private let trackShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    // Like the native control, no divider touches the selected segment.
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 1, height: 12)
                        .opacity(option.value == selection || options[index - 1].value == selection ? 0 : 1)
                }
                segment(option)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(trackShape.fill(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Text(option.title)
            .font(.system(size: 13))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = option.value }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
