//
//  NotchViewModelTests.swift
//  DynamicNotchTests
//
//  Colle entre NotchViewModel et ActivityCenter : état initial, suspension
//  pendant l'ouverture, suivi des activités. `ManualScheduler` est défini
//  dans ActivityCenterTests.swift.
//

import Combine
import XCTest
@testable import DynamicNotch

@MainActor
final class NotchViewModelTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var center: ActivityCenter!
    private var hud: HUDController!

    override func setUp() async throws {
        scheduler = ManualScheduler()
        center = ActivityCenter(scheduler: scheduler)
        hud = HUDController(scheduler: scheduler)
    }

    private func makeViewModel() -> NotchViewModel {
        let vm = NotchViewModel(geometry: .preview, activities: center, hud: hud)
        vm.lastTab = .home
        return vm
    }

    // MARK: état initial

    func test_init_adoptsActivityAlreadyInProgress() {
        center.setPersistent(.charging, active: true)
        let vm = makeViewModel()
        XCTAssertEqual(vm.presentation, .compact(.charging))
        vm.destroy()
    }

    func test_init_withoutActivity_isClosed() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.presentation, .closed)
        vm.destroy()
    }

    // MARK: suspension

    func test_open_suspends_close_resumes() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        XCTAssertTrue(center.isSuspended)
        vm.notchClose()
        XCTAssertFalse(center.isSuspended)
        vm.destroy()
    }

    func test_openTwice_closeOnce_resumes() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        vm.notchOpen(.boot)
        vm.notchClose()
        XCTAssertFalse(center.isSuspended)
        vm.destroy()
    }

    func test_destroyWhileOpen_resumes() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        vm.destroy()
        XCTAssertFalse(center.isSuspended)
    }

    /// L'ouverture passe directement à l'état ouvert : la suspension (qui
    /// coupe la ponctuelle en cours) ne doit pas faire repasser la coque par
    /// l'état compact.
    func test_open_goesStraightToOpened_withoutIntermediateCompact() {
        center.setPersistent(.charging, active: true)
        center.post(.charging)
        let vm = makeViewModel()
        XCTAssertEqual(vm.presentation, .expanded(.charging))
        var states: [NotchPresentation] = []
        let observation = vm.$presentation.dropFirst().sink { states.append($0) }
        vm.notchOpen(.boot)
        XCTAssertEqual(states, [.opened(.tab(.home))])
        observation.cancel()
        vm.destroy()
    }

    func test_showSettings_whenClosed_opensAndSuspends() {
        let vm = makeViewModel()
        vm.showSettings()
        XCTAssertEqual(vm.presentation, .opened(.settings))
        XCTAssertTrue(center.isSuspended)
        vm.notchClose()
        XCTAssertFalse(center.isSuspended)
        vm.destroy()
    }

    // MARK: suivi des activités

    func test_activityChangeWhileClosed_isFollowed() {
        let vm = makeViewModel()
        center.setPersistent(.charging, active: true)
        XCTAssertEqual(vm.presentation, .compact(.charging))
        center.post(.charging)
        XCTAssertEqual(vm.presentation, .expanded(.charging))
        scheduler.advance(by: 2.2)
        XCTAssertEqual(vm.presentation, .compact(.charging))
        center.setPersistent(.charging, active: false)
        XCTAssertEqual(vm.presentation, .closed)
        vm.destroy()
    }

    func test_activityChangeWhileOpened_keepsPanel_thenRestsOnClose() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        center.setPersistent(.stopwatch, active: true)
        XCTAssertEqual(vm.presentation, .opened(.tab(.home)))
        vm.notchClose()
        XCTAssertEqual(vm.presentation, .compact(.stopwatch))
        vm.destroy()
    }

    // MARK: survol des ailes

    func test_hoverOverCompactShell_sendsHapticOnEntryOnly() {
        AppSettings.shared.popOnHoverEnabled = true
        center.setPersistent(.charging, active: true)
        let vm = makeViewModel()
        var haptics = 0
        let observation = vm.hapticSender.sink { haptics += 1 }
        let shell = vm.currentShellRect
        let inside = NSPoint(x: shell.minX + 4, y: shell.midY)
        let outside = NSPoint(x: shell.minX - 40, y: shell.midY - 200)

        vm.handleMouseMove(to: outside)
        vm.handleMouseMove(to: inside)
        vm.handleMouseMove(to: inside)
        XCTAssertEqual(haptics, 1)
        XCTAssertEqual(vm.presentation, .compact(.charging), "pas d'agrandissement en compact")
        vm.handleMouseMove(to: outside)
        vm.handleMouseMove(to: inside)
        XCTAssertEqual(haptics, 2)
        observation.cancel()
        vm.destroy()
    }

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

    func test_closeSettings_resetsSlideEdgeToTrailing() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        vm.selectTab(.agenda)
        vm.selectTab(.home)
        XCTAssertEqual(vm.tabSlideEdge, .leading)
        vm.showSettings()
        vm.closeSettings()
        XCTAssertEqual(vm.tabSlideEdge, .trailing)
        vm.destroy()
    }

    // MARK: HUD

    func test_hud_takesPrecedence_overActivity_thenRestsOnActivity() {
        center.setPersistent(.charging, active: true)
        let vm = makeViewModel()
        XCTAssertEqual(vm.presentation, .compact(.charging))
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .hud(.volume))
        hud.show(HUDState(kind: .brightness, level: 0.4))
        XCTAssertEqual(vm.presentation, .hud(.brightness))
        scheduler.advance(by: 1.5)
        XCTAssertEqual(vm.presentation, .compact(.charging))
        vm.destroy()
    }

    func test_hud_doesNotInterruptOpenedPanel() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .opened(.tab(.home)))
        vm.notchClose()
        XCTAssertEqual(vm.presentation, .hud(.volume))
        vm.destroy()
    }

    func test_hud_overridesPeek() {
        AppSettings.shared.popOnHoverEnabled = true
        let vm = makeViewModel()
        vm.notchPop()
        XCTAssertEqual(vm.presentation, .peek)
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .hud(.volume))
        vm.destroy()
    }
}
