# Mouvement et panneau — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer le panneau à pages par cinq onglets logés autour de l'encoche, animer ouverture, fermeture et changement d'onglet façon Dynamic Island, et rendre les micro-interactions vivantes, sans dessiner de noir hors de l'encoche au repos.

**Architecture :** `NotchTab` et un `ContentType` à onglets remplacent les pages de widgets dans `NotchViewModel` ; une rangée d'en-tête (`NotchTopRow`) occupe la hauteur de l'encoche ; chaque onglet est une vue qui compose les modèles existants ; deux transitions (`emerge`, `tabSlide`) et trois composants (`DSModule`, `DSIconButton`, `DSTabBar`) portent le langage visuel.

**Tech Stack :** Swift 5 (mode 5), SwiftUI + AppKit, macOS 14 (SF Symbols effects), EventKit, XCTest.

**Spec :** `docs/superpowers/specs/2026-09-26-mouvement-et-panneau-design.md`

## Global Constraints

- Branche `refonte/mouvement-panneau`. Commits en français, préfixe conventionnel ; ligne `Co-Authored-By` selon le harnais de l'agent.
- Tout fichier Swift créé ou supprimé passe par `ruby Tools/xcproj.rb add <Cible> <fichiers…>` / `ruby Tools/xcproj.rb remove <fichiers…>`.
- Tests : `Tools/test.sh [Classe]`. Build : `Tools/build.sh [Debug|Release]`. Jamais sans `CODE_SIGNING_ALLOWED=NO` (les scripts s'en chargent).
- Swift 5, macOS 14. Si le compilateur signale un appel isolé au MainActor dans une closure `DispatchQueue.main.async/asyncAfter`, entourer l'appel de `MainActor.assumeIsolated { … }`.
- Coque : remplissage `Color.black` opaque ; ressorts de coque uniquement `DS.Motion.expand` / `collapse` / `micro`.
- Aucun zoom ni flou sur du texte **au repos** ; zoom et flou autorisés seulement dans les transitions d'apparition et de disparition.
- Typographie SF Pro ; rien sous 11 pt dans le panneau.
- Écran de référence des tests : encoche 185 × 32 pt, échelle 2 (`NotchGeometry.preview`).
- Onglets (ordre fixe) : Accueil `house.fill`, Fichiers `tray.full.fill`, Minuteurs `timer`, Notes `note.text`, Agenda `calendar`.
- Tailles de panneau : Accueil, Fichiers, Minuteurs 640 × 190 ; Notes 640 × 220 ; Agenda 640 × 260 ; Réglages 880 × 560.

**Écart assumé avec la spec (§1, changement d'onglet) :** le contenu sortant ne glisse pas, il s'efface en fondu avec un flou de 4 pt. Une vue retirée garde la transition de son dernier rendu ; un glissement « dans le sens opposé » partirait du mauvais côté à chaque inversion de direction. Le contenu entrant glisse bien de 24 pt dans le sens de la navigation.

---

### Task 1 : onglets dans le modèle (fin des pages)

**Files :**
- Create : `DynamicNotch/Shell/NotchTab.swift`, `DynamicNotchTests/NotchTabTests.swift`
- Modify : `DynamicNotch/NotchViewModel.swift`, `DynamicNotch/Shell/NotchPresentation.swift`, `DynamicNotch/NotchContentView.swift`, `DynamicNotch/NotchHeaderView.swift`, `DynamicNotch/NotchWindowController.swift:36-47`, `DynamicNotch/NotchSettingsView.swift`, `DynamicNotch/Debug/DebugTools.swift:65`, `DynamicNotchTests/NotchPresentationTests.swift`, `DynamicNotchTests/NotchViewModelTests.swift`
- Delete : `DynamicNotch/Widget.swift`

**Interfaces :**
- Produces :
  - `enum NotchTab: Int, CaseIterable, Codable, Identifiable { case home, files, timers, notes, agenda; var systemImage: String; var title: String; var panelHeight: CGFloat; static func slideEdge(from: NotchTab, to: NotchTab) -> Edge }`
  - `NotchViewModel.ContentType` : `enum ContentType: Hashable { case tab(NotchTab); case settings }`
  - `NotchViewModel` : `lastTab: NotchTab` (persisté, clé `lastTab`), `currentTab: NotchTab?`, `tabSlideEdge: Edge` (publié), `selectTab(_:)`, `closeSettings()` ; `notchOpen(.drag)` ouvre `.files`, les autres raisons ouvrent `lastTab`.
  - `ContentType.panelSize` selon le tableau des contraintes.
  - `NotchPresentation.metrics` : `closed` sans oreilles ; `peek` = même largeur, +3 pt de haut.
- Supprime : `Widget`, `widgetPages`, `currentPage`, `currentWidgets`, `toggleWidget`, `addPage`, `removePage`, `nextPage`, `previousPage`, `maxWidgetsPerPage`, `maxPages`, `ContentType.normal`, `ContentType.menu`.

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/NotchTabTests.swift` :
```swift
//
//  NotchTabTests.swift
//  DynamicNotchTests
//

import SwiftUI
import XCTest
@testable import DynamicNotch

final class NotchTabTests: XCTestCase {
    func test_order_andSymbols() {
        XCTAssertEqual(NotchTab.allCases, [.home, .files, .timers, .notes, .agenda])
        XCTAssertEqual(NotchTab.allCases.map(\.systemImage), ["house.fill", "tray.full.fill", "timer", "note.text", "calendar"])
    }

    func test_panelHeights() {
        XCTAssertEqual(NotchTab.home.panelHeight, 190)
        XCTAssertEqual(NotchTab.files.panelHeight, 190)
        XCTAssertEqual(NotchTab.timers.panelHeight, 190)
        XCTAssertEqual(NotchTab.notes.panelHeight, 220)
        XCTAssertEqual(NotchTab.agenda.panelHeight, 260)
    }

    func test_slideEdge_followsNavigationDirection() {
        XCTAssertEqual(NotchTab.slideEdge(from: .home, to: .agenda), .trailing)
        XCTAssertEqual(NotchTab.slideEdge(from: .agenda, to: .files), .leading)
        XCTAssertEqual(NotchTab.slideEdge(from: .notes, to: .notes), .trailing)
    }
}
```

Remplacer tout `DynamicNotchTests/NotchPresentationTests.swift` par :
```swift
//
//  NotchPresentationTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class NotchPresentationTests: XCTestCase {
    private let notch = CGSize(width: 185, height: 32)

    private func metrics(_ p: NotchPresentation, hardware: Bool = true) -> ShellMetrics {
        p.metrics(notch: hardware ? notch : CGSize(width: 190, height: 24), hasHardwareNotch: hardware, scale: 2)
    }

    /// Au repos, la coque épouse l'encoche : aucun pixel noir hors de l'encoche.
    func test_closed_isExactlyTheHardwareNotch() {
        XCTAssertEqual(metrics(.closed), ShellMetrics(bodyWidth: 185, bodyHeight: 32, topRadius: 0, bottomRadius: 10, hasShadow: false))
    }

    /// Le survol n'élargit plus : il allonge de 3 pt vers le bas.
    func test_peek_growsDownOnly() {
        XCTAssertEqual(metrics(.peek), ShellMetrics(bodyWidth: 185, bodyHeight: 35, topRadius: 0, bottomRadius: 10, hasShadow: false))
    }

    func test_compact_addsTwoEqualWings_withEars() {
        let m = metrics(.compact(.charging))
        XCTAssertEqual(m.bodyWidth, 185 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(m.bodyHeight, 32)
        XCTAssertEqual(m.topRadius, 6)
        XCTAssertFalse(m.hasShadow)
    }

    func test_expanded_and_opened() {
        XCTAssertEqual(metrics(.expanded(.charging)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.home))), ShellMetrics(bodyWidth: 640, bodyHeight: 190, topRadius: 10, bottomRadius: 28, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.notes))).bodyHeight, 220)
        XCTAssertEqual(metrics(.opened(.tab(.agenda))).bodyHeight, 260)
        XCTAssertEqual(metrics(.opened(.settings)).bodyWidth, 880)
    }

    func test_pill_states() {
        XCTAssertEqual(metrics(.closed, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12, hasShadow: false))
        XCTAssertEqual(metrics(.peek, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 27, topRadius: 0, bottomRadius: 13.5, hasShadow: false))

        let compact = metrics(.compact(.charging), hardware: false)
        XCTAssertEqual(compact.bodyWidth, 190 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(compact.topRadius, 0)
        XCTAssertEqual(compact.bottomRadius, 12)

        XCTAssertEqual(metrics(.expanded(.charging), hardware: false), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 0, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.tab(.home)), hardware: false), ShellMetrics(bodyWidth: 640, bodyHeight: 190, topRadius: 0, bottomRadius: 28, hasShadow: true))
    }

    func test_motion() {
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .peek), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .peek, to: .closed), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .opened(.tab(.home))), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .closed), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .expanded(.charging)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.charging), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.settings)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.settings), to: .opened(.tab(.home))), .collapse)
    }

    /// Entre deux onglets : on compare la surface du panneau.
    func test_motion_betweenTabs_comparesPanelArea() {
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.tab(.agenda))), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.agenda)), to: .opened(.tab(.home))), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.tab(.home)), to: .opened(.tab(.files))), .expand)
    }

    func test_motion_equalMagnitude_usesExpand() {
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .compact(.stopwatch)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.filesAdded(count: 2)), to: .expanded(.airDropSent)), .expand)
    }

    func test_wingWidth_fitsWidestValue_andIsPixelAligned() {
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .stopwatch), 36)
        let text = WingLayout.textWidth("100 %")
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .charging), text + 2 * WingLayout.padding)
        let total = WingLayout.wingsWidth(for: .charging, scale: 2)
        XCTAssertEqual(total * 2, (total * 2).rounded())
    }

    func test_expanded_growsWithTallNotch() {
        let tall = NotchPresentation.expanded(.charging).metrics(notch: CGSize(width: 200, height: 38), hasHardwareNotch: true, scale: 2)
        XCTAssertEqual(tall.bodyHeight, 86)
    }

    func test_stopwatchWing_fitsThreeDigitMinutes_andBatteryGlyph() {
        let text = WingLayout.textWidth("100:00")
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .stopwatch), text + 2 * WingLayout.padding)
        XCTAssertGreaterThanOrEqual(WingLayout.iconWidth, 25)
    }
}
```

Dans `DynamicNotchTests/NotchViewModelTests.swift` :
1. Dans `makeViewModel()`, fixer l'onglet mémorisé pour isoler les tests :
```swift
    private func makeViewModel() -> NotchViewModel {
        let vm = NotchViewModel(geometry: .preview, activities: center)
        vm.lastTab = .home
        return vm
    }
