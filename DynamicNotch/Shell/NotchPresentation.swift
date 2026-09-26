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
        if case .opened = self { return true }
        return false
    }

    func metrics(notch: CGSize, hasHardwareNotch: Bool, scale: CGFloat) -> ShellMetrics {
        let ear: CGFloat = hasHardwareNotch ? 6 : 0
        let largeEar: CGFloat = hasHardwareNotch ? 10 : 0
        switch self {
        case .closed:
            return ShellMetrics(
                bodyWidth: notch.width, bodyHeight: notch.height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 10 : notch.height / 2, hasShadow: false
            )
        case .peek:
            let height = notch.height + 4
            return ShellMetrics(
                bodyWidth: notch.width + 12, bodyHeight: height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 12 : height / 2, hasShadow: false
            )
        case let .compact(id):
            return ShellMetrics(
                bodyWidth: notch.width + WingLayout.wingsWidth(for: id, scale: scale),
                bodyHeight: notch.height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 12 : notch.height / 2, hasShadow: false
            )
        case .expanded:
            return ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: largeEar, bottomRadius: 24, hasShadow: true)
        case let .opened(content):
            let size = content.panelSize
            return ShellMetrics(bodyWidth: size.width, bodyHeight: size.height, topRadius: largeEar, bottomRadius: 28, hasShadow: true)
        }
    }

    /// Plus l'état est « grand », plus la valeur est élevée.
    private var magnitude: Int {
        switch self {
        case .closed: 0
        case .peek: 10
        case .compact: 20
        case .expanded: 30
        case let .opened(content): 40 + content.rawValue
        }
    }

    /// Ressort d'une transition : grandir rebondit, rétrécir non.
    static func motion(from: NotchPresentation, to: NotchPresentation) -> DS.Motion.Kind {
        if (from == .closed && to == .peek) || (from == .peek && to == .closed) { return .micro }
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
        case .normal: CGSize(width: 600, height: 180)
        case .menu: CGSize(width: 600, height: 200)
        case .settings: CGSize(width: 880, height: 560)
        }
    }
}
