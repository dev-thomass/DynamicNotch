import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import Observation
import SwiftUI

@MainActor
@Observable
final class NotchViewModel: PersistObservable {
    @ObservationIgnored var cancellables: Set<AnyCancellable> = []
    /// Abonnement à `ActivityCenter`, posé par `setupCancellables()`.
    @ObservationIgnored var activityObservation: ActivityObservation?
    @ObservationIgnored let activities: ActivityCenter
    @ObservationIgnored private var isSuspendingActivities = false
    /// Pointeur dans la coque au dernier mouvement : le retour haptique du
    /// survol des ailes ne part qu'à l'entrée.
    @ObservationIgnored var isPointerInsideShell = false

    /// `activities` à `nil` → `ActivityCenter.shared`. (Une valeur par défaut
    /// `.shared` serait évaluée hors du MainActor en Swift 5 : avertissement.)
    init(geometry: NotchGeometry = .preview, activities: ActivityCenter? = nil) {
        self.geometry = geometry
        self.activities = activities ?? .shared
        setupCancellables()
        // Une activité peut déjà être en cours (connexion, reconstruction des
        // fenêtres) : on la reprend d'emblée, sans animation.
        presentation = restingPresentation
    }

    /// Ressort des animations internes aux widgets.
    let animation: Animation = DS.Motion.expand

    let dropDetectorRange: CGFloat = 32

    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case unknown
    }

    enum ContentType: Hashable {
        case tab(NotchTab)
        case settings
    }

    private(set) var presentation: NotchPresentation = .closed
    var geometry: NotchGeometry
    var openReason: OpenReason = .unknown
    var spacing: CGFloat = 16
    var optionKeyPressed: Bool = false

    // MARK: géométrie (coordonnées écran AppKit)

    var deviceNotchRect: CGRect {
        geometry.notchRect
    }

    var screenRect: CGRect {
        geometry.screen.frame
    }

    var hasHardwareNotch: Bool {
        geometry.hasHardwareNotch
    }

    /// Marge de survol et de clic : élargie de 4 pt autour d'une vraie encoche.
    var inset: CGFloat {
        hasHardwareNotch ? -4 : 0
    }

    var metrics: ShellMetrics {
        presentation.metrics(
            notch: deviceNotchRect.size,
            hasHardwareNotch: hasHardwareNotch,
            scale: geometry.screen.scale
        )
    }

    var notchOpenedSize: CGSize {
        contentType.panelSize
    }

    var notchOpenedRect: CGRect {
        let size = notchOpenedSize
        return CGRect(
            x: deviceNotchRect.midX - size.width / 2,
            y: screenRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Rectangle de la coque dans son état courant.
    var currentShellRect: CGRect {
        let m = metrics
        return CGRect(
            x: deviceNotchRect.midX - m.bodyWidth / 2,
            y: screenRect.maxY - m.bodyHeight,
            width: m.bodyWidth,
            height: m.bodyHeight
        )
    }

    @ObservationIgnored
    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @ObservationIgnored
    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    /// Dernier onglet choisi, rouvert à chaque ouverture (sauf dépôt de fichier).
    @ObservationIgnored
    @PublishedPersist(key: "lastTab", defaultValue: .home)
    var lastTab: NotchTab

    /// Bord par lequel arrive le contenu au prochain changement d'onglet.
    private(set) var tabSlideEdge: Edge = .trailing

    @ObservationIgnored let hapticSender = PassthroughSubject<Void, Never>()
    /// Chaque nouvel état posé par `transition(to:)` (retour haptique, tests).
    @ObservationIgnored let presentationChanges = PassthroughSubject<NotchPresentation, Never>()

    // MARK: états

    /// Contenu du panneau ouvert (le dernier onglet hors de l'état ouvert).
    var contentType: ContentType {
        if case let .opened(content) = presentation {
            return content
        }
        return .tab(lastTab)
    }

    /// Onglet affiché, `nil` hors onglets (fermé, réglages…).
    var currentTab: NotchTab? {
        if case let .opened(.tab(tab)) = presentation {
            return tab
        }
        return nil
    }

    /// Change d'onglet (panneau ouvert seulement) et le mémorise.
    func selectTab(_ tab: NotchTab) {
        guard presentation.isOpened else { return }
        let from = currentTab ?? lastTab
        tabSlideEdge = NotchTab.slideEdge(from: from, to: tab)
        lastTab = tab
        if from != tab || currentTab == nil {
            hapticSender.send()
        }
        transition(to: .opened(.tab(tab)))
    }

    /// Quitte les réglages pour le dernier onglet.
    func closeSettings() {
        guard presentation == .opened(.settings) else { return }
        // Le dernier onglet arrive par la droite, comme à l'ouverture.
        tabSlideEdge = .trailing
        transition(to: .opened(.tab(lastTab)))
    }

    /// État de repos : l'activité en cours, sinon l'encoche nue.
    var restingPresentation: NotchPresentation {
        guard let display = activities.current else { return .closed }
        return display.mode == .expanded ? .expanded(display.id) : .compact(display.id)
    }

    /// Seul point d'entrée des changements d'état : choisit le ressort.
    func transition(to next: NotchPresentation) {
        guard next != presentation else { return }
        let kind = NotchPresentation.motion(from: presentation, to: next)
        withAnimation(DS.Motion.animation(kind)) {
            presentation = next
        }
        presentationChanges.send(next)
    }

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        // D'abord l'état ouvert : le rappel de la suspension (fin de la
        // ponctuelle) tombe alors sur la garde `isOpened` d'`activityDidChange`.
        // Un dépôt de fichier montre l'étagère ; sinon le dernier onglet.
        let tab: NotchTab = reason == .drag ? .files : lastTab
        transition(to: .opened(.tab(tab)))
        if !isSuspendingActivities {
            isSuspendingActivities = true
            activities.beginSuspension()
        }
        // Ne voler le focus que sur un clic explicite (pas pendant un
        // glisser-déposer depuis une autre app, ni au lancement).
        if reason == .click {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func notchClose() {
        openReason = .unknown
        if isSuspendingActivities {
            isSuspendingActivities = false
            activities.endSuspension()
        }
        transition(to: restingPresentation)
    }

    func notchPop() {
        guard presentation == .closed else { return }
        transition(to: .peek)
    }

    func showSettings() {
        // Hors de l'état ouvert : on passe par l'ouverture (suspension des activités).
        if !presentation.isOpened {
            notchOpen(.click)
        }
        transition(to: .opened(.settings))
    }

    /// Appelé par `ActivityCenter` : le panneau ouvert et l'aperçu ne sont pas interrompus.
    func activityDidChange() {
        guard !presentation.isOpened, presentation != .peek else { return }
        transition(to: restingPresentation)
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        activityObservation?.cancel()
        activityObservation = nil
        if isSuspendingActivities {
            isSuspendingActivities = false
            activities.endSuspension()
        }
    }

    #if DEBUG
    /// Rendu PNG des états (DebugTools) : pose un état sans animation.
    func setPresentationForRendering(_ state: NotchPresentation) {
        presentation = state
    }
    #endif
}
