// PopupWindowController+PaletteSource.swift
// OpenClip
//
// Fork: the palette reads both the selection and the clipboard and can switch between them
// (footer switch or Tab). The session context is fixed when the popup shows, so switching
// re-shows the palette on the other source — actions, their availability (Copy/Cut need a live
// selection) and inline results all follow the new text — carrying the typed query over.
import Core

extension PopupWindowController {
    /// Opens the palette on `context` and remembers `alternate`, the other text source, if it
    /// was read too.
    func showPalette(for context: SelectionContext, alternate: SelectionContext?, pasteAvailable: Bool?) {
        paletteAlternateContext = alternate
        modeStore.paletteHasAlternateSource = alternate != nil
        modeStore.paletteSeedQuery = ""
        show(for: context, pasteAvailable: pasteAvailable, initialMode: .search)
    }

    /// Switches the open palette to its other text source. Returns false when there is none.
    @discardableResult
    func switchPaletteSource(keeping query: String) -> Bool {
        guard modeStore.mode == .search,
              let alternate = paletteAlternateContext,
              let current = currentActionContext?.selection else { return false }
        paletteAlternateContext = current
        modeStore.paletteSeedQuery = query
        defer { modeStore.paletteSeedQuery = "" }
        // The paste probe answered for the target app, not the text, so it holds for both sources.
        show(for: alternate, pasteAvailable: modeStore.canPaste, initialMode: .search)
        return true
    }
}