```
2. Remplacer les trois occurrences de `.opened(.normal)` par `.opened(.tab(.home))`.
3. Ajouter à la fin de la classe :
```swift
    // MARK: onglets

    func test_open_usesLastTab() {
        let vm = makeViewModel()
        vm.lastTab = .agenda
        vm.notchOpen(.boot)
        XCTAssertEqual(vm.presentation, .opened(.tab(.agenda)))
        vm.destroy()
    }

    func test_openByDrag_showsFiles_withoutChangingLastTab() {
        let vm = makeViewModel()
        vm.lastTab = .notes
        vm.notchOpen(.drag)
        XCTAssertEqual(vm.presentation, .opened(.tab(.files)))
        XCTAssertEqual(vm.lastTab, .notes)
        vm.destroy()
    }

    func test_selectTab_switches_andPersists() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        vm.selectTab(.timers)
        XCTAssertEqual(vm.presentation, .opened(.tab(.timers)))
        XCTAssertEqual(vm.lastTab, .timers)
        XCTAssertEqual(vm.currentTab, .timers)
        XCTAssertEqual(vm.tabSlideEdge, .trailing)
        vm.selectTab(.home)
        XCTAssertEqual(vm.tabSlideEdge, .leading)
        vm.destroy()
    }

    func test_selectTab_whenClosed_isIgnored() {
        let vm = makeViewModel()
        vm.selectTab(.agenda)
        XCTAssertEqual(vm.presentation, .closed)
        XCTAssertEqual(vm.lastTab, .home)
        vm.destroy()
    }

    func test_closeSettings_returnsToLastTab() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        vm.selectTab(.notes)
        vm.showSettings()
        XCTAssertNil(vm.currentTab)
        vm.closeSettings()
        XCTAssertEqual(vm.presentation, .opened(.tab(.notes)))
        vm.destroy()
    }
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/NotchTabTests.swift && Tools/test.sh NotchTabTests`
Expected : échec de compilation (`cannot find 'NotchTab' in scope`).

- [ ] **Step 2 : `NotchTab`**

`DynamicNotch/Shell/NotchTab.swift` :
```swift
//
//  NotchTab.swift
//  DynamicNotch
//
//  Onglets du panneau ouvert, dans l'ordre d'affichage de la barre.
//

import SwiftUI

enum NotchTab: Int, CaseIterable, Codable, Identifiable {
    case home, files, timers, notes, agenda

