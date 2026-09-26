import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

@MainActor
final class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    /// Abonnement à `ActivityCenter`, posé par `setupCancellables()`.
    var activityObservation: ActivityObservation?
    let activities: ActivityCenter
    private var isSuspendingActivities = false

    /// `activities` à `nil` → `ActivityCenter.shared`. (Une valeur par défaut
    /// `.shared` serait évaluée hors du MainActor en Swift 5 : avertissement.)
    init(geometry: NotchGeometry = .preview, activities: ActivityCenter? = nil) {
        self.geometry = geometry
        self.activities = activities ?? .shared
        super.init()
        setupCancellables()
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

    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case menu
        case settings
    }

    @Published private(set) var presentation: NotchPresentation = .closed
    @Published var geometry: NotchGeometry
    @Published var openReason: OpenReason = .unknown
    @Published var spacing: CGFloat = 16
    @Published var optionKeyPressed: Bool = false

    // MARK: géométrie (coordonnées écran AppKit)

    var deviceNotchRect: CGRect { geometry.notchRect }
    var screenRect: CGRect { geometry.screen.frame }
    var hasHardwareNotch: Bool { geometry.hasHardwareNotch }
    /// Marge de survol et de clic : élargie de 4 pt autour d'une vraie encoche.
    var inset: CGFloat { hasHardwareNotch ? -4 : 0 }

    var metrics: ShellMetrics {
        presentation.metrics(notch: deviceNotchRect.size, hasHardwareNotch: hasHardwareNotch, scale: geometry.screen.scale)
    }

    var notchOpenedSize: CGSize { contentType.panelSize }

    var notchOpenedRect: CGRect {
        let size = notchOpenedSize
        return CGRect(x: deviceNotchRect.midX - size.width / 2, y: screenRect.maxY - size.height, width: size.width, height: size.height)
    }

    /// Rectangle de la coque dans son état courant.
    var currentShellRect: CGRect {
        let m = metrics
        return CGRect(x: deviceNotchRect.midX - m.bodyWidth / 2, y: screenRect.maxY - m.bodyHeight, width: m.bodyWidth, height: m.bodyHeight)
    }

    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    // ─── Widget pages ─────────────────────────────────────────────────────────
    //
    // The opened panel (in `.normal` content type) is divided into pages.
    // Each page hosts up to `maxWidgetsPerPage` widgets shown side-by-side.
    // The user picks which widgets land on which page from Settings.
    // Pages are navigated by swiping horizontally inside the panel.

    /// Hard limit per page so a 4-tile row stays readable on a notch panel.
    static let maxWidgetsPerPage = 4
    /// Hard limit on number of pages — the dot indicator goes from cramped
    /// to silly past this.
    static let maxPages = 5

    @PublishedPersist(key: "widgetPages", defaultValue: [[.airdrop, .files]])
    var widgetPages: [[Widget]]

    @Published var currentPage: Int = 0

    /// Convenience accessor — slot of widgets shown on the active page.
    /// Returns an empty array if `currentPage` ever drifts out of range
    /// (defensive — shouldn't happen with the bounds checks below).
    var currentWidgets: [Widget] {
        guard currentPage >= 0, currentPage < widgetPages.count else { return [] }
        return widgetPages[currentPage]
    }

    /// Toggle a widget on a given page: present → remove (and drop the page
    /// if it becomes empty and we have more than one); absent → append
    /// (capped at `maxWidgetsPerPage`).
    func toggleWidget(_ widget: Widget, onPage page: Int) {
        guard page >= 0, page < widgetPages.count else { return }
        if let idx = widgetPages[page].firstIndex(of: widget) {
            widgetPages[page].remove(at: idx)
            if widgetPages[page].isEmpty, widgetPages.count > 1 {
                widgetPages.remove(at: page)
                if currentPage >= widgetPages.count {
                    currentPage = max(0, widgetPages.count - 1)
                }
            }
        } else if widgetPages[page].count < Self.maxWidgetsPerPage {
            widgetPages[page].append(widget)
        }
    }

    /// Append an empty new page (no-op if already at `maxPages`).
    func addPage() {
        guard widgetPages.count < Self.maxPages else { return }
        widgetPages.append([])
        currentPage = widgetPages.count - 1
    }

    /// Remove a page by index. Refuses to delete the last page.
    func removePage(_ index: Int) {
        guard widgetPages.count > 1, index < widgetPages.count else { return }
        widgetPages.remove(at: index)
        if currentPage >= widgetPages.count {
            currentPage = max(0, widgetPages.count - 1)
        }
    }

    /// Page navigation — wraps around for symmetry with the dot indicator.
    func nextPage() {
        guard !widgetPages.isEmpty else { return }
        currentPage = (currentPage + 1) % widgetPages.count
    }

    func previousPage() {
        guard !widgetPages.isEmpty else { return }
        currentPage = (currentPage - 1 + widgetPages.count) % widgetPages.count
    }

    let hapticSender = PassthroughSubject<Void, Never>()

    // MARK: états

    /// Contenu du panneau ouvert. L'écrire hors de l'état ouvert est sans effet.
    var contentType: ContentType {
        get {
            if case let .opened(content) = presentation { return content }
            return .normal
        }
        set {
            guard presentation.isOpened else { return }
            transition(to: .opened(newValue))
        }
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
    }

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        if !isSuspendingActivities {
            isSuspendingActivities = true
            activities.beginSuspension()
        }
        transition(to: .opened(.normal))
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
