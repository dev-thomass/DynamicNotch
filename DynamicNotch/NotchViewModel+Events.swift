//
//  NotchViewModel+Events.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/8.
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
            .sink { [weak self] _ in
                guard let self else { return }
                let mouseLocation: NSPoint = NSEvent.mouseLocation
                switch status {
                case .opened:
                    // Click outside the opened panel → close.
                    if !notchOpenedRect.contains(mouseLocation) {
                        notchClose()
                    // Click on the device notch silhouette itself → close.
                    // (The header's menu/settings/close buttons have their own
                    // tap targets and don't reach this handler.)
                    } else if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        notchClose()
                    }
                    // The legacy "click headline to cycle through .normal → .menu → .settings"
                    // anti-pattern was removed in 2026-05. Use the explicit header buttons
                    // (DSNotchHeader) instead.
                case .closed, .popping:
                    // Click on the closed notch → open.
                    if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        notchOpen(.click)
                    }
                }
            }
            .store(in: &cancellables)

        events.optionKeyPress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] input in
                guard let self else { return }
                optionKeyPressed = input
            }
            .store(in: &cancellables)

        events.mouseLocation
            // The system emits mouseMoved at the display refresh rate (60-120 Hz).
            // We only need to know when the cursor *crosses* the device-notch rect;
            // throttling to ~60 Hz keeps the publisher chain cheap while still
            // feeling instantaneous.
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                // Respect the user's "Pop on hover" preference (T-32).
                guard AppSettings.shared.popOnHoverEnabled else { return }
                let mouseLocation: NSPoint = NSEvent.mouseLocation
                let aboutToOpen = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation)
                if status == .closed, aboutToOpen { notchPop() }
                if status == .popping, !aboutToOpen { notchClose() }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 != .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation { self?.notchVisible = true }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 == .popping }
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
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .now
                )
            }
            .store(in: &cancellables)

        $status
            .debounce(for: 0.5, scheduler: DispatchQueue.global())
            .filter { $0 == .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.notchVisible = false
                }
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

        // Esc dismisses the opened notch (accessibility baseline).
        // Toggleable via AppSettings.escClosesNotch pour les utilisateurs
        // qui veulent que Esc reste exclusif à l'app frontale.
        events.escapePressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, status == .opened else { return }
                guard AppSettings.shared.escClosesNotch else { return }
                notchClose()
            }
            .store(in: &cancellables)
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