    var id: Int { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .files: "tray.full.fill"
        case .timers: "timer"
        case .notes: "note.text"
        case .agenda: "calendar"
        }
    }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .files: "Fichiers"
        case .timers: "Minuteurs"
        case .notes: "Notes"
        case .agenda: "Agenda"
        }
    }

    /// Hauteur du panneau (le corps de la coque) pour cet onglet.
    var panelHeight: CGFloat {
        switch self {
        case .home, .files, .timers: 190
        case .notes: 220
        case .agenda: 260
        }
    }

    /// Bord par lequel arrive le contenu quand on passe de `from` à `to` :
    /// depuis la droite si l'onglet visé est à droite (ou le même).
    static func slideEdge(from: NotchTab, to: NotchTab) -> Edge {
        to.rawValue >= from.rawValue ? .trailing : .leading
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Shell/NotchTab.swift`

- [ ] **Step 3 : tailles, métriques et ressorts**

Dans `DynamicNotch/Shell/NotchPresentation.swift` :

1. Dans `metrics(…)`, remplacer les cas `.closed` et `.peek` par :
```swift
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
```
2. Dans `magnitude`, remplacer `case let .opened(content): 40 + content.rawValue` par `case .opened: 40`.
3. Remplacer `motion(from:to:)` par :
```swift
    /// Ressort d'une transition : grandir rebondit, rétrécir non. Entre deux
    /// contenus ouverts, on compare la surface du panneau.
    static func motion(from: NotchPresentation, to: NotchPresentation) -> DS.Motion.Kind {
        if (from == .closed && to == .peek) || (from == .peek && to == .closed) { return .micro }
        if case let .opened(a) = from, case let .opened(b) = to {
            let areaA = a.panelSize.width * a.panelSize.height
            let areaB = b.panelSize.width * b.panelSize.height
            return areaB >= areaA ? .expand : .collapse
        }
        return to.magnitude >= from.magnitude ? .expand : .collapse
    }
```
4. Remplacer le corps de `panelSize` par :
```swift
        switch self {
        case let .tab(tab): CGSize(width: 640, height: tab.panelHeight)
        case .settings: CGSize(width: 880, height: 560)
        }
```

- [ ] **Step 4 : `NotchViewModel` à onglets**

Dans `DynamicNotch/NotchViewModel.swift` :

1. Remplacer `enum ContentType: Int, Codable, Hashable, Equatable { … }` par :
```swift
    enum ContentType: Hashable {
        case tab(NotchTab)
        case settings
    }
```
2. Supprimer tout le bloc des pages : du commentaire `// ─── Widget pages ───…` jusqu'à la fin de `func previousPage() { … }` inclus. À sa place, ajouter :
```swift
    /// Dernier onglet choisi, rouvert à chaque ouverture (sauf dépôt de fichier).
    @PublishedPersist(key: "lastTab", defaultValue: .home)
    var lastTab: NotchTab

    /// Bord par lequel arrive le contenu au prochain changement d'onglet.
    @Published private(set) var tabSlideEdge: Edge = .trailing
```
3. Remplacer le getter/setter `contentType` par :
```swift
    /// Contenu du panneau ouvert. L'écrire hors de l'état ouvert est sans effet.
    var contentType: ContentType {
        get {
            if case let .opened(content) = presentation { return content }
            return .tab(lastTab)
        }
        set {
            guard presentation.isOpened else { return }
            transition(to: .opened(newValue))
        }
    }

    /// Onglet affiché, `nil` hors onglets (fermé, réglages…).
    var currentTab: NotchTab? {
        if case let .opened(.tab(tab)) = presentation { return tab }
        return nil
    }

    /// Change d'onglet (panneau ouvert seulement) et le mémorise.
    func selectTab(_ tab: NotchTab) {
        guard presentation.isOpened else { return }
        tabSlideEdge = NotchTab.slideEdge(from: currentTab ?? lastTab, to: tab)
        lastTab = tab
        transition(to: .opened(.tab(tab)))
    }

    /// Quitte les réglages pour le dernier onglet.
    func closeSettings() {
        guard presentation == .opened(.settings) else { return }
        transition(to: .opened(.tab(lastTab)))
    }
```
4. Dans `notchOpen(_:)`, remplacer `transition(to: .opened(.normal))` par :
```swift
        // Un dépôt de fichier montre l'étagère ; sinon le dernier onglet.
        let tab: NotchTab = reason == .drag ? .files : lastTab
        transition(to: .opened(.tab(tab)))
```

- [ ] **Step 5 : appelants**

- Supprimer `Widget.swift` :
  ```bash
  ruby Tools/xcproj.rb remove DynamicNotch/Widget.swift && git rm -q DynamicNotch/Widget.swift
  ```
- Remplacer tout `DynamicNotch/NotchContentView.swift` par :
```swift
//
//  NotchContentView.swift
//  DynamicNotch
//
//  Corps du panneau ouvert : l'onglet courant ou les réglages.
//

import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        switch vm.contentType {
        case let .tab(tab):
            tabContent(tab)
        case .settings:
            NotchSettingsView(vm: vm)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: NotchTab) -> some View {
        switch tab {
        case .home:
            HStack(spacing: vm.spacing) {
                ShareView(vm: vm, type: .airdrop)
                TrayView(vm: vm)
            }
        case .files:
            TrayView(vm: vm)
        case .timers:
            HStack(spacing: vm.spacing) {
                StopwatchWidgetView(vm: vm)
                PomodoroWidgetView(vm: vm)
            }
        case .notes:
            NoteView(vm: vm)
        case .agenda:
            CalendarWidgetView(vm: vm)
        }
    }
}
```
  (Accueil et Agenda sont provisoires ; les tâches 5 et 6 les remplacent.)
- Dans `DynamicNotch/NotchHeaderView.swift` (provisoire, remplacé en tâche 3), remplacer le corps de la struct par :
```swift
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        DSNotchHeader(
            title: title,
            showsBack: vm.contentType == .settings,
            onBack: { vm.closeSettings() },
            pageNav: nil,
            onAction: handle(action:)
        )
    }

    private var title: LocalizedStringKey {
        switch vm.contentType {
        case let .tab(tab): LocalizedStringKey(tab.title)
        case .settings: "Réglages"
        }
    }

    private func handle(action: DSNotchHeader.Action) {
        switch action {
        case .menu:
            // Provisoire : onglet suivant (la barre d'onglets arrive en tâche 3).
            let next = NotchTab(rawValue: ((vm.currentTab ?? vm.lastTab).rawValue + 1) % NotchTab.allCases.count) ?? .home
            vm.selectTab(next)
        case .settings:
            vm.showSettings()
        case .close:
            vm.notchClose()
        }
    }
```
- `DynamicNotch/NotchWindowController.swift` : remplacer le `switch CommandLine.arguments[index + 1] { … }` par :
```swift
                let name = CommandLine.arguments[index + 1]
                if name == "settings" {
                    vm?.showSettings()
                } else if let tab = NotchTab.allCases.first(where: { "\($0)" == name }) {
                    vm?.selectTab(tab)
                }
```
  et mettre à jour son commentaire : `--initial-view settings|home|files|timers|notes|agenda`.
- `DynamicNotch/NotchSettingsView.swift` : supprimer la ligne `widgetsSection` du `body`, puis supprimer tout le bloc qui va de `    // MARK: widgets` jusqu'à la ligne qui précède le `    // MARK:` suivant (il contient `widgetsSection`, la ligne de pages et `widgetChip`). Vérifier : `grep -n "widget\|Widget" DynamicNotch/NotchSettingsView.swift` ne renvoie plus que des mentions sans rapport avec les pages (aucun appel à `vm.widgetPages`, `toggleWidget`, `addPage`, `removePage`).
- `DynamicNotch/Debug/DebugTools.swift` : remplacer `("opened", .opened(.normal)),` par `("opened", .opened(.tab(.home))),`.

- [ ] **Step 6 : tests, build, commit**

Run : `Tools/test.sh && Tools/build.sh`
Expected : `** TEST SUCCEEDED **` (dont NotchTabTests 3/3, NotchPresentationTests, NotchViewModelTests avec les 5 nouveaux tests), `** BUILD SUCCEEDED **`.
Vérifier : `grep -rn "widgetPages\|currentPage\|\.normal)\|\.menu)\|NotchViewModel.Widget" DynamicNotch DynamicNotchTests --include='*.swift'` → aucune sortie (hors la clé `"widgetPages"` de `DataMigration.swift`, conservée).

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: onglets du panneau à la place des pages de widgets"
```

---

### Task 2 : composants `DSModule`, `DSIconButton`, `DSTabBar`

**Files :**
- Modify : `DynamicNotch/DesignSystem/DSTokens.swift`, `DynamicNotch/DesignSystem/DSComponents.swift`
- Create : `DynamicNotch/DesignSystem/DSTabBar.swift`

**Interfaces :**
- Consumes : `NotchTab` (tâche 1).
- Produces :
  - `DS.Color.module` (gris `#1C1C1E`) ; `dsCard` remplit désormais avec `DS.Color.module`.
  - `DSModule<Content>(_ title: String? = nil, action: (() -> Void)? = nil, @ViewBuilder content:)` : carte rayon 16, padding 12 ; cliquable (survol 0,08, appui 0,14) si `action`.
  - `DSIconButton(_ systemImage: String, label: String, size: DSIconButton.Size = .regular, action:)` avec `Size.regular` (30 pt) / `.large` (36 pt) ; rebond du symbole à chaque action.
  - `DSTabBar(selection: NotchTab, onSelect: (NotchTab) -> Void)`.

Tâche visuelle : pas de test unitaire, le build et la suite existante font foi ; les composants sont utilisés dès la tâche 3.

- [ ] **Step 1 : token**

Dans `DSTokens.swift`, dans `enum Color`, après `hairline`, ajouter :
```swift
        /// Fond des modules du panneau (gris système sombre).
        public static let module = SwiftUI.Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)   // #1C1C1E
```
Dans `dsCard(radius:)`, remplacer `.fill(DS.Color.surfaceRaised)` par `.fill(DS.Color.module)`.

- [ ] **Step 2 : `DSModule` et `DSIconButton`**

Dans `DSComponents.swift`, juste avant `// MARK: - Press events helper`, ajouter :
```swift
// MARK: - DSModule

/// Module du panneau : carte gris sombre, rayon 16. Cliquable si `action`.
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

```

- [ ] **Step 3 : `DSTabBar`**

`DynamicNotch/DesignSystem/DSTabBar.swift` :
```swift
//
//  DSTabBar.swift
//  DynamicNotch
//
//  Barre d'onglets de la rangée de l'encoche : icônes 14 pt, pastille de
//  sélection qui glisse d'un onglet à l'autre, rebond à la sélection.
//

import SwiftUI

struct DSTabBar: View {
    let selection: NotchTab
    let onSelect: (NotchTab) -> Void

    @Namespace private var pill
    @State private var bounces: [NotchTab: Int] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    bounces[tab, default: 0] += 1
                    onSelect(tab)
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .symbolEffect(.bounce, value: bounces[tab, default: 0])
                        .foregroundStyle(tab == selection ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .frame(width: 30, height: 26)
                        .background {
                            if tab == selection {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "selection", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(tab.title))
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .animation(DS.Motion.micro, value: selection)
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/DesignSystem/DSTabBar.swift`

- [ ] **Step 4 : build, tests, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **` sans nouvel avertissement dans les fichiers touchés, `** TEST SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotch.xcodeproj
git commit -m "feat: composants DSModule, DSIconButton et DSTabBar"
```

---

### Task 3 : rangée de l'encoche (onglets, batterie, menu)

**Files :**
- Create : `DynamicNotch/Shell/NotchTopRow.swift`
- Modify : `DynamicNotch/NotchView.swift` (`openedPanel`), `DynamicNotch/Debug/DebugTools.swift`, `DynamicNotch/DesignSystem/DSComponents.swift`, `DynamicNotch/DesignSystem/DSGallery.swift`
- Delete : `DynamicNotch/NotchHeaderView.swift`, `DynamicNotch/NotchMenuView.swift`

**Interfaces :**
- Consumes : `DSTabBar`, `DSIconButton` (2) ; `NotchViewModel.selectTab/closeSettings/showSettings/contentType` (1) ; `BatteryMonitor.hasBattery/percent`.
- Produces : `NotchTopRow(vm:)` ; `enum NotchActions { static func confirmAndClearTray(_ vm: NotchViewModel); static func confirmAndQuit(_ vm: NotchViewModel) }`.
- Supprime : `NotchHeaderView`, `NotchMenuView`, `DebugActivityTile`, `DSNotchHeader`, `DSIconTile`, `DSCard`, `DSPill`, `DSDivider`.

- [ ] **Step 1 : `NotchTopRow`**

`DynamicNotch/Shell/NotchTopRow.swift` :
```swift
//
//  NotchTopRow.swift
//  DynamicNotch
//
//  Rangée du haut du panneau ouvert, à hauteur de l'encoche : les onglets à
//  gauche de l'encoche physique, la batterie et le menu « … » à droite.
//

import SwiftUI

struct NotchTopRow: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var battery = BatteryMonitor.shared

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            Color.clear
                .frame(width: vm.deviceNotchRect.width)
            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .frame(height: vm.deviceNotchRect.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch vm.contentType {
        case let .tab(tab):
            DSTabBar(selection: tab) { vm.selectTab($0) }
        case .settings:
            HStack(spacing: 6) {
                DSIconButton("chevron.left", label: "Retour") { vm.closeSettings() }
                Text("Réglages")
                    .font(DS.Typography.bodyEmphasis)
                    .foregroundStyle(DS.Color.textPrimary)
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 10) {
            if battery.hasBattery {
                Text("\(battery.percent) %")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
                    .contentTransition(.numericText(value: Double(battery.percent)))
                    .animation(DS.Motion.micro, value: battery.percent)
            }
            moreMenu
        }
    }

    /// Menu natif : réglages, vider les fichiers, quitter (+ simulation en Debug).
    private var moreMenu: some View {
        Menu {
            Button("Réglages…") { vm.showSettings() }
            Button("Vider les fichiers…") { NotchActions.confirmAndClearTray(vm) }
            #if DEBUG
                Menu("Simuler une activité") {
                    ForEach(ActivityID.samples.map(\.debugName), id: \.self) { name in
                        Button(name) {
                            vm.notchClose()
                            // Laisser le panneau se fermer : ouvert, il suspend les activités.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                MainActor.assumeIsolated { ActivitySimulator.run(name) }
                            }
                        }
                    }
                }
            #endif
            Divider()
            Button("Quitter DynamicNotch") { NotchActions.confirmAndQuit(vm) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Plus"))
        .accessibilityLabel(Text("Plus d'options"))
    }
}

/// Actions confirmées par une alerte (reprises de l'ancien menu de l'encoche).
@MainActor
enum NotchActions {
    static func confirmAndClearTray(_ vm: NotchViewModel) {
        let count = TrayDrop.shared.items.count
        guard count > 0 else {
            vm.notchClose()
            return
        }
        let title = "Vider tous les fichiers stockés ?"
        let message = "\(count) fichier(s) seront supprimés de DynamicNotch. Vos originaux sur le disque ne sont pas affectés."
        if NSAlert.popConfirm(title: title, message: message, confirm: "Vider", destructive: true) {
            TrayDrop.shared.removeAll()
        }
        vm.notchClose()
    }

    static func confirmAndQuit(_ vm: NotchViewModel) {
        let title = "Quitter DynamicNotch ?"
        let message = "L'encoche cessera de répondre jusqu'à ce que vous relanciez DynamicNotch."
        guard NSAlert.popConfirm(title: title, message: message, confirm: "Quitter", destructive: true) else { return }
        vm.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2 : brancher la rangée dans `NotchView`**

Dans `DynamicNotch/NotchView.swift`, remplacer `openedPanel` par :
```swift
    private var openedPanel: some View {
        VStack(spacing: 0) {
            NotchTopRow(vm: vm)
            NotchContentView(vm: vm)
                .padding(.horizontal, vm.spacing)
                .padding(.top, 8)
                .padding(.bottom, vm.spacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
```

- [ ] **Step 3 : supprimer l'ancien en-tête, l'ancien menu et les composants morts**

```bash
ruby Tools/xcproj.rb remove DynamicNotch/NotchHeaderView.swift DynamicNotch/NotchMenuView.swift
git rm -q DynamicNotch/NotchHeaderView.swift DynamicNotch/NotchMenuView.swift
python3 - <<'EOF'
p = 'DynamicNotch/DesignSystem/DSComponents.swift'
s = open(p).read()
for name in ['DSIconTile', 'DSCard', 'DSPill', 'DSDivider', 'DSNotchHeader']:
    start = s.index(f'// MARK: - {name}\n')
    end = s.index('// MARK: - ', start + 10)
    s = s[:start] + s[end:]
open(p, 'w').write(s)
EOF
```
Dans `DynamicNotch/Debug/DebugTools.swift`, supprimer la struct `DebugActivityTile` entière (elle vivait dans l'ancien menu ; la simulation est maintenant dans le menu « … »).

Dans `DynamicNotch/DesignSystem/DSGallery.swift` :
- supprimer les lignes `section("Icon Tiles") { iconTilesSection }` et `section("Notch Header") { notchHeaderSection }` ;
- supprimer les propriétés `iconTilesSection` et `notchHeaderSection` entières ;
- dans `badgesPillsSection`, supprimer le second `HStack` (les cinq `DSPill`) ;
- dans `cardsDropZoneSection`, supprimer le bloc `DSCard { … }.frame(width: 220)` ;
- renommer la section `"Cards & Drop Zone"` en `"Drop Zone"` et `"Badges & Pills"` en `"Badges"`.

Vérifier : `grep -rn "DSIconTile\|DSCard\b\|DSPill\|DSDivider\|DSNotchHeader\|NotchHeaderView\|NotchMenuView\|DebugActivityTile" DynamicNotch --include='*.swift'` → aucune sortie.

- [ ] **Step 4 : build, tests, rendu, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.
Run :
```bash
Tools/build.sh Debug
OUT="$TMPDIR/notch-states" && rm -rf "$OUT"
build/Build/Products/Debug/DynamicNotch.app/Contents/MacOS/DynamicNotch --render-states "$OUT"
```
Ouvrir `opened.png` : les 5 icônes à gauche de l'encoche avec la pastille sur la maison, le pourcentage et « … » à droite, plus de titre ni de flèches.

```bash
git add -A DynamicNotch DynamicNotch.xcodeproj
git commit -m "feat: rangée de l'encoche avec onglets, batterie et menu natif"
```

---

### Task 4 : mouvement (émergence, glissement d'onglet, haptique)

**Files :**
- Create : `DynamicNotch/DesignSystem/DSTransitions.swift`
- Modify : `DynamicNotch/DesignSystem/DSTokens.swift`, `DynamicNotch/NotchView.swift`, `DynamicNotch/NotchContentView.swift`, `DynamicNotch/NotchViewModel.swift` (`selectTab`)

**Interfaces :**
- Consumes : `NotchViewModel.tabSlideEdge`, `currentTab`, `hapticSender` (1).
- Produces : `DS.Motion.emergeIn`, `DS.Motion.emergeOut` ; `AnyTransition.emerge`, `AnyTransition.tabSlide(from: Edge)`.

- [ ] **Step 1 : test qui échoue**

Ajouter à `DynamicNotchTests/NotchViewModelTests.swift` :
```swift
    func test_selectTab_sendsHaptic_onlyWhenTabChanges() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        var haptics = 0
        let observation = vm.hapticSender.sink { haptics += 1 }
        vm.selectTab(.agenda)
        vm.selectTab(.agenda)
        XCTAssertEqual(haptics, 1)
        observation.cancel()
        vm.destroy()
    }
```
Run : `Tools/test.sh NotchViewModelTests` → échec (`haptics` vaut 0).

- [ ] **Step 2 : haptique au changement d'onglet**

Dans `NotchViewModel.selectTab(_:)`, remplacer le corps par :
```swift
        guard presentation.isOpened else { return }
        let from = currentTab ?? lastTab
        tabSlideEdge = NotchTab.slideEdge(from: from, to: tab)
        lastTab = tab
        if from != tab || currentTab == nil { hapticSender.send() }
        transition(to: .opened(.tab(tab)))
```
Run : `Tools/test.sh NotchViewModelTests` → tous verts (`test_selectTab_switches_andPersists` inclus).

- [ ] **Step 3 : courbes et transitions**

Dans `DSTokens.swift`, à la fin de `enum Motion` (avant son accolade fermante), ajouter :
```swift

        // ─── Contenu ──────────────────────────────────────────────────────
        /// Entrée du contenu qui émerge de l'encoche.
        public static let emergeIn = Animation.spring(response: 0.38, dampingFraction: 0.82).delay(0.03)
        /// Sortie : rétraction rapide vers l'encoche.
        public static let emergeOut = Animation.easeIn(duration: 0.18)
```

`DynamicNotch/DesignSystem/DSTransitions.swift` :
```swift
//
//  DSTransitions.swift
//  DynamicNotch
//
//  Transitions du contenu de l'encoche. Zoom et flou n'existent que pendant
//  la transition : à l'état identité (repos), zoom = 1 et flou = 0.
//

import SwiftUI

private struct EmergeEffect: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
    }
}

private struct SlideEffect: ViewModifier {
    let opacity: Double
    let offsetX: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: offsetX)
            .blur(radius: blur)
    }
}

extension AnyTransition {
    /// Le contenu émerge de l'encoche (fondu, zoom 0,92 → 1 ancré en haut,
    /// flou 6 → 0) et s'y rétracte à la sortie.
    static var emerge: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: EmergeEffect(opacity: 0, scale: 0.92, blur: 6),
                identity: EmergeEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(DS.Motion.emergeIn),
            removal: .modifier(
                active: EmergeEffect(opacity: 0, scale: 0.95, blur: 4),
                identity: EmergeEffect(opacity: 1, scale: 1, blur: 0)
            ).animation(DS.Motion.emergeOut)
        )
    }

    /// Changement d'onglet : l'entrant glisse de 24 pt depuis `edge` ;
    /// le sortant s'efface (fondu + flou), sans glisser.
    static func tabSlide(from edge: Edge) -> AnyTransition {
        let offset: CGFloat = edge == .trailing ? 24 : -24
        return .asymmetric(
            insertion: .modifier(
                active: SlideEffect(opacity: 0, offsetX: offset, blur: 4),
                identity: SlideEffect(opacity: 1, offsetX: 0, blur: 0)
            ).animation(DS.Motion.expand),
            removal: .modifier(
                active: SlideEffect(opacity: 0, offsetX: 0, blur: 4),
                identity: SlideEffect(opacity: 1, offsetX: 0, blur: 0)
            ).animation(.easeIn(duration: 0.15))
        )
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/DesignSystem/DSTransitions.swift`

- [ ] **Step 4 : appliquer**

Dans `DynamicNotch/NotchView.swift` : supprimer la propriété statique `contentTransition` (et son commentaire) et remplacer ses trois usages `.transition(Self.contentTransition)` par `.transition(.emerge)`.

Dans `DynamicNotch/NotchContentView.swift`, remplacer `case let .tab(tab): tabContent(tab)` par :
```swift
        case let .tab(tab):
            tabContent(tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(tab)
                .transition(.tabSlide(from: vm.tabSlideEdge))
```
et `case .settings: NotchSettingsView(vm: vm)` par :
```swift
        case .settings:
            NotchSettingsView(vm: vm)
                .transition(.emerge)
```

- [ ] **Step 5 : tests, build, commit**

Run : `Tools/test.sh && Tools/build.sh` → `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.
Vérifier : `grep -n "contentTransition" DynamicNotch/NotchView.swift` → aucune sortie.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: contenu qui émerge de l'encoche et glissement entre onglets"
```

---

### Task 5 : onglets Accueil et Agenda

**Files :**
- Create : `DynamicNotch/Widgets/AgendaPlanner.swift`, `DynamicNotch/Tabs/HomeTabView.swift`, `DynamicNotch/Tabs/AgendaTabView.swift`, `DynamicNotchTests/AgendaPlannerTests.swift`
- Modify : `DynamicNotch/Widgets/CalendarWidget.swift` (store ; suppression de `CalendarWidgetView`), `DynamicNotch/Share+View.swift`, `DynamicNotch/NotchContentView.swift`

**Interfaces :**
- Consumes : `DSModule`, `DSIconButton` (2) ; `NotchViewModel.selectTab`, `hapticSender` (1) ; `TrayDrop.shared.items/load`, `DropItem.workspacePreviewImage` ; `StopwatchModel.running/toggle()` ; `PomodoroModel.isRunning/performPrimary()`.
- Produces :
  - `struct AgendaEntry: Equatable, Identifiable { let id: String; let title: String; let start: Date; let end: Date; let isAllDay: Bool; let color: NSColor? }`
  - `enum AgendaPlanner { static func split(_:now:calendar:) -> (today: [AgendaEntry], tomorrow: [AgendaEntry]); static func upcoming(_:now:limit:) -> [AgendaEntry] }`
  - `enum AgendaAccess { case granted, notDetermined, denied }` ; `CalendarStore` : `@Published access`, `todayEvents`, `tomorrowEvents`, `refreshAccess()`, `requestAccess()`, `static func access(for: EKAuthorizationStatus) -> AgendaAccess`
  - `ShareView.pickFilesAndSend(_ type: ShareType, vm: NotchViewModel)`
  - `HomeTabView(vm:)`, `AgendaTabView()`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/AgendaPlannerTests.swift` :
```swift
//
//  AgendaPlannerTests.swift
//  DynamicNotchTests
//

import EventKit
import XCTest
@testable import DynamicNotch

final class AgendaPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// Vendredi 26 septembre 2026, 10:00 (Paris).
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10))! }

    private func entry(_ id: String, day: Int, hour: Int, minutes: Int = 60, allDay: Bool = false) -> AgendaEntry {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        return AgendaEntry(id: id, title: id, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay, color: nil)
    }

    func test_split_sortsTodayAndTomorrow_allDayFirst() {
        let entries = [
            entry("demain", day: 27, hour: 9),
            entry("midi", day: 26, hour: 12),
            entry("matin", day: 26, hour: 8),
            entry("journée", day: 26, hour: 0, minutes: 24 * 60, allDay: true),
            entry("hier", day: 25, hour: 18),
        ]
        let split = AgendaPlanner.split(entries, now: now, calendar: calendar)
        XCTAssertEqual(split.today.map(\.id), ["journée", "matin", "midi"])
        XCTAssertEqual(split.tomorrow.map(\.id), ["demain"])
    }

    func test_upcoming_skipsEndedAndAllDay_andLimits() {
        let today = [
            entry("journée", day: 26, hour: 0, minutes: 24 * 60, allDay: true),
            entry("fini", day: 26, hour: 8),
            entry("en cours", day: 26, hour: 9, minutes: 90),
            entry("midi", day: 26, hour: 12),
            entry("soir", day: 26, hour: 18),
        ]
        XCTAssertEqual(AgendaPlanner.upcoming(today, now: now, limit: 2).map(\.id), ["en cours", "midi"])
    }

    func test_accessMapping() {
        XCTAssertEqual(CalendarStore.access(for: .fullAccess), .granted)
        XCTAssertEqual(CalendarStore.access(for: .notDetermined), .notDetermined)
        XCTAssertEqual(CalendarStore.access(for: .denied), .denied)
        XCTAssertEqual(CalendarStore.access(for: .restricted), .denied)
        XCTAssertEqual(CalendarStore.access(for: .writeOnly), .denied)
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/AgendaPlannerTests.swift && Tools/test.sh AgendaPlannerTests` → échec de compilation (`cannot find 'AgendaEntry'`).

- [ ] **Step 2 : `AgendaPlanner`**

`DynamicNotch/Widgets/AgendaPlanner.swift` :
```swift
//
//  AgendaPlanner.swift
//  DynamicNotch
//
//  Tri et filtrage des événements du jour et du lendemain. Fonctions pures,
//  indépendantes d'EventKit pour être testables.
//

import AppKit

struct AgendaEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor?
}

enum AgendaPlanner {
    /// Événements du jour de `now` et du lendemain ; « journée entière » d'abord, puis par heure.
    static func split(_ entries: [AgendaEntry], now: Date, calendar: Calendar = .current) -> (today: [AgendaEntry], tomorrow: [AgendaEntry]) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfAfter = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow)!
        let today = entries.filter { $0.start < startOfTomorrow && $0.end > startOfToday }
        let tomorrow = entries.filter { $0.start < startOfAfter && $0.end > startOfTomorrow && $0.start >= startOfTomorrow }
        return (sorted(today), sorted(tomorrow))
    }

    /// Prochains événements horaires pas encore terminés.
    static func upcoming(_ today: [AgendaEntry], now: Date, limit: Int) -> [AgendaEntry] {
        Array(today.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }.prefix(limit))
    }

    private static func sorted(_ entries: [AgendaEntry]) -> [AgendaEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start < rhs.start
        }
    }
}
```

- [ ] **Step 3 : `CalendarStore` étendu**

Dans `DynamicNotch/Widgets/CalendarWidget.swift` :
1. Avant `@MainActor final class CalendarStore`, ajouter :
```swift
enum AgendaAccess: Equatable {
    case granted, notDetermined, denied
}
```
2. Dans `CalendarStore`, après `@Published var authorizationDenied: Bool = false`, ajouter :
```swift
    @Published private(set) var access: AgendaAccess = CalendarStore.access(for: EKEventStore.authorizationStatus(for: .event))
    @Published private(set) var todayEvents: [AgendaEntry] = []
    @Published private(set) var tomorrowEvents: [AgendaEntry] = []

    static func access(for status: EKAuthorizationStatus) -> AgendaAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Relit l'autorisation ; si l'accès est accordé, lance le suivi (sans invite).
    func refreshAccess() {
        access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        if access == .granted, refreshTimer == nil { startObserving() }
    }

    /// Demande l'accès (invite système), puis relit l'autorisation.
    func requestAccess() {
        Task {
            await requestAndRefresh()
            refreshAccess()
        }
    }
