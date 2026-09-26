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
            .brightness(isHovering ? 0.08 : 0)
            .opacity(isPressed ? 0.75 : 1)
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
                .fill(isTargeted ? DS.Color.dropZoneTargetedFill : DS.Color.dropZoneIdle)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .strokeBorder(isTargeted ? DS.Color.dropZoneTargetedBorder : DS.Color.borderDefault, lineWidth: 1)
                )
                .animation(DS.Motion.base, value: isTargeted)
                .animation(DS.Motion.base, value: isLoading)
            label()
        }
    }
}

// MARK: - DSModule

/// Module du panneau : carte gris sombre, rayon 16. Cliquable si `action`.
/// Ne pas passer d'`action` si `content` contient lui-même des contrôles (boutons, champs) : le module entier devient un bouton.
public struct DSModule<Content: View>: View {
    private let title: String?
    private let action: (() -> Void)?
    private let content: () -> Content

    public init(_ title: String? = nil, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.action = action
        self.content = content
    }

    public var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(DSHighlightButtonStyle(shape: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)))
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let title {
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.module)
        )
    }
}

// MARK: - DSIconButton

/// Bouton rond à icône seule. Survol plus clair, appui légèrement réduit
/// (autorisé : il ne contient pas de texte), rebond du symbole à chaque action.
public struct DSIconButton: View {
    public enum Size {
        case regular, large

        var diameter: CGFloat { self == .regular ? 30 : 36 }
        var iconSize: CGFloat { self == .regular ? 13 : 15 }
    }

    private let systemImage: String
    private let label: String
    private let size: Size
    private let action: () -> Void
    @State private var bounces = 0

    public init(_ systemImage: String, label: String, size: Size = .regular, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button {
            bounces += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size.iconSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounces)
                .foregroundStyle(DS.Color.textPrimary)
                .frame(width: size.diameter, height: size.diameter)
        }
        .buttonStyle(DSIconButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Surbrillance de survol (0,08) et d'appui (0,14) posée sur la forme.
private struct DSHighlightButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        DSHighlightBody(configuration: configuration, shape: shape)
    }
}

private struct DSHighlightBody<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .overlay(shape.fill(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0))))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(DS.Motion.micro, value: isHovering)
            .animation(DS.Motion.micro, value: configuration.isPressed)
    }
}

private struct DSIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSIconButtonBody(configuration: configuration)
    }
}

private struct DSIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(isHovering ? 0.16 : 0.10)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(DS.Motion.micro, value: isHovering)
            .animation(DS.Motion.micro, value: configuration.isPressed)
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
