// SelectionContext.swift
// OpenClip
//
// Represents the full context of a text selection event, including selected text, source application, screen coordinates, and app policy.
import Foundation
import CoreGraphics

public enum SelectionSource: Sendable {
    case selection, clipboard
}

public struct SelectionContext: Sendable {
    /// Retrieval correlation ID, carried through presentation without retaining content in logs.
    public let traceID: UInt64?
    public let text: String
    public let sourceApp: AppIdentity
    public let cursorPosition: CGPoint
    public let selectionBounds: CGRect?
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    /// True when the text came from the clipboard (shortcut triggered with no selection), not from a live selection.
    public let isClipboardFallback: Bool
    public let source: SelectionSource
    /// Whether the source selection was confirmed editable by the selection reader. Nil means the
    /// reader did not establish editability. Clipboard and OCR input are never editable selections.
    public let isEditable: Bool?
    /// Whether the current destination was confirmed to accept paste. This is destination
    /// evidence, independent of where `text` came from.
    public let pasteTargetAvailable: Bool?
    public let html: String?
    public let rtf: String?
    /// Raw pasteboard representations captured alongside the text, including app-private types.
    public let flavors: [RichPasteboardFlavor]

    public init(
        text: String,
        sourceApp: AppIdentity = AppIdentity(bundleIdentifier: "com.openclip.unknown", localizedName: "Unknown"),
        cursorPosition: CGPoint = .zero,
        selectionBounds: CGRect? = nil,
        timestamp: Date = Date(),
        appPolicy: AppPolicyContext = .default,
        isClipboardFallback: Bool = false,
        html: String? = nil,
        rtf: String? = nil,
        flavors: [RichPasteboardFlavor] = [],
        source: SelectionSource? = nil,
        isEditable: Bool? = nil,
        pasteTargetAvailable: Bool? = nil,
        traceID: UInt64? = nil
    ) {
        self.traceID = traceID
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.selectionBounds = selectionBounds
        self.timestamp = timestamp
        self.appPolicy = appPolicy
        self.source = source ?? (isClipboardFallback ? .clipboard : .selection)
        self.isClipboardFallback = self.source == .clipboard
        self.isEditable = self.source == .selection ? isEditable : false
        self.pasteTargetAvailable = pasteTargetAvailable
        self.html = html
        self.rtf = rtf
        self.flavors = flavors
    }

    public func with(cursorPosition: CGPoint) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: cursorPosition,
            selectionBounds: selectionBounds,
            timestamp: timestamp,
            appPolicy: appPolicy,
            isClipboardFallback: isClipboardFallback,
            html: html,
            rtf: rtf,
            flavors: flavors,
            source: source,
            isEditable: isEditable,
            pasteTargetAvailable: pasteTargetAvailable,
            traceID: traceID
        )
    }

    public func with(isEditable: Bool? = nil, pasteTargetAvailable: Bool? = nil) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: cursorPosition,
            selectionBounds: selectionBounds,
            timestamp: timestamp,
            appPolicy: appPolicy,
            isClipboardFallback: isClipboardFallback,
            html: html,
            rtf: rtf,
            flavors: flavors,
            source: source,
            isEditable: self.isEditable ?? isEditable,
            pasteTargetAvailable: pasteTargetAvailable ?? self.pasteTargetAvailable,
            traceID: traceID
        )
    }
}