```
3. À la fin de `refresh()`, ajouter :
```swift
        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday)!
        let dayPredicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        let entries = store.events(matching: dayPredicate).map { event in
            AgendaEntry(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Sans titre",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: event.calendar?.color
            )
        }
        let split = AgendaPlanner.split(entries, now: now)
        todayEvents = split.today
        tomorrowEvents = split.tomorrow
```
4. Supprimer toute la struct `CalendarWidgetView` (remplacée par les onglets).

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Widgets/AgendaPlanner.swift && Tools/test.sh AgendaPlannerTests` → 3/3 verts.

- [ ] **Step 4 : AirDrop réutilisable**

Dans `DynamicNotch/Share+View.swift`, ajouter en fin de fichier :
```swift
extension ShareView {
    /// Ferme l'encoche, puis ouvre le sélecteur de fichiers et envoie avec `type`.
    static func pickFilesAndSend(_ type: ShareType, vm: NotchViewModel) {
        vm.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated {
                let picker = NSOpenPanel()
                picker.allowsMultipleSelection = true
                picker.canChooseDirectories = true
                picker.canChooseFiles = true
                picker.begin { response in
                    if response == .OK {
                        type.service(picker.urls).begin()
                    }
                }
            }
        }
    }
}
```
et remplacer le corps de `handleTap()` par :
```swift
        trigger = .init()
        Self.pickFilesAndSend(type, vm: vm)
```

