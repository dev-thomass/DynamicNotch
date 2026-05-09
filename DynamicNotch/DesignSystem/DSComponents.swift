//
//  DSComponents.swift
//  DynamicNotch — Design System
//
//  Reusable UI primitives. All visual values come from DSTokens.
//  Build app UI by composing these — never hand-roll buttons/cards/badges in feature code.
//

import SwiftUI

// MARK: - DSButton

/// Standard button used across the app.
///
/// Use roles to communicate intent — they map to colors, glows, and confirmation
/// expectations (see UX guidelines in the design system docs).
public struct DSButton: View {
    public enum Role {
        case primary       // brand cyan, the default affirmative action
        case secondary     // neutral surface, equal to primary in importance
        case destructive   // red, requires confirmation when used
        case warning       // orange, used for irreversible-but-not-destructive
        case ghost         // text-only, lowest emphasis
    }

    public enum Size {
        case small
        case medium
        case large
    }

    private let title: LocalizedStringKey
    private let systemImage: String?
    private let role: Role
    private let size: Size
    private let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        role: Role = .primary,
        size: Size = .medium,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                }
                Text(title)
                    .font(textFont)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .frame(minHeight: minHeight)
            .background(background)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .dsShadow(shadow)
            .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))
            .animation(DS.Motion.fast, value: isHovering)
            .animation(DS.Motion.fast, value: isPressed)
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
    }

    // MARK: derived

    private var iconSize: CGFloat {
        switch size { case .small: 11; case .medium: 13; case .large: 15 }
    }
    private var textFont: Font {
        switch size { case .small: DS.Typography.caption; case .medium: DS.Typography.body; case .large: DS.Typography.headline }
    }
    private var paddingH: CGFloat {
        switch size { case .small: DS.Spacing.sm; case .medium: DS.Spacing.md; case .large: DS.Spacing.lg }
    }
    private var paddingV: CGFloat {
        switch size { case .small: DS.Spacing.xs; case .medium: DS.Spacing.sm; case .large: DS.Spacing.md }
    }
    private var minHeight: CGFloat {
        switch size { case .small: 22; case .medium: 30; case .large: 40 }
    }
    private var foreground: Color {
        switch role {
        case .primary, .destructive, .warning: DS.Color.textOnAccent
        case .secondary: DS.Color.textPrimary
        case .ghost: DS.Color.textSecondary
        }
    }
    @ViewBuilder
    private var background: some View {
        switch role {
        case .primary:
            DS.Color.brandGradient
        case .secondary:
            DS.Color.surfaceRaised
        case .destructive:
            DS.Color.destructive
        case .warning:
            DS.Color.warning
        case .ghost:
            Color.clear
        }
    }
    @ViewBuilder
    private var borderOverlay: some View {
        switch role {
        case .secondary:
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.borderDefault, lineWidth: 1)
        case .ghost:
            EmptyView()
        default:
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }
    private var shadow: DS.Effect.Shadow {
        guard isHovering else { return DS.Effect.shadowSm }
        switch role {
        case .primary: return DS.Effect.glowBrand
        case .destructive: return DS.Effect.glowDestructive
        case .warning: return DS.Effect.glowWarning
        default: return DS.Effect.shadowMd
        }
    }
}

// MARK: - DSIconTile

/// Square tile button used in the menu / quick-actions row.
/// Replaces the legacy `ColorButton` from `NotchMenuView`.
public struct DSIconTile: View {
    public enum Tone {
        case brand
        case neutral
        case destructive
        case warning
    }

    private let systemImage: String
    private let title: LocalizedStringKey
    private let tone: Tone
    private let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    public init(
        systemImage: String,
        title: LocalizedStringKey,
        tone: Tone = .brand,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.sm) {
                ZStack {
                    iconBackground
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .dsShadow(isHovering ? glow : DS.Effect.shadowSm)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconForeground)
                }
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(isHovering ? DS.Color.surfaceRaisedStrong : DS.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.96 : (isHovering ? 1.03 : 1.0))
            .animation(DS.Motion.fast, value: isHovering)
            .animation(DS.Motion.fast, value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pressEvents(onPress: { isPressed = true }, onRelease: { isPressed = false })
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var iconBackground: some View {
        switch tone {
        case .brand:       DS.Color.brandGradient
        case .neutral:     DS.Color.surfaceRaisedStrong
        case .destructive: DS.Color.destructive.opacity(0.95)
        case .warning:     DS.Color.warning.opacity(0.95)
        }
    }
    private var iconForeground: Color {
        switch tone {
        case .neutral: DS.Color.textPrimary
        default: DS.Color.textOnAccent
        }
    }
    private var glow: DS.Effect.Shadow {
        switch tone {
        case .brand:       DS.Effect.glowBrand
        case .destructive: DS.Effect.glowDestructive
        case .warning:     DS.Effect.glowWarning
        case .neutral:     DS.Effect.shadowMd
        }
    }
}

// MARK: - DSCard

/// A standard surface card. Use for grouping content inside the notch.
public struct DSCard<Content: View>: View {
    private let content: () -> Content
    private let radius: CGFloat
    private let padding: CGFloat

    public init(
        radius: CGFloat = DS.Radius.lg,
        padding: CGFloat = DS.Spacing.md,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .dsCard(radius: radius)
            .dsRimLight(radius: radius)
    }
}

// MARK: - DSBadge

/// Small numeric/text badge — use on icons or pinned to a corner.
public struct DSBadge: View {
    public enum Tone { case brand, destructive, warning, neutral }

    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone = .brand) {
        self.text = text
        self.tone = tone
    }

