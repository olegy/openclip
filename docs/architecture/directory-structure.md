# OpenClip Directory Structure

Annotated source tree. See `docs/architecture/overview.md` for the architectural (target-split)
view; this is the detailed per-file map.

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Core.swift                            # Module exports
│   ├── Log.swift                             # Single logging surface: Log enum, LogChannel, LogSink protocol, LogLevel, LogMessage (see docs/logging.md)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionCustomizationManager.swift  # User action overrides (title/icon); delegates I/O to SettingsStore
│   │   ├── ActionDelivery.swift              # Per-action delivery: secondary outcome + per-click toasts
│   │   ├── ActionIdentity.swift              # Action identification helpers (builtin, AI preset, extension package)
│   │   ├── ActionMatchInfo.swift             # Regex match context & capture payload
│   │   ├── ActionRegistry.swift              # Storage (registration order) and the palette's availability filter
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── ActionResultDelivery.swift        # Select → Probe → Toast: paste-vs-copy delivery decision (resolves (result, toast))
│   │   ├── ActionSearch.swift                # Popup mode enum + pure substring matcher for the action-search palette
│   │   ├── ActionVisibility.swift            # Pure visibility & requirement evaluation logic
│   │   ├── Builtin/                          # Core builtin actions (Calculate, Calendar, Define, Search)
│   │   │   ├── CalculateAction.swift
│   │   │   ├── CalendarAction.swift
│   │   │   ├── DefineAction.swift
│   │   │   ├── SearchAction.swift
│   │   │   └── SearchEnginePreset.swift      # Built-in search engine preset configurations
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol (preferenceIconName)
│   │   ├── ConfigurationRequest.swift        # Required-option configuration request model
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── DeliveryDecoratedAction.swift     # Pure wrapper stamping a declared ActionDelivery onto an action
│   │   ├── ExtensionActionRules.swift        # Action requirements & visibility rules evaluator
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── GroupAction.swift                 # Pure group-row action (chrome .showSubActions); perform → .none
│   │   ├── KeyPressSpec.swift                # Key-press spec ("mod+mod+key") parsed from manifest keyPress
│   │   ├── MathEvaluator.swift               # Deterministic exception-free arithmetic parser (replaces NSExpression; used by CalculateAction)
│   │   ├── MenuDecoratedAction.swift         # Sub-menu relevance decorator
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── PinnedActionStore.swift           # Palette pins (max 10) + PaletteOrder: pinned → recent → title
│   │   ├── RelevanceProviding.swift          # Sub-menu relevance protocol
│   │   ├── RichPasteboardPayload.swift       # Multi-format pasteboard payload (text, HTML, RTF)
│   │   ├── StatusFeedback.swift              # Toast notification model
│   │   ├── SubAction.swift                   # SubActionProviding protocol
│   │   └── URLTemplateAction.swift           # Web search / URL template action
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader; reports changes via onRegister/onUnregister callbacks
│   │   ├── ExtensionPackageInfo.swift        # Metadata for installed extension packages
│   │   ├── ExtensionStoreCache.swift         # In-memory store cache
│   │   ├── ExtensionUpdateBatchResult.swift  # Batch update result summary
│   │   ├── ExtensionUpdatePlanner.swift      # Extension update plan evaluator
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ActionRequirements.swift      # Requirements model (regex, apps, requiredOptions, expression)
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   ├── ExtensionManifest.swift       # Extension manifest decoder
│   │   │   ├── ExtensionManifestStore.swift  # Manifest file locate/read/write (shared home)
│   │   │   ├── ManifestValidation.swift      # Manifest validation pass + empty capability gate + fingerprint record
│   │   │   └── ValidateExpression.swift      # Computed visibility expression DSL AST & evaluator
│   │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser (nonisolated, pure text); body mode ends only at `#` header keys, `//` lines stay body
│   │   ├── ScriptAction.swift                # Executable script action
│   │   ├── ShellProcessRunner.swift          # Shared subprocess executor; an explicit timeout arms a GCD-timer watchdog that terminates the child (process group when the child is group leader, else snapshotted descendants), with no watchdog when no timeout is set + readabilityHandler reads (never blocks a thread); hosts TimeoutFlag/OnceGate; maps stdout JSON via ShellResultMapper
│   │   └── Trust/                            # Extension trust & consent gate
│   │       ├── ContentFingerprint.swift      # Package SHA-256 fingerprinting
│   │       ├── ExtensionPackageHashResolver.swift # Recursive package hashing
│   │       ├── ExtensionRiskProfile.swift    # Extension risk assessment
│   │       ├── ExtensionTrustGate.swift      # Trust state decision engine
│   │       ├── ExtensionTrustState.swift     # Trust lifecycle states (seen/trusted/revoked)
│   │       └── SemanticVersion.swift         # Semantic version parser & comparator
│   ├── Lifecycle/
│   │   └── AppLaunchClassifier.swift         # Startup scenario classifier (firstInstall, appUpdate, permissionRecovery, normalLaunch)
│   ├── Rules/                                # Built-in per-app selection policy
│   │   ├── AppRule.swift                     # AppPolicyContext (denyPaste, retrievalMode, gate) + built-in AppRule model
│   │   ├── DefaultAppRules.swift             # Built-in per-app rule catalog (retrieval mode, denyPaste)
│   │   ├── PasteAvailability.swift           # Paste availability tri-state (canPaste, cannotPaste, unknown)
│   │   ├── RuleEngine.swift                  # Resolves AppPolicyContext from DefaultAppRules (no user rules)
│   │   ├── SelectionGatePolicy.swift         # Pre-retrieval role & cursor gate policy
│   │   └── SelectionRetrievalMode.swift      # Selection retrieval strategy selector
│   ├── Selection/                            # Text selection models
│   │   ├── AppFilter.swift                   # App bundle filtering helpers
│   │   ├── AppIdentifying.swift              # Application identity protocol
│   │   ├── BrowserDetector.swift             # Browser bundle ID classifier
│   │   ├── Constants.swift                   # Domain/runtime constants (timeouts, key codes, env vars, manifest keys) — no UI sizing
│   │   ├── SelectionContext.swift            # Selection snapshot context (source: selection or clipboard)
│   │   ├── SelectionReadResponse.swift       # TextReadResponse / SelectionTriggerResponse read outcomes
│   │   └── TextRetrieving.swift              # Text retrieval protocol
│   ├── Settings/                             # Settings subsystem
│   │   ├── ActionOptionStore.swift           # ActionOptionReading & ActionOptionWriting protocols + SettingsActionOptionStore
│   │   ├── ActionUsageStore.swift            # Usage frequency tracking for search ranking
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore protocol + DefaultSettingsStore adapter
│   └── Utils/
│       ├── TextDiff.swift                    # Character-level Myers diff (input → result) behind the result card's diff view
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine ({text}, {query}, {html}, {rtf}, {matched}, {captureN}, {bundleID})
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AppDelegate.swift                     # Lifecycle, onboarding check (hasCompletedOnboarding), hotkey + Capture Text setup
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── StatusBarController.swift             # Status bar item and menu: Settings, updates, Quit (reads showMenuBarIcon)
    ├── AI/                                   # AI Assistant & Providers
    │   ├── AIAction.swift                    # Action conforming AI preset runner
    │   ├── AIActionSync.swift                # Synchronizes AIAction instances with AIServiceManager presets
    │   ├── AIProvider.swift                  # AIProvider protocol & prompt formatting
    │   ├── AIServiceManager.swift            # cloudAPIKey is SecretStore-backed (@Published), other prefs via @AppStorage
    │   ├── AIToolsAction.swift               # AI Tools group launcher action
    │   ├── AIConversation.swift              # A card session (selection + instructions + results) rendered as labelled context for follow-ups
    │   └── Providers/                        # Apple Intelligence, Local LLMs, CLI Subscriptions, Cloud API
    │       ├── AppleIntelligenceProvider.swift # On-device Apple Intelligence runner
    │       ├── CLIProvider.swift             # Subprocess CLI runner (Claude Code, Codex CLI, GitHub Copilot)
    │       ├── CloudAPIProvider.swift        # OpenAI-compatible / Anthropic / Gemini / DeepSeek / Groq cloud chat
    │       ├── CloudAPIProviderDTOs.swift    # Codable chat request/response payloads for cloud APIs
    │       └── LocalLLMProvider.swift        # Universal local LLM runner (LM Studio, Ollama, Jan, llama.cpp)
    ├── Notifications/
    │   └── Notification.Name+OpenClip.swift  # Internal notification names
    ├── Platform/                             # macOS Platform Services
    │   ├── AppIdentifying+NSRunningApplication.swift # AppIdentifying conformance
    │   ├── AppleScriptRunner.swift           # Bounded off-main AppleScript executor (killable osascript subprocess via ShellProcessRunner)
    │   ├── AppUpdateManager.swift            # Sparkle software update coordinator
    │   ├── BuiltinActions/                   # AppKit platform actions (open URL, reveal in Finder)
    │   │   ├── OpenURLAction.swift
    │   │   └── RevealInFinderAction.swift
    │   ├── DebugLogging/                     # In-process debug log store, file sink + --dump-logs CLI (App target)
    │   │   ├── DebugLogBuffer.swift          # Thread-safe capacity-capped ring buffer (LogSink)
    │   │   ├── DebugLogCommand.swift         # --dump-logs arg parsing + line formatting
    │   │   ├── DebugLogEntry.swift           # Captured log entry model (timestamp/category/level/message)
    │   │   ├── DebugLogFilter.swift          # Pure category/level/count filter
    │   │   ├── DebugLogLevel.swift           # Severity level enum (values mirror OSLogEntryLog.Level)
    │   │   ├── DebugLogStore.swift           # Buffer-backed log store (0ms delay, zero polling) + .shared
    │   │   ├── LogExporter.swift             # Diagnostic log archive exporter
    │   │   └── RotatingFileLogSink.swift     # Thread-safe rotating file appender (~/Library/Logs/OpenClip/openclip.log, 5MB cap, 3 backups)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler (pasteboard, workspace, sharing, shortcuts, key events)
    │   ├── Extensions/
    │   │   ├── CustomActionManifestWriter.swift # GUI-authored custom action manifest serializer
    │   │   ├── DefaultActionFactory.swift    # ActionFactory implementation (routing kinds incl. keyPress/shortcut/service/group)
    │   │   ├── ExtensionsDirectoryWatcher.swift # Hot reload directory watcher for ~/.openclip/extensions
    │   │   ├── ExtensionUpdateManager.swift  # Extension store update checker
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift # Snippet parser factory integration
    │   │   ├── RemoteExtensionInstaller.swift # Zip download and extraction installer
    │   │   └── SecretActionOptionStore.swift # Composite option store; .secret options → SecretStore (~/.openclip/secrets.json)
    │   ├── DeepLinkRouter.swift              # Acts on inbound openclip:// URLs (install, open-settings)
    │   ├── HotkeyManager.swift               # Global shortcuts: ⌥⌘C reads the selection on demand and opens the palette (or hides it), per-action hotkeys, Capture Text
    │   ├── Inline/
    │   │   └── InlineResultEvaluator.swift   # Tiered inline result evaluation for palette rows (isInlineResult actions)
    │   ├── InstalledAppsScanner.swift        # Running and installed app scanner
    │   ├── LaunchAtLoginManager.swift        # Login item manager (SMAppService; persisted state via SettingKey.startAtLogin)
    │   ├── OCR/
    │   │   └── CaptureTextController.swift   # Capture Text: region selection + Vision OCR, copies the text and shows a toast
    │   ├── PaletteRowShortcuts.swift         # ⌘1…⌘9 palette-row global hot keys, active only while the palette shows
    │   ├── PasteAvailabilityProbe.swift      # AX probe walking Edit ▸ Paste menu items
    │   ├── PermissionManager.swift           # Accessibility and Screen Recording permission manager
    │   ├── Runtimes/                         # Runtime action executors requiring AppKit / JavaScriptCore
    │   │   ├── AppleScriptAction.swift       # AppleScript action runtime
    │   │   ├── JavaScriptAction.swift        # Manifests JS actions; short-circuits to .openConfiguration when required option unresolved, else delegates to OpenClipJSHost
    │   │   ├── JSNativeFetch.swift           # JS fetch() URLSession polyfill
    │   │   ├── KeyPressAction.swift          # type: "keyPress" runtime → .keyPress(KeyPressSpec)
    │   │   ├── NamedServiceAction.swift      # type: "service" runtime → .showServices(text)
    │   │   ├── OpenClipJSHost.swift          # JS bridge (openclip.*) + effect resolver + .openConfiguration short-circuit support
    │   │   ├── OpenClipJSHostSupport.swift   # Threading/support boxes for the JS host (TimeoutFlag, gate, JS context/value/runloop boxes, promise state)
    │   │   ├── OpenClipModuleLoader.swift    # CommonJS require() module loader and containment validator
    │   │   └── ShortcutAction.swift          # type: "shortcut" runtime → .runShortcut(name:input:)
    │   ├── SecretStore.swift                 # File-backed secrets storage (~/.openclip/secrets.json, POSIX 0600)
    │   ├── Selection/                        # Selection retrieval bridge to OpenSelection package
    │   │   ├── CollapsedCaretProbe.swift     # Focused text control with a collapsed caret → the palette hotkey sends no ⌘C
    │   │   └── OpenSelectionBridge.swift     # Re-exports OpenSelection, maps Core domain types, logging bridge
    │   └── UnifiedIconProvider.swift         # Unified icon loader and cache
    ├── Resources/
    │   └── Localizable.xcstrings             # App string catalog (en source + zh-Hans, zh-Hant, fr, ja). Regenerate with scripts/generate_localizable.py
    ├── Settings/
    │   ├── SettingKey+MenuBar.swift          # Menu bar visibility setting key definition
    │   └── SettingKey+ResultCard.swift       # Remembered result card size
    └── UI/                                   # User Interface (SwiftUI & AppKit Panels)
        ├── AppIcon.swift                     # App icon loaded from bundle AppIcon.icns
        ├── Design/
        │   └── LiquidGlass.swift             # glassSurface modifier: Liquid Glass (.glassEffect) on macOS 26+, .ultraThinMaterial fallback on macOS 14-15
        ├── Icons/
        │   ├── ActionIconView.swift          # Dynamic icon renderer
        │   └── LocalIconCache.swift          # In-memory and disk icon image cache
        ├── Onboarding/                       # First-launch 3-step wizard (Welcome → Access → Extensions)
        │   ├── OnboardingView.swift          # Step flow view (Welcome, Access, Extensions)
        │   ├── OnboardingWindowController.swift # Transparent borderless window hosting the onboarding card
        │   └── RecommendedExtensionsView.swift  # Top recommended extensions listing + Install File
        ├── PermissionRecovery/
        │   ├── PermissionRecoveryView.swift  # Accessibility permission re-prompt UI
        │   └── PermissionRecoveryWindowController.swift # Permission recovery window controller
        ├── Popup/                            # Floating popup panel: command palette + result card
        │   ├── FilePreviews/                 # PDFPreviewView, QuickLookPreviewView for file results
        │   ├── PaletteAIPrompt.swift         # Palette AI rows: "Ask AI" / "Save as AI tool", the ⏎/⇧⏎ hint, instruction + tool-title rules
        │   ├── PaletteRowAccessories.swift   # Row trailing side: alias → hotkey → ⌘N (inline preview covers them until ⌘ is held)
        │   ├── PaletteSourceFooter.swift     # Footer selection/clipboard switch + start of the active text
        │   ├── PopupHoverSupport.swift       # Shared popup hover-state singleton + content-size preference key
        │   ├── PopupMetrics.swift            # UI-only palette/result-card/toast sizing + timing constants (App target, not Core)
        │   ├── PopupModeStore.swift          # Shared observable search↔content mode + resultCard payload
        │   ├── PopupPanel.swift              # NSPanel subclass (scoped allowsKey, top-edge anchoring + re-centering on resize)
        │   ├── PopupPositioner.swift         # Spotlight-style frame on the mouse's screen (pure static, no singletons)
        │   ├── PopupResizeGeometry.swift     # Pure resize geometry for the result card handles
        │   ├── PopupResizeHandles.swift      # Right/bottom/corner resize handles (SwiftUI gestures)
        │   ├── PopupSearchView.swift         # Command palette: field + ranked results + footer
        │   ├── PopupThemeModel.swift         # Theme resolution: category (classic/glass) + shared appearance → tokens/colorScheme
        │   ├── PopupView.swift               # Popup root view: the palette, replaced by the result card in .content mode
        │   ├── PopupWindowController.swift   # Window lifecycle, search/content switch, event monitoring, result delivery
        │   ├── ResultCardView.swift          # Native result card (back chevron + action icon/sparkles + title + diff toggle header, header-drag gesture, scrollable body/diff, follow-up field, Copy/Paste footer) for .content mode
        │   ├── SearchHoverSupport.swift      # Search-palette hover-target/frame preference keys
        │   ├── ToastPanel.swift              # Non-key floating NSPanel behind the status toast
        │   ├── ToastPanelController.swift    # Owns the toast panel + auto-dismiss timer; single status surface
        │   └── ToastView.swift               # One-line SwiftUI toast `[spinner | icon] message`, PopupThemeModel-themed
        └── Preferences/                      # Settings window (sidebar + router-driven pages, no popovers/sheets)
            ├── AboutTabView.swift            # About page: "OpenClip Lite", version, GitHub link, updates, diagnostics
            ├── ActionAppearanceFields.swift  # Hero icon/name fields + IconPickerPage
            ├── ActionDuplicator.swift        # Duplicate a custom action or extension next to the original
            ├── ActionEditorPage.swift        # One action's settings page (enabled, appearance, keyboard, options/logic, delete/duplicate)
            ├── ActionEnablement.swift        # Shared enable-switch rule for actions and packages
            ├── ActionKindPages.swift         # Built-in and Extensions pages + the shared ActionKindHeader
            ├── ActionSettingsRow.swift       # Read-only action row: icon, name, alias/hotkey, switch, opens the action's page
            ├── AIActionsSection.swift        # AI prompt library section (reorderable, rows drill into a prompt)
            ├── AIConfigureForm.swift         # Shared AI engine/provider form (embedded in AIPage and onboarding)
            ├── AIPage.swift                  # AI page (toggle + engine + prompts) and the prompt edit/new pages
            ├── AppearanceSettingsCard.swift  # General ▸ Appearance card: Popup Theme, Color Mode, Notification Size
            ├── CustomActionsPage.swift       # Custom page: the user's actions, then create with AI or by kind
            ├── DynamicActionConfigView.swift # Dynamic extension options configuration view
            ├── ExtensionCardView.swift       # Store list row for a single extension listing
            ├── ExtensionInstallPanel.swift   # Shared "Install File…" NSOpenPanel presenter
            ├── ExtensionPackagePage.swift    # One installed extension's page (toggle, actions, update, remove)
            ├── ExtensionsStoreView.swift     # Extension store browser (ViewModel + ExtensionStoreView)
            ├── GeneralTabView.swift          # General page: shortcuts, appearance, save location, menu bar, login, permissions
            ├── IconPickerView.swift          # SF Symbol / Iconify / custom icon picker (compact or full-page)
            ├── InstalledExtensionInfo.swift  # Installed packages derived from the action catalog
            ├── NewCustomActionPage.swift     # Page to create a custom action
            ├── PalettePage.swift             # Palette page: Pinned (drag to order) + All Actions, Pin/Unpin menu
            ├── PreferencesToolbar.swift      # AppKit toolbar: back/forward group, title, store filter/search, + button, page switch + … menu
            ├── PreferencesView.swift         # Settings window root: sidebar + SettingsNavigationStack detail
            ├── SettingsNavigationStack.swift # Mounted-levels page host, SettingsEditorPage footer layout, shared rows
            ├── SettingsDestination.swift     # Router path to any action's home (AI / Built-in / Custom / Extensions)
            ├── SettingsHeroHeader.swift      # Centred icon/title/subtitle identity block for pages about one thing
            ├── SettingsNoticeBanner.swift    # Inline (glass) notice that replaces NSAlert in the window
            ├── SettingsRouter.swift          # SettingsPage enum + SettingsRouter (path, history, notices)
            ├── SettingsRowLabel.swift        # Shared settings row shapes
            ├── SettingsToolbarAccessories.swift # Trailing toolbar switch + ellipsis menu models and per-page items
            ├── SettingsSidebar.swift         # Sidebar: app pages, then the static Actions group (AI, Built-in, Custom, Extensions)
```