- [ ] **Step 5 : onglet Accueil**

`DynamicNotch/Tabs/HomeTabView.swift` :
```swift
//
//  HomeTabView.swift
//  DynamicNotch
//
//  Accueil : aujourd'hui (date + deux prochains événements), fichiers
//  récents (zone de dépôt) et quatre actions rapides.
//

import SwiftUI

struct HomeTabView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var calendar = CalendarStore.shared
    @ObservedObject private var tray = TrayDrop.shared
    @ObservedObject private var stopwatch = StopwatchModel.shared
    @ObservedObject private var pomodoro = PomodoroModel.shared
    @State private var filesTargeted = false

    /// Largeur utile (640 − 2 × 16) moins deux espacements de 10, en 3,2 parts.
    private let unit: CGFloat = (640 - 32 - 20) / 3.2

    var body: some View {
        HStack(spacing: 10) {
            todayModule.frame(width: unit * 1.2)
            filesModule.frame(width: unit)
            actionsModule.frame(width: unit)
        }
        .onAppear { calendar.refreshAccess() }
    }

    // MARK: aujourd'hui

    private var todayModule: some View {
        DSModule(
            Date().formatted(.dateTime.weekday(.wide)).capitalized,
            action: calendar.access == .granted ? { vm.selectTab(.agenda) } : nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(DS.Typography.displayMedium)
                    .foregroundStyle(DS.Color.textPrimary)
                todayDetail
            }
        }
    }

    @ViewBuilder
    private var todayDetail: some View {
        switch calendar.access {
        case .granted:
            let upcoming = AgendaPlanner.upcoming(calendar.todayEvents, now: Date(), limit: 2)
            if upcoming.isEmpty {
                Text("Rien de prévu")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            ForEach(upcoming) { entry in
                HStack(spacing: 6) {
                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(entry.title)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                .font(DS.Typography.caption)
            }
        case .notDetermined:
            Button("Autoriser l'agenda") { calendar.requestAccess() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.brand)
        case .denied:
            Button("Autoriser dans Réglages Système") { openCalendarPrivacy() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.brand)
        }
    }

    // MARK: fichiers

    private var filesModule: some View {
        DSModule("Fichiers", action: { vm.selectTab(.files) }) {
            VStack(alignment: .leading, spacing: 8) {
                if tray.items.isEmpty {
                    Text("Glissez des fichiers ici")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(tray.items.prefix(3))) { item in
                            Image(nsImage: item.workspacePreviewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        if tray.items.count > 3 {
                            Text("+\(tray.items.count - 3)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    Text("\(tray.items.count) fichier(s)")
                        .font(DS.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                        .contentTransition(.numericText(value: Double(tray.items.count)))
                        .animation(DS.Motion.micro, value: tray.items.count)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(filesTargeted ? 0.35 : 0), lineWidth: 1)
        )
        .animation(DS.Motion.micro, value: filesTargeted)
        .onDrop(of: [.data], isTargeted: $filesTargeted) { providers in
            vm.hapticSender.send()
            DispatchQueue.global().async { TrayDrop.shared.load(providers) }
            return true
        }
    }

    // MARK: actions

    private var actionsModule: some View {
        DSModule {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    action("dot.radiowaves.up.forward", "AirDrop") {
                        ShareView.pickFilesAndSend(.airdrop, vm: vm)
                    }
                    action(stopwatch.running ? "pause.fill" : "stopwatch", "Chrono") {
                        if !stopwatch.running { vm.hapticSender.send() }
                        stopwatch.toggle()
                    }
                }
                GridRow {
                    action(pomodoro.isRunning ? "pause.fill" : "brain.head.profile", "Pomodoro") {
                        if !pomodoro.isRunning { vm.hapticSender.send() }
                        pomodoro.performPrimary()
                    }
                    action("square.and.pencil", "Note") { vm.selectTab(.notes) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func action(_ systemImage: String, _ title: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 3) {
            DSIconButton(systemImage, label: title, size: .large, action: perform)
            Text(title)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
        }
    }

    private func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 6 : onglet Agenda**

`DynamicNotch/Tabs/AgendaTabView.swift` :
```swift
//
//  AgendaTabView.swift
//  DynamicNotch
//
//  La journée : événements du jour (ou de demain si la journée est vide).
//

