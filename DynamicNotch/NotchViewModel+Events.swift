//
//  NotchViewModel+Events.swift
//  DynamicNotch
//

import Cocoa
import Combine
import Foundation
import SwiftUI

extension NotchViewModel {
    func setupCancellables() {
        let events = EventMonitors.shared

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMouseDown(at: NSEvent.mouseLocation) }
            .store(in: &cancellables)

        events.optionKeyPress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pressed in self?.optionKeyPressed = pressed }
            .store(in: &cancellables)

        // Le système émet mouseMoved à la fréquence d'affichage : 60 Hz suffisent
        // pour détecter l'entrée et la sortie de l'encoche.
        events.mouseLocation
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.handleMouseMove(to: NSEvent.mouseLocation) }
            .store(in: &cancellables)

        presentationChanges
            .filter { $0 == .peek }
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.hapticSender.send()
            }
            .store(in: &cancellables)

        hapticSender
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard self?.hapticFeedback ?? false else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                self?.notchClose()
                output.apply()
            }
            .store(in: &cancellables)

        // Échap ferme le panneau (désactivable dans les réglages).
        events.escapePressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, presentation.isOpened, AppSettings.shared.escClosesNotch else { return }
                notchClose()
            }
            .store(in: &cancellables)

        activityObservation = activities.observe { [weak self] _ in
            self?.activityDidChange()
        }
    }

    func handleMouseDown(at point: NSPoint) {
        if presentation.isOpened {
            // Clic hors du panneau, ou sur l'encoche elle-même → fermer.
            if !notchOpenedRect.contains(point) || deviceNotchRect.insetBy(dx: inset, dy: inset).contains(point) {
                notchClose()
            }
        } else if currentShellRect.insetBy(dx: inset, dy: inset).contains(point) {
            notchOpen(.click)
        }
    }

    func handleMouseMove(to point: NSPoint) {
        let insideShell = currentShellRect.insetBy(dx: inset, dy: inset).contains(point)
        let wasInsideShell = isPointerInsideShell
        isPointerInsideShell = insideShell
        guard AppSettings.shared.popOnHoverEnabled else { return }
        // Ailes affichées : retour haptique à l'entrée dans la coque, sans
        // agrandissement (l'aperçu reste réservé à l'encoche fermée).
        if case .compact = presentation, insideShell, !wasInsideShell {
            hapticSender.send()
        }
        let inside = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(point)
        if presentation == .closed, inside {
            notchPop()
        }
        if presentation == .peek, !inside {
            notchClose()
        }
    }
}
