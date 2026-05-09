//
//  DSGallery.swift
//  DynamicNotch — Design System
//
//  A SwiftUI Preview-only gallery showcasing every token & component.
//  Use it as your living styleguide:
//  - Open this file in Xcode
//  - Hit ⌥⌘P to toggle the canvas
//  - Browse all tokens & components in one place
//
//  This file is not referenced from any production code path.
//

import SwiftUI

#if DEBUG

struct DSGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                section("Logo") { logoSection }
                section("Colors") { colorSection }
                section("Typography") { typographySection }
                section("Spacing & Radius") { spacingRadiusSection }
                section("Effects (Shadows & Glows)") { effectsSection }
                section("Buttons") { buttonsSection }
                section("Icon Tiles") { iconTilesSection }
                section("Badges & Pills") { badgesPillsSection }
                section("Cards & Drop Zone") { cardsDropZoneSection }
                section("Notch Header") { notchHeaderSection }
            }
            .padding(DS.Spacing.xxl)
        }
        .background(DS.Color.surfaceBase)
        .preferredColorScheme(.dark)
    }

    // MARK: section helper

    @ViewBuilder
    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(title)
                .font(DS.Typography.displayMedium)
                .foregroundStyle(DS.Color.textPrimary)
            content()
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
        }
    }

    // MARK: sections

    var logoSection: some View {
        // `NSImage(named: "AppIcon")` doesn't resolve the AppIcon asset by name
        // — Apple ships it under `NSImage.applicationIconName`, which returns
        // the running app's actual icon (the one users see in the Dock).
        let appIcon = NSImage(named: NSImage.applicationIconName) ?? NSImage()
        return HStack(spacing: DS.Spacing.lg) {
            ForEach([16, 32, 64, 128, 256], id: \.self) { size in
                VStack(spacing: DS.Spacing.xs) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: CGFloat(size), height: CGFloat(size))
                    Text("\(size)pt").font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    var colorSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            colorRow("Surface", swatches: [
                ("base", DS.Color.surfaceBase),
                ("raised", DS.Color.surfaceRaised),
                ("raisedStrong", DS.Color.surfaceRaisedStrong),
            ])
            colorRow("Text", swatches: [
                ("primary", DS.Color.textPrimary),
                ("secondary", DS.Color.textSecondary),
                ("tertiary", DS.Color.textTertiary),
                ("quaternary", DS.Color.textQuaternary),
            ])
            colorRow("Brand", swatches: [
                ("brand", DS.Color.brand),
                ("brandStrong", DS.Color.brandStrong),
                ("brandSoft", DS.Color.brandSoft),
            ])
            colorRow("Semantic", swatches: [
                ("destructive", DS.Color.destructive),
                ("warning", DS.Color.warning),
                ("success", DS.Color.success),
                ("info", DS.Color.info),
            ])
        }
    }

    func colorRow(_ title: String, swatches: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.Color.textTertiary)
            HStack(spacing: DS.Spacing.sm) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(color)
                            .frame(width: 80, height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .strokeBorder(DS.Color.borderSubtle, lineWidth: 1)
                            )
                        Text(name).font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
    }

    var typographySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Group {
                Text("displayLarge — 28").font(DS.Typography.displayLarge)
                Text("displayMedium — 22").font(DS.Typography.displayMedium)
                Text("title — 17").font(DS.Typography.title)
                Text("headline — 15").font(DS.Typography.headline)
                Text("body — 13").font(DS.Typography.body)
                Text("bodyEmphasis — 13 / semi").font(DS.Typography.bodyEmphasis)
                Text("caption — 11").font(DS.Typography.caption)
                Text("captionSmall — 10").font(DS.Typography.captionSmall)
                Text("mono — 11 / mono").font(DS.Typography.mono)
            }
            .foregroundStyle(DS.Color.textPrimary)
        }
    }

    var spacingRadiusSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.lg) {
                ForEach([("xxs", DS.Spacing.xxs), ("xs", DS.Spacing.xs), ("sm", DS.Spacing.sm),
                         ("md", DS.Spacing.md), ("lg", DS.Spacing.lg), ("xl", DS.Spacing.xl),
                         ("xxl", DS.Spacing.xxl)], id: \.0) { name, value in
                    VStack(spacing: 4) {
                        Rectangle().fill(DS.Color.brand).frame(width: value, height: value)
                        Text(name).font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
            HStack(spacing: DS.Spacing.lg) {
                ForEach([("xs", DS.Radius.xs), ("sm", DS.Radius.sm), ("md", DS.Radius.md),
                         ("lg", DS.Radius.lg), ("xl", DS.Radius.xl), ("xxl", DS.Radius.xxl)], id: \.0) { name, value in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: value, style: .continuous)
                            .fill(DS.Color.surfaceRaisedStrong)
                            .frame(width: 64, height: 40)
                        Text(name).font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
    }

    var effectsSection: some View {
        HStack(spacing: DS.Spacing.lg) {
            effectChip("shadowSm", DS.Effect.shadowSm)
            effectChip("shadowMd", DS.Effect.shadowMd)
            effectChip("shadowLg", DS.Effect.shadowLg)
            effectChip("glowBrand", DS.Effect.glowBrand)
            effectChip("glowDestructive", DS.Effect.glowDestructive)
            effectChip("glowWarning", DS.Effect.glowWarning)
        }
    }

    func effectChip(_ name: String, _ effect: DS.Effect.Shadow) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.surfaceRaisedStrong)
                .frame(width: 80, height: 50)
                .dsShadow(effect)
            Text(name).font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.sm)
    }

    var buttonsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                DSButton("Primary", systemImage: "sparkles", role: .primary) {}
                DSButton("Secondary", systemImage: "tray", role: .secondary) {}
                DSButton("Destructive", systemImage: "trash", role: .destructive) {}
                DSButton("Warning", systemImage: "exclamationmark.triangle", role: .warning) {}
                DSButton("Ghost", role: .ghost) {}
            }
            HStack(spacing: DS.Spacing.md) {
                DSButton("Small", role: .primary, size: .small) {}
                DSButton("Medium", role: .primary, size: .medium) {}
                DSButton("Large", role: .primary, size: .large) {}
            }
        }
    }

    var iconTilesSection: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIconTile(systemImage: "gear",      title: "Settings",    tone: .brand) {}
            DSIconTile(systemImage: "tray.full", title: "Inbox",       tone: .neutral) {}
            DSIconTile(systemImage: "trash",     title: "Clear",       tone: .warning) {}
            DSIconTile(systemImage: "power",     title: "Quit",        tone: .destructive) {}
        }
    }

    var badgesPillsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                DSBadge("3", tone: .brand)
                DSBadge(count: 12, tone: .destructive)
                DSBadge(count: 1234, tone: .warning)
                DSBadge("NEW", tone: .neutral)
            }
            HStack(spacing: DS.Spacing.sm) {
                DSPill("Idle", systemImage: "moon", tone: .neutral)
                DSPill("Connected", systemImage: "checkmark", tone: .success)
                DSPill("Syncing", systemImage: "arrow.triangle.2.circlepath", tone: .brand)
                DSPill("Quota low", systemImage: "exclamationmark", tone: .warning)
                DSPill("Error", systemImage: "xmark", tone: .destructive)
            }
        }
    }

    var cardsDropZoneSection: some View {
        HStack(spacing: DS.Spacing.lg) {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Card").font(DS.Typography.headline).foregroundStyle(DS.Color.textPrimary)
                    Text("A standard surface for grouping content.")
                        .font(DS.Typography.body).foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(width: 220)

            DSDropZone(isTargeted: false) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                    Text("Drop files").font(DS.Typography.body)
                }
                .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(width: 160, height: 100)

            DSDropZone(isTargeted: true) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20))
                    Text("Release to drop").font(DS.Typography.body)
                }
                .foregroundStyle(DS.Color.brandSoft)
            }
            .frame(width: 160, height: 100)
        }
    }

    var notchHeaderSection: some View {
        DSNotchHeader(title: "DynamicNotch") { _ in }
            .padding(DS.Spacing.md)
            .frame(width: 480)
            .background(DS.Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

#Preview("Design System Gallery") {
    DSGallery()
        .frame(width: 980, height: 1400)
}

#endif