import SwiftUI

struct AgendaTabView: View {
    @ObservedObject private var calendar = CalendarStore.shared

    var body: some View {
        DSModule {
            switch calendar.access {
            case .granted:
                list
            case .notDetermined:
                prompt("Autoriser l'agenda") { calendar.requestAccess() }
            case .denied:
                prompt("Autoriser dans Réglages Système") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onAppear { calendar.refreshAccess() }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if !calendar.todayEvents.isEmpty {
                    section("Aujourd'hui", calendar.todayEvents)
                } else if !calendar.tomorrowEvents.isEmpty {
                    section("Demain", calendar.tomorrowEvents)
                } else {
                    Text("Rien de prévu aujourd'hui ni demain")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, _ entries: [AgendaEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(nsColor: entry.color ?? .systemBlue))
                        .frame(width: 8, height: 8)
                    Text(entry.isAllDay ? "Journée" : "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 104, alignment: .leading)
                    Text(entry.title)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                }
                .font(DS.Typography.body)
            }
        }
    }

    private func prompt(_ title: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(DS.Color.textSecondary)
            Button(title, action: perform)
                .buttonStyle(.plain)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.brand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 7 : brancher, build, tests, commit**

Dans `NotchContentView.tabContent`, remplacer le cas `.home` (le `HStack` provisoire) par `HomeTabView(vm: vm)` et le cas `.agenda` par `AgendaTabView()`.

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Tabs/HomeTabView.swift DynamicNotch/Tabs/AgendaTabView.swift
Tools/test.sh && Tools/build.sh
```
Expected : `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. Vérifier `grep -rn "CalendarWidgetView" DynamicNotch` → aucune sortie.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: onglets Accueil et Agenda"
```

---

### Task 6 : onglets Fichiers, Minuteurs et Notes

**Files :**
- Create : `DynamicNotch/Tabs/FilesTabView.swift`, `DynamicNotch/Tabs/TimersTabView.swift`, `DynamicNotchTests/PomodoroProgressTests.swift`
- Modify : `DynamicNotch/Widgets/PomodoroWidget.swift`, `DynamicNotch/Widgets/StopwatchWidget.swift`, `DynamicNotch/Widgets/NoteWidget.swift`, `DynamicNotch/NotchContentView.swift`

**Interfaces :**
- Consumes : `DSModule` (2), `vm.hapticSender`.
- Produces : `PomodoroModel.progress(at: Date) -> Double` ; `FilesTabView(vm:)`, `TimersTabView(vm:)`.

- [ ] **Step 1 : test qui échoue**

`DynamicNotchTests/PomodoroProgressTests.swift` :
```swift
//
//  PomodoroProgressTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class PomodoroProgressTests: XCTestCase {
    func test_progress_isContinuousWhileRunning() {
        let model = PomodoroModel()
        XCTAssertEqual(model.progress(at: Date()), 0)
        model.performPrimary()
        let total = model.phaseTotal
        let later = Date().addingTimeInterval(total / 4)
        XCTAssertEqual(model.progress(at: later), 0.25, accuracy: 0.01)
        model.reset()
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/PomodoroProgressTests.swift && Tools/test.sh PomodoroProgressTests` → échec de compilation (`progress(at:)` inconnu).

- [ ] **Step 2 : progression continue du Pomodoro**

Dans `PomodoroModel`, après la propriété `progress`, ajouter :
```swift
    /// Progression de la phase à `date`, continue entre deux ticks.
    func progress(at date: Date) -> Double {
        guard phaseTotal > 0, phase != .idle else { return 0 }
        let left: TimeInterval
        if isRunning, let end = phaseEndDate {
            left = max(0, end.timeIntervalSince(date))
        } else {
            left = remaining
        }
        return min(1, max(0, 1 - left / phaseTotal))
    }
```
Dans `PomodoroWidgetView.ringWithTime`, remplacer le second `Circle()` (celui avec `.trim` et `.animation(.linear(duration: 0.5), …)`) par :
```swift
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isRunning)) { context in
                Circle()
                    .trim(from: 0, to: model.progress(at: context.date))
                    .stroke(model.phase.tint, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
```
et remplacer, dans le même `ZStack`, la police du temps `.font(.system(size: 17, weight: .semibold))` par `.font(DS.Typography.title)`, puis ajouter après `.monospacedDigit()` :
```swift
                .contentTransition(.numericText(countsDown: true))
                .animation(DS.Motion.micro, value: timeDisplayed)
```
Dans `circleBtn` du Pomodoro, ajouter `.contentTransition(.symbolEffect(.replace))` à l'`Image`.

Run : `Tools/test.sh PomodoroProgressTests` → vert.

- [ ] **Step 3 : chrono et note**

Dans `StopwatchWidgetView` : remplacer `.font(.system(size: 24, weight: .semibold))` par `.font(DS.Typography.displayLarge)` ; dans `circleBtn`, ajouter `.contentTransition(.symbolEffect(.replace))` à l'`Image` ; remplacer l'action du bouton lecture/pause `{ model.toggle() }` par `{ if !model.running { vm.hapticSender.send() }; model.toggle() }`.
Dans `PomodoroWidgetView.controls`, remplacer l'action du bouton principal `model.performPrimary()` par :
```swift
                if !model.isRunning { vm.hapticSender.send() }
                model.performPrimary()
```
Dans `NoteView` : remplacer `.font(.system(size: 11))` (l'éditeur) par `.font(DS.Typography.body)`.

- [ ] **Step 4 : onglets**

`DynamicNotch/Tabs/FilesTabView.swift` :
```swift
//
//  FilesTabView.swift
//  DynamicNotch
//
//  L'étagère de fichiers en grand, avec la zone AirDrop à gauche.
//

import SwiftUI

struct FilesTabView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            ShareView(vm: vm, type: .airdrop)
                .frame(width: 120)
            TrayView(vm: vm)
        }
    }
}
```

`DynamicNotch/Tabs/TimersTabView.swift` :
```swift
//
//  TimersTabView.swift
//  DynamicNotch
//
//  Chrono et Pomodoro côte à côte.
//

import SwiftUI

struct TimersTabView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            StopwatchWidgetView(vm: vm)
            PomodoroWidgetView(vm: vm)
        }
    }
}
```

Dans `NotchContentView.tabContent`, remplacer les cas `.files`, `.timers` et `.notes` par :
```swift
        case .files:
            FilesTabView(vm: vm)
        case .timers:
            TimersTabView(vm: vm)
        case .notes:
            NoteView(vm: vm)
