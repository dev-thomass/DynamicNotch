//
//  DSTokens.swift
//  DynamicNotch — Design System
//
//  All visual tokens used across the app.
//  Namespace pattern: DS.Color.*, DS.Spacing.*, DS.Radius.*, DS.Motion.*, DS.Effect.*, DS.Typography.*
//
//  Rules:
//  - Never hard-code colors, font sizes, paddings, corner radii or animations in views.
//  - If a token is missing, add it here first, then use it.
//  - All tokens are dark-mode authored (the notch overlay is always dark).
//

import SwiftUI

/// Root namespace for the DynamicNotch design system.
public enum DS {}

// MARK: - Color

public extension DS {
    enum Color {

        // ─── Surface ──────────────────────────────────────────────────────────
        /// Pure black — used for the notch shell itself.
        public static let surfaceBase = SwiftUI.Color.black

        /// Subtle elevated surface (e.g. cards inside the notch).
        public static let surfaceRaised = SwiftUI.Color.white.opacity(0.06)

        /// More prominent elevated surface (hovered cards, active tiles).
        public static let surfaceRaisedStrong = SwiftUI.Color.white.opacity(0.10)

        /// Translucent overlay used for sheets / popovers within the notch.
        public static let surfaceScrim = SwiftUI.Color.black.opacity(0.55)

        // ─── Text ─────────────────────────────────────────────────────────────
        public static let textPrimary    = SwiftUI.Color.white
        public static let textSecondary  = SwiftUI.Color.white.opacity(0.72)
        public static let textTertiary   = SwiftUI.Color.white.opacity(0.48)
        public static let textQuaternary = SwiftUI.Color.white.opacity(0.28)
        public static let textOnAccent   = SwiftUI.Color.white

        // ─── Brand ────────────────────────────────────────────────────────────
        /// Primary brand cyan — picked from the icon's drop highlight.
        public static let brand        = SwiftUI.Color(red: 0.475, green: 0.725, blue: 1.000)   // #79B9FF
        public static let brandStrong  = SwiftUI.Color(red: 0.357, green: 0.659, blue: 1.000)   // #5BA8FF
        public static let brandSoft    = SwiftUI.Color(red: 0.769, green: 0.886, blue: 1.000)   // #C4E2FF

        /// Brand gradient (used for hero glows, primary buttons).
        public static let brandGradient = LinearGradient(
            colors: [brandSoft, brand, brandStrong],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // ─── Semantic ─────────────────────────────────────────────────────────
        public static let destructive  = SwiftUI.Color(red: 1.000, green: 0.271, blue: 0.227)   // #FF453A
        public static let warning      = SwiftUI.Color(red: 1.000, green: 0.624, blue: 0.039)   // #FF9F0A
        public static let success      = SwiftUI.Color(red: 0.188, green: 0.820, blue: 0.345)   // #30D158
        public static let info         = SwiftUI.Color(red: 0.392, green: 0.824, blue: 1.000)   // #64D2FF

        // ─── Border ───────────────────────────────────────────────────────────
        public static let borderSubtle  = SwiftUI.Color.white.opacity(0.06)
        public static let borderDefault = SwiftUI.Color.white.opacity(0.12)
        public static let borderStrong  = SwiftUI.Color.white.opacity(0.22)
        public static let borderFocus   = brand

        // ─── Drop zone (specific to file drag affordances) ────────────────────
        public static let dropZoneIdle      = SwiftUI.Color.white.opacity(0.08)
        public static let dropZoneTargeted  = brand.opacity(0.45)
    }
}

// MARK: - Spacing

public extension DS {
    enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs:  CGFloat = 4
        public static let sm:  CGFloat = 8
        public static let md:  CGFloat = 12
        public static let lg:  CGFloat = 16
        public static let xl:  CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }
}

// MARK: - Radius

public extension DS {
    enum Radius {
        public static let xs:   CGFloat = 4
        public static let sm:   CGFloat = 8
        public static let md:   CGFloat = 12
        public static let lg:   CGFloat = 16
        public static let xl:   CGFloat = 24
        public static let xxl:  CGFloat = 32
        public static let pill: CGFloat = 999
    }
}

// MARK: - Typography

public extension DS {
    /// Type scale. Avoid the name `Type` — it collides with Swift's metatype keyword.
    enum Typography {
        // SF Pro Rounded scale — matches Apple's system text styles
        // but tightened for the cramped notch real estate.
        public static let displayLarge  = Font.system(size: 28, weight: .bold,     design: .rounded)
        public static let displayMedium = Font.system(size: 22, weight: .bold,     design: .rounded)
        public static let title         = Font.system(size: 17, weight: .semibold, design: .rounded)
        public static let headline      = Font.system(size: 15, weight: .semibold, design: .rounded)
        public static let body          = Font.system(size: 13, weight: .regular,  design: .rounded)
        public static let bodyEmphasis  = Font.system(size: 13, weight: .semibold, design: .rounded)
        public static let caption       = Font.system(size: 11, weight: .medium,   design: .rounded)
        public static let captionSmall  = Font.system(size: 10, weight: .medium,   design: .rounded)
        public static let mono          = Font.system(size: 11, weight: .medium,   design: .monospaced)
    }
}

// MARK: - Motion

public extension DS {
    enum Motion {
        /// 120 ms — micro-feedback (hover, press).
        public static let fast = Animation.spring(response: 0.18, dampingFraction: 0.85)

        /// 280 ms — default UI transitions (state changes, view swaps).
        public static let base = Animation.spring(response: 0.32, dampingFraction: 0.78)

        /// 500 ms — the notch open/close. Matches the existing signature spring.
        public static let expressive = Animation.interactiveSpring(
            duration: 0.5,
            extraBounce: 0.25,
            blendDuration: 0.125
        )

        /// Linear ease for crossfades.
        public static let crossfade = Animation.easeInOut(duration: 0.18)
    }
}

// MARK: - Effects (shadows, glows, rims)

public extension DS {
    enum Effect {
        // Drop shadows
        public static let shadowSm = Shadow(color: .black.opacity(0.30), radius: 6,  x: 0, y: 2)
        public static let shadowMd = Shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
        public static let shadowLg = Shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 12)

        // Glows (use as outer halo on hovered/active elements)
        public static let glowBrand       = Shadow(color: DS.Color.brand.opacity(0.55),       radius: 22, x: 0, y: 0)
        public static let glowDestructive = Shadow(color: DS.Color.destructive.opacity(0.55), radius: 18, x: 0, y: 0)
        public static let glowWarning     = Shadow(color: DS.Color.warning.opacity(0.55),     radius: 18, x: 0, y: 0)

        public struct Shadow {
            public let color: SwiftUI.Color
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat

            public init(color: SwiftUI.Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
                self.color = color
                self.radius = radius
                self.x = x
                self.y = y
            }
        }
    }
}

// MARK: - View modifiers (sugar)

public extension View {
    /// Apply a DS shadow token.
    func dsShadow(_ shadow: DS.Effect.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    /// Apply the standard DS card surface (raised background + subtle border).
    func dsCard(radius: CGFloat = DS.Radius.lg) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.borderSubtle, lineWidth: 1)
            )
    }

    /// Apply a soft inner rim light (top edge), useful on dark surfaces.
    func dsRimLight(radius: CGFloat = DS.Radius.lg) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        )
    }
}
