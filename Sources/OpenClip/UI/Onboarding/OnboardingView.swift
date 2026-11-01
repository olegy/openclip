// OnboardingView.swift
// OpenClip
//
// Native macOS onboarding flow following Apple System Settings / Setup Assistant conventions:
// - Solid, edge-to-edge window background (Color(nsColor: .windowBackgroundColor))
// - Plain SF Symbols with .symbolRenderingMode(.hierarchical)
// - Tactile primary button style (gradient + arrow icon + scale on press)
// - Flat system inset cards with zero web drop-shadows
// - Vertically centered content with zero dead space
import SwiftUI
import AppKit
import Core

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case permission = 1
    case extensions = 2

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permission: return "Access"
        case .extensions: return "Extensions"
        }
    }
}

// MARK: - Tactile Button Styles

public struct MacPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6.5)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(
                color: Color.accentColor.opacity(configuration.isPressed ? 0.05 : 0.2),
                radius: configuration.isPressed ? 1.5 : 3,
                x: 0,
                y: configuration.isPressed ? 0.5 : 1.5
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct MacSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.01 : 0.04), radius: 1.5, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Onboarding View

@MainActor
public struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    public var onComplete: @MainActor () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var slideEdge: Edge = .trailing
    @State private var isSkipHovered = false

    public init(onComplete: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Top Header: Step Indicator ─────────────────────────────
            topBar
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // ── Center Content Area ────────────────────────────────────
            VStack {
                Spacer(minLength: 0)

                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .permission: permissionStep
                    case .extensions: extensionsStep
                    }
                }
                .transition(.push(from: slideEdge))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)

            // ── Bottom Navigation Bar ──────────────────────────────────
            bottomBar
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .padding(.top, 12)
        }
        .frame(width: 520, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // Compact Apple-style Progress Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: max(8, geo.size.width * CGFloat(step.rawValue + 1) / CGFloat(OnboardingStep.allCases.count)),
                            height: 3
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 72, height: 8)

            if !isLastStep {
                Button {
                    completeOnboarding()
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isSkipHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { isSkipHovered = $0 }
            }
        }
    }

    // MARK: - Bottom Navigation Bar

    private var bottomBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    slideEdge = .leading
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Back")
                    }
                }
                .buttonStyle(MacSecondaryButtonStyle())
            }

            Spacer()

            Button {
                if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                    slideEdge = .trailing
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = next
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isLastStep ? String(localized: "Get Started") : String(localized: "Continue"))
                    Image(systemName: isLastStep ? "arrow.right.circle.fill" : "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                }
            }
            .buttonStyle(MacPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var isLastStep: Bool {
        step == OnboardingStep.allCases.last
    }

    private func completeOnboarding() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
        DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
        DefaultSettingsStore.shared.set(.hasCompletedOnboarding, value: true)
        onComplete()
    }

    // MARK: - Screen 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            // Hero
            VStack(spacing: 6) {
                Image(systemName: "command.square.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 42))
                    .foregroundStyle(Color.accentColor)

                Text("OpenClip Lite")
                    .font(.title2.weight(.bold))

                Text("Select text in any app, press the shortcut, and pick an action from the palette. With nothing selected, the palette works on the clipboard.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Text("Command Palette")
                    .font(.headline)
                Spacer()
                Shortcut(for: .togglePopup)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Screen 2: Permission & Privacy

    private var permissionStep: some View {
        VStack(spacing: 16) {
            // Hero
            VStack(spacing: 6) {
                Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.shield.fill" : "hand.raised.square.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 42))
                    .foregroundStyle(permissionManager.isAccessibilityGranted ? Color.green : Color.accentColor)

                Text("Accessibility Access")
                    .font(.title2.weight(.bold))

                Text("So OpenClip can see what you've selected — text stays local by default unless you invoke cloud AI or browser actions.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // System Settings style Privacy Card
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 22))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("100% Private & On-Device")
                        .font(.headline)

                    Text("Highlighted text stays on your Mac by default. OpenClip never collects background data, and only transmits text when you explicitly invoke cloud AI or browser actions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Permission Action
            if permissionManager.isAccessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Accessibility Permission Granted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }
                .padding(.vertical, 4)
            } else {
                Button("Grant Access in System Settings…") {
                    permissionManager.requestAccessibilityPermission()
                }
                .buttonStyle(MacPrimaryButtonStyle())
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: permissionManager.isAccessibilityGranted)
    }

    // MARK: - Screen 3: Extensions (Curated Defaults)

    private var extensionsStep: some View {
        VStack(spacing: 12) {
            // Hero
            VStack(spacing: 4) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 38))
                    .foregroundStyle(Color.accentColor)

                Text("Essential Extensions")
                    .font(.title2.weight(.bold))

                Text("Install top extensions for instant translations, counts & speech.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            RecommendedExtensionsView()

            Text("Browse 100+ extensions in Menu Bar → Preferences")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