```

- [ ] **Step 5 : build, tests, commit**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Tabs/FilesTabView.swift DynamicNotch/Tabs/TimersTabView.swift
Tools/test.sh && Tools/build.sh
```
Expected : `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: onglets Fichiers, Minuteurs et Notes"
```

---

### Task 7 : micro-interactions (chiffres, symboles, dépôts, fichiers)

**Files :**
- Modify : `DynamicNotch/Shell/ActivityViews.swift`, `DynamicNotch/Shell/BatteryGlyph.swift`, `DynamicNotch/Share.swift`, `DynamicNotch/Share+View.swift`, `DynamicNotch/DesignSystem/DSComponents.swift` (`DSDropZone`), `DynamicNotch/TrayDrop+View.swift`, `DynamicNotch/TrayDrop.swift` (`load`), `DynamicNotch/TrayDrop+DropItemView.swift`
- Test : `DynamicNotchTests/ShareActivityTests.swift` (create)

**Interfaces :**
- Produces : `final class ShareActivity: ObservableObject { static let shared; @Published private(set) var isSending: Bool; func begin(); func end() }` ; `BatteryGlyph(…, pulsesBolt: Bool = false)`.

- [ ] **Step 1 : test qui échoue**

`DynamicNotchTests/ShareActivityTests.swift` :
```swift
//
//  ShareActivityTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class ShareActivityTests: XCTestCase {
    func test_sendingState_isBalanced() {
        let activity = ShareActivity()
        XCTAssertFalse(activity.isSending)
        activity.begin()
        activity.begin()
        XCTAssertTrue(activity.isSending)
        activity.end()
        XCTAssertTrue(activity.isSending)
        activity.end()
        activity.end()
        XCTAssertFalse(activity.isSending)
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/ShareActivityTests.swift && Tools/test.sh ShareActivityTests` → échec de compilation.

