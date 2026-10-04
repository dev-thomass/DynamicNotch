//
//  NotchPresentation.swift
//  DynamicNotch
//
//  Machine d'états de la coque : l'encoche est toujours dans exactement un de
//  ces états. Chaque état donne une géométrie (`ShellMetrics`) ; chaque
//  transition donne un ressort (`DS.Motion.Kind`).
//

import CoreGraphics

enum NotchPresentation: Equatable {
    case closed
    case peek
    case compact(ActivityID)
    case expanded(ActivityID)
    case opened(NotchViewModel.ContentType)

    var isOpened: Bool {
        if case .opened = self {
            return true
        }
        return false
    }

    func metrics(notch: CGSize, hasHardwareNotch: Bool, scale: CGFloat) -> ShellMetrics {
        let ear: CGFloat = hasHardwareNotch ? 6 : 0
        let largeEar: CGFloat = hasHardwareNotch ? 10 : 0
        switch self {
        case .closed:
            // Pas d'oreilles au repos : la coque épouse l'encoche physique.
            return ShellMetrics(
                bodyWidth: notch.width, bodyHeight: notch.height, topRadius: 0,
                bottomRadius: hasHardwareNotch ? 10 : notch.height / 2, hasShadow: false
            )
        case .peek:
            // Survol : on allonge de 3 pt vers le bas, sans élargir.
            let height = notch.height + 3
            return ShellMetrics(
                bodyWidth: notch.width, bodyHeight: height, topRadius: 0,
                bottomRadius: hasHardwareNotch ? 10 : height / 2, hasShadow: false
            )
        case let .compact(id):
            return ShellMetrics(
                bodyWidth: notch.width + WingLayout.wingsWidth(for: id, scale: scale),
                bodyHeight: notch.height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 12 : notch.height / 2, hasShadow: false
            )
        case .expanded:
            // 80 pt pour l'encoche de 32 pt et la pilule de 24 pt ; plus haut
            // si l'encoche l'est, pour garder 48 pt de contenu sous elle.
            let height = max(80, notch.height + 48)
            return ShellMetrics(
                bodyWidth: 340,
                bodyHeight: height,
                topRadius: largeEar,
                bottomRadius: 24,
                hasShadow: true
            )
        case let .opened(content):
            let size = content.panelSize
            return ShellMetrics(
                bodyWidth: size.width,
                bodyHeight: size.height,
                topRadius: largeEar,
                bottomRadius: 28,
                hasShadow: true
            )
        }
    }

    /// Plus l'état est « grand », plus la valeur est élevée.
    private var magnitude: Int {
        switch self {
        case .closed: 0
        case .peek: 10
        case .compact: 20
        case .expanded: 30
        case .opened: 40
        }
    }

    /// Ressort d'une transition : grandir rebondit, rétrécir non. Entre deux
    /// contenus ouverts, on compare la surface du panneau.
    static func motion(from: NotchPresentation, to: NotchPresentation) -> DS.Motion.Kind {
        if (from == .closed && to == .peek) || (from == .peek && to == .closed) {
            return .micro
        }
        if case let .opened(a) = from, case let .opened(b) = to {
            let areaA = a.panelSize.width * a.panelSize.height
            let areaB = b.panelSize.width * b.panelSize.height
            return areaB >= areaA ? .expand : .collapse
        }
        return to.magnitude >= from.magnitude ? .expand : .collapse
    }
}

struct ShellMetrics: Equatable {
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var hasShadow: Bool
}

extension NotchViewModel.ContentType {
    /// Taille du panneau ouvert selon le contenu.
    var panelSize: CGSize {
        switch self {
        case let .tab(tab): CGSize(width: 640, height: tab.panelHeight)
        case .settings: CGSize(width: 880, height: 560)
        }
    }
}
