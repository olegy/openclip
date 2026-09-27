// PaletteSourceFooter.swift
// OpenClip
//
// Fork: the leading side of the palette footer. Shows where the palette's text comes from — a
// segmented selection/clipboard switch, styled like the Color Mode picker in Appearance — and
// the start of that text on one line. Only the sources that were read get a segment; with no
// text at all it says so (D005). Replaces upstream's action count (`ForkBehavior.paletteSourceFooter`).
import SwiftUI
import Core

struct PaletteSourceFooter: View {
    enum Source: Hashable {
        case selection
        case clipboard
    }

    /// The palette's current input; its `isClipboardFallback` says which source is active.
    let selection: SelectionContext
    /// Whether the other source was read too, so both segments show.
    let hasAlternate: Bool
    let effectiveTheme: String
    let onSwitch: @MainActor () -> Void

    private var active: Source { selection.isClipboardFallback ? .clipboard : .selection }

    private var sources: [Source] {
        hasAlternate ? [.selection, .clipboard] : [active]
    }

    var body: some View {
        HStack(spacing: 8) {
            if selection.text.isEmpty {
                Text("No text")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme).opacity(0.7))
            } else {
                sourcePicker
                Text(Self.previewLine(selection.text))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme).opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(
            get: { active },
            set: { if $0 != active { onSwitch() } }
        )) {
            ForEach(sources, id: \.self) { source in
                Image(systemName: Self.symbol(for: source))
                    .help(Self.label(for: source))
                    .accessibilityLabel(Self.label(for: source))
                    .tag(source)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(Text("Text source"))
    }

    static func symbol(for source: Source) -> String {
        switch source {
        case .selection: return "character.cursor.ibeam"
        case .clipboard: return "doc.on.clipboard"
        }
    }

    static func label(for source: Source) -> String {
        switch source {
        case .selection: return String(localized: "Selection")
        case .clipboard: return String(localized: "Clipboard")
        }
    }

    /// The start of `text` on one line: whitespace runs, line breaks included, collapse to a single
    /// space. Only the head is scanned — the footer never shows more than a line of it.
    static func previewLine(_ text: String) -> String {
        text.prefix(400).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