- [ ] **Step 2 : état d'envoi AirDrop**

Dans `DynamicNotch/Share.swift`, avant `class Share`, ajouter :
```swift
/// Envois AirDrop en cours (pour animer l'icône pendant l'envoi).
final class ShareActivity: ObservableObject {
    static let shared = ShareActivity()

    @Published private(set) var isSending = false
    private var count = 0

    func begin() {
        count += 1
        isSending = true
    }

    func end() {
        count = max(0, count - 1)
        isSending = count > 0
    }
}
```
Dans `Share` : dans `begin()`, après `Share.inFlight.insert(self)`, ajouter `if serviceName == .sendViaAirDrop { ShareActivity.shared.begin() }` ; dans le `catch` de `begin()` et dans les deux méthodes `sharingService(_:didShareItems:)` / `sharingService(_:didFailToShareItems:error:)`, ajouter `if serviceName == .sendViaAirDrop { ShareActivity.shared.end() }`.

Run : `Tools/test.sh ShareActivityTests` → vert.

Dans `ShareView` : ajouter `@ObservedObject private var shareActivity = ShareActivity.shared` et, sur l'`Image(systemName: type.imageName)` de `iconBubble`, ajouter :
```swift
                .symbolEffect(.variableColor.iterative, isActive: shareActivity.isSending)
                .symbolEffect(.bounce, value: targeting)
```

- [ ] **Step 3 : chiffres animés et éclair qui pulse**

Dans `DynamicNotch/Shell/ActivityViews.swift` :
- `BatteryActivity.percent` : ajouter `.animation(DS.Motion.micro, value: battery.percent)` après la `contentTransition` ;
- `PomodoroActivity.remaining` : ajouter `.animation(DS.Motion.micro, value: model.formatted)` ;
- `StopwatchActivity.time` : remplacer par
```swift
    @ViewBuilder
    private var time: some View {
        if let startedAt = model.startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                label(model.elapsed(at: context.date))
            }
        } else {
            label(model.elapsed(at: Date()))
        }
    }

    private func label(_ elapsed: TimeInterval) -> some View {
        let text = StopwatchModel.minutesSeconds(elapsed)
        return Text(text)
            .contentTransition(.numericText())
            .animation(DS.Motion.micro, value: text)
    }
```
- `CalendarActivity.countdown` : ajouter `.contentTransition(.numericText(countsDown: true))` et `.animation(DS.Motion.micro, value: minutes)` au `Text` ;
- dans `BatteryActivity.glyph(width:)`, passer `pulsesBolt: place == .expanded && id == .charging` au `BatteryGlyph`.

Dans `DynamicNotch/Shell/BatteryGlyph.swift` : ajouter la propriété `var pulsesBolt = false` après `width`, et sur l'`Image(systemName: "bolt.fill")` ajouter `.symbolEffect(.pulse, options: .repeating, isActive: pulsesBolt)`.

- [ ] **Step 4 : dépôts vivants et fichiers qui arrivent**

Dans `DSDropZone.body` (`DSComponents.swift`), remplacer le `.fill(…)` et le `.strokeBorder(…)` par :
```swift
                .fill(isTargeted ? Color.white.opacity(0.10) : DS.Color.dropZoneIdle)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .strokeBorder(Color.white.opacity(isTargeted ? 0.35 : 0.12), lineWidth: 1)
                )
```
Dans `TrayView.emptyState`, sur l'`Image(systemName: "tray.and.arrow.down.fill")`, ajouter `.symbolEffect(.bounce, value: targeting)` ; dans le `.onDrop` de `TrayView.body`, ajouter `vm.hapticSender.send()` avant le `DispatchQueue.global().async`.
Dans `TrayDrop.load(_:)`, remplacer `items.forEach { self.items.updateOrInsert($0, at: 0) }` par :
```swift
                withAnimation(DS.Motion.expand) {
                    items.forEach { self.items.updateOrInsert($0, at: 0) }
                }
```
(ajouter `import SwiftUI` en tête de `TrayDrop.swift` si nécessaire).
Dans `TrayDrop+DropItemView.swift`, remplacer l'insertion de la transition (`insertion: .opacity,`) par `insertion: .opacity.combined(with: .scale(scale: 0.8)),`.

- [ ] **Step 5 : build, tests, commit**

Run : `Tools/test.sh && Tools/build.sh` → `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: micro-interactions (chiffres, symboles animés, dépôts vivants)"
```

---

### Task 8 : rendu par onglet, vérification et documentation

**Files :**
- Modify : `DynamicNotch/Debug/DebugTools.swift`, `README.md`

- [ ] **Step 1 : un rendu par onglet**

Dans `StateRenderer.renderAll(to:)`, remplacer la ligne des états de départ par :
```swift
            var states: [(String, NotchPresentation)] = [("closed", .closed), ("peek", .peek), ("opened-settings", .opened(.settings))]
            for tab in NotchTab.allCases {
                states.append(("opened-\(tab)", .opened(.tab(tab))))
            }
```

- [ ] **Step 2 : rendre et inspecter**

```bash
Tools/build.sh Debug
OUT="$TMPDIR/notch-states" && rm -rf "$OUT"
build/Build/Products/Debug/DynamicNotch.app/Contents/MacOS/DynamicNotch --render-states "$OUT"
ls "$OUT"
```
Expected : 26 fichiers (`closed`, `peek`, `opened-settings`, 5 `opened-<onglet>`, 18 états d'activité). Ouvrir chaque `opened-*.png` et `closed.png`/`peek.png` et vérifier :
- `closed.png` : la forme a exactement la largeur de l'encoche, sans oreilles ;
- chaque onglet : barre d'onglets à gauche avec la pastille sur le bon onglet, pourcentage + « … » à droite, contenu non tronqué, modules gris sombre arrondis, aucun texte sous 11 pt ;
- `opened-agenda.png` plus haut que `opened-home.png`.
(Le bloc jaune au « sens interdit » est le rendu ImageRenderer de la zone de dépôt, absent de l'app.)

- [ ] **Step 3 : documentation**

Dans `README.md`, remplacer la puce « **Multi-page widget panel** — … » par :
```markdown
- **Tabbed panel** — five tabs live around the notch (Home, Files, Timers,
  Notes, Agenda); the panel morphs out of the notch like the Dynamic Island.
```
et remplacer, dans la liste des widgets, la puce **Calendar** par « **Agenda** (today's events, next ones on Home, via EventKit) ».

- [ ] **Step 4 : suite complète, Release, relance, commit**

```bash
Tools/test.sh && Tools/build.sh
pkill -x DynamicNotch; open build/Build/Products/Release/DynamicNotch.app; sleep 3; pgrep -x DynamicNotch
```
Expected : `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`, un PID.

```bash
git add -A DynamicNotch README.md
git commit -m "chore: rendu Debug par onglet et documentation du panneau à onglets"
```
