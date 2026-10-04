//
//  NotchGeometry.swift
//  DynamicNotch
//
//  Géométrie de l'encoche calculée une fois, au pixel physique près. Valeur
//  pure (aucune dépendance à NSScreen hors de l'initialiseur de commodité),
//  donc testable sans écran réel.
//

import AppKit

/// Arrondit `value` au pixel physique le plus proche pour une échelle donnée.
func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return value.rounded() }
    return (value * scale).rounded() / scale
}

/// Ce que l'on retient d'un `NSScreen` pour calculer la géométrie.
struct ScreenDescriptor: Equatable {
    var displayID: UInt32
    var frame: CGRect
    var scale: CGFloat
    var safeAreaTop: CGFloat
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?
    var menuBarHeight: CGFloat
}

extension ScreenDescriptor {
    init(_ screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        self.init(
            displayID: (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0,
            frame: screen.frame,
            scale: screen.backingScaleFactor,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            // Barre masquée (plein écran) → 24 pt, pour que la signature
            // d'écran reste stable.
            menuBarHeight: max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        )
    }
}

struct NotchGeometry: Equatable {
    static let pillWidth: CGFloat = 190
    static let fallbackWidthRatio: CGFloat = 0.12
    /// Plus grand corps (réglages 880 × 560) + oreilles (2 × 10) + marge d'ombre (24).
    static let windowSize = CGSize(width: 880 + 2 * 10 + 2 * 24, height: 560 + 24)

    let screen: ScreenDescriptor
    /// Encoche (ou pilule) en coordonnées écran AppKit (origine en bas à gauche).
    let notchRect: CGRect
    let hasHardwareNotch: Bool

    init(screen: ScreenDescriptor, forcePill: Bool = false) {
        self.screen = screen
        let scale = screen.scale
        let frame = screen.frame

        if screen.safeAreaTop > 0, !forcePill {
            let height = pixelAligned(screen.safeAreaTop, scale: scale)
            hasHardwareNotch = true
            // Voie nominale : les zones visibles de part et d'autre de l'encoche.
            // On n'utilise que leurs largeurs, valables quel que soit le repère.
            if let left = screen.auxiliaryTopLeft?.width, let right = screen.auxiliaryTopRight?.width,
               left > 0, right > 0
            {
                let minX = pixelAligned(frame.minX + left, scale: scale)
                let maxX = pixelAligned(frame.maxX - right, scale: scale)
                if maxX - minX > 50, maxX - minX < frame.width / 2 {
                    notchRect = CGRect(x: minX, y: frame.maxY - height, width: maxX - minX, height: height)
                    return
                }
            }
            let width = pixelAligned(frame.width * Self.fallbackWidthRatio, scale: scale)
            notchRect = CGRect(
                x: pixelAligned(frame.midX - width / 2, scale: scale),
                y: frame.maxY - height, width: width, height: height
            )
            return
        }

        hasHardwareNotch = false
        let height = pixelAligned(screen.safeAreaTop > 0 ? screen.safeAreaTop : screen.menuBarHeight, scale: scale)
        let width = Self.pillWidth
        notchRect = CGRect(
            x: pixelAligned(frame.midX - width / 2, scale: scale),
            y: frame.maxY - height, width: width, height: height
        )
    }

    /// Fenêtre de taille fixe, collée en haut de l'écran et centrée sur l'encoche.
    var windowFrame: CGRect {
        let size = Self.windowSize
        return CGRect(
            x: pixelAligned(notchRect.midX - size.width / 2, scale: screen.scale),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Centre horizontal de l'encoche dans le repère SwiftUI de la fenêtre.
    var notchCenterXInWindow: CGFloat {
        notchRect.midX - windowFrame.minX
    }

    /// Géométrie de l'écran de référence, pour les aperçus et le rendu Debug.
    static let preview = NotchGeometry(screen: ScreenDescriptor(
        displayID: 0,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        scale: 2,
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
        menuBarHeight: 32
    ))
}