    public init(count: Int, tone: Tone = .brand) {
        // Cap at 99+ for legibility
        self.text = count > 99 ? "99+" : String(count)
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(DS.Typography.captionSmall)
            .foregroundStyle(DS.Color.textOnAccent)
            .monospacedDigit()
            .padding(.horizontal, DS.Spacing.xs + 1)
            .padding(.vertical, 1)
            .frame(minWidth: 16, minHeight: 16)
            .background(background)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var background: some View {
        switch tone {
        case .brand:        DS.Color.brand
        case .destructive:  DS.Color.destructive
        case .warning:      DS.Color.warning
        case .neutral:      DS.Color.surfaceRaisedStrong
        }
    }
}

// MARK: - DSPill

/// Inline status pill (icon + label). Use for read-only indicators.
public struct DSPill: View {
    public enum Tone { case brand, neutral, destructive, warning, success }

    private let label: LocalizedStringKey
    private let systemImage: String?
    private let tone: Tone

    public init(_ label: LocalizedStringKey, systemImage: String? = nil, tone: Tone = .neutral) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(label).font(DS.Typography.caption)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 3)
        .background(background)
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(border, lineWidth: 0.5))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: DS.Color.textSecondary
        case .brand:   DS.Color.brandSoft
        case .success: DS.Color.success
        case .warning: DS.Color.warning
        case .destructive: DS.Color.destructive
        }
    }
    @ViewBuilder
    private var background: some View {
        switch tone {
        case .neutral:     DS.Color.surfaceRaisedStrong
        case .brand:       DS.Color.brand.opacity(0.18)
        case .success:     DS.Color.success.opacity(0.18)
        case .warning:     DS.Color.warning.opacity(0.18)
        case .destructive: DS.Color.destructive.opacity(0.18)
        }
    }
    private var border: Color {
        foreground.opacity(0.25)
    }
}

// MARK: - DSDivider

public struct DSDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(DS.Color.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - DSDropZone

/// The standard drag-drop receptacle. Replaces the dashed border in `TrayView`.
public struct DSDropZone<Label: View>: View {
    private let isTargeted: Bool
    private let isLoading: Bool
    private let label: () -> Label

    public init(
        isTargeted: Bool,
        isLoading: Bool = false,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isTargeted = isTargeted
        self.isLoading = isLoading
        self.label = label
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(isTargeted ? DS.Color.dropZoneTargeted.opacity(0.35) : DS.Color.dropZoneIdle)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .strokeBorder(
                            isTargeted ? DS.Color.brand : DS.Color.borderDefault,
                            lineWidth: isTargeted ? 1.5 : 1
                        )
                )
                .dsShadow(isTargeted ? DS.Effect.glowBrand : DS.Effect.shadowSm)
                .animation(DS.Motion.base, value: isTargeted)
                .animation(DS.Motion.base, value: isLoading)
            label()
        }
    }
}

// MARK: - DSNotchHeader

/// Standard header used at the top of the opened notch.
/// Replaces the cycle-on-tap headline anti-pattern.
public struct DSNotchHeader: View {
    public enum Action {
        case menu
        case settings
        case close
    }

    /// Optionnel : configuration de la navigation entre pages affichée
    /// au centre-gauche du header (chevron ‹  X/Y  chevron ›).
    /// Quand `nil`, aucune navigation n'est affichée.
    public struct PageNavigation {
        public let currentPage: Int   // 0-based
        public let totalPages: Int
        public let onPrev: () -> Void
        public let onNext: () -> Void

        public init(currentPage: Int, totalPages: Int, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) {
            self.currentPage = currentPage
            self.totalPages = totalPages
            self.onPrev = onPrev
            self.onNext = onNext
        }
    }

    private let title: LocalizedStringKey
    private let onAction: (Action) -> Void
    private let showsBack: Bool
    private let onBack: (() -> Void)?
    private let pageNav: PageNavigation?

    public init(
        title: LocalizedStringKey,
        showsBack: Bool = false,
        onBack: (() -> Void)? = nil,
        pageNav: PageNavigation? = nil,
        onAction: @escaping (Action) -> Void
    ) {
        self.title = title
        self.showsBack = showsBack
        self.onBack = onBack
        self.pageNav = pageNav
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if showsBack {
                headerIconButton(systemImage: "chevron.left", label: "Retour") { onBack?() }
            }
            Text(title)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .contentTransition(.numericText())
            if let pageNav {
                pageNavigator(pageNav)
            }
            Spacer()
            headerIconButton(systemImage: "ellipsis.circle",   label: "Menu")     { onAction(.menu) }
            headerIconButton(systemImage: "gear",              label: "Réglages") { onAction(.settings) }
            headerIconButton(systemImage: "xmark.circle.fill", label: "Fermer")   { onAction(.close) }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    /// Sous-vue ‹  X/Y  ›  affichée à droite du titre quand il y a plus
    /// d'une page de widgets. Hit area étendue à 22pt sur les chevrons
    /// pour cliquage facile malgré la taille visuelle réduite (10pt).
    @ViewBuilder
    private func pageNavigator(_ nav: PageNavigation) -> some View {
        HStack(spacing: 2) {
            chevronButton(systemImage: "chevron.left",  label: "Page précédente", action: nav.onPrev)
            Text("\(nav.currentPage + 1)/\(nav.totalPages)")
                .font(DS.Typography.captionSmall)
                .monospacedDigit()
                .foregroundStyle(DS.Color.textTertiary)
                .frame(minWidth: 24)
                .contentTransition(.numericText())
            chevronButton(systemImage: "chevron.right", label: "Page suivante",  action: nav.onNext)
        }
        .padding(.leading, DS.Spacing.xs)
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 22, height: 22)   // hit area généreuse
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private func headerIconButton(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Press events helper

private struct PressActions: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded   { _ in onRelease() }
            )
    }
}

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressActions(onPress: onPress, onRelease: onRelease))
    }
}
