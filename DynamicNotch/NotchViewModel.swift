import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    let inset: CGFloat

    init(inset: CGFloat = -4) {
        self.inset = inset
        super.init()
        setupCancellables()
    }

    deinit {
        destroy()
    }

    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.25,
        blendDuration: 0.125
    )

    /// Logical size of the opened panel — varies per content type so dense
    /// views (Settings) can breathe without leaving the AirDrop+Tray layout
    /// uselessly large.
    ///
    /// Driven off `contentType` (a `@Published` property) so SwiftUI
    /// re-renders and animates the resize via the standard `vm.animation`
    /// spring already applied at the call sites.
    var notchOpenedSize: CGSize {
        switch contentType {
        // 180pt (au lieu de 160) donne 94pt par tuile widget après chrome.
        // C'est confortable pour TOUS les widgets : Pomodoro a un intrinsic
        // d'~82pt (ring + 3 boutons + texte), donc 94pt lui laisse de l'air,
        // et les widgets simples (Notes, Calendar) utilisent l'espace
        // sans avoir l'air vide.
        case .normal:   .init(width: 600, height: 180)
        case .menu:     .init(width: 600, height: 200)
        // Settings : 3 colonnes (Apparence/Comportement | Affichage/Stockage |
        // Pomodoro/Avancé) + section Widgets full-width en haut.
        case .settings: .init(width: 880, height: 560)
        }
    }

    let dropDetectorRange: CGFloat = 32

    enum Status: String, Codable, Hashable, Equatable {
        case closed
        case opened
        case popping
    }

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

    var notchOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notchOpenedSize.height,
            width: notchOpenedSize.width,
            height: notchOpenedSize.height
        )
    }

    var headlineOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - deviceNotchRect.height,
            width: notchOpenedSize.width,
            height: deviceNotchRect.height
        )
    }

    @Published private(set) var status: Status = .closed
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal

    @Published var spacing: CGFloat = 16
    @Published var cornerRadius: CGFloat = 16
    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    @Published var optionKeyPressed: Bool = false
    @Published var notchVisible: Bool = true

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

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        status = .opened
        contentType = .normal
        // Only steal focus when the user explicitly clicked the notch.
        // - On `.drag`, the user is interacting with another app (Finder, etc.) —
        //   activating ourselves would tear that drag down and is the worst
        //   possible UX for a menubar utility.
        // - On `.boot`, we'd grab focus on every launch / screen change — noisy.
        if reason == .click {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func notchClose() {
        openReason = .unknown
        status = .closed
        contentType = .normal
    }

    func showSettings() {
        contentType = .settings
    }

    func notchPop() {
        openReason = .unknown
        status = .popping
    }
}
