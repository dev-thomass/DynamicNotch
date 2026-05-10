//
//  NotchHUDView.swift
//  DynamicNotch
//
//  HUD compact qui apparaît SOUS l'encoche (collé au bord inférieur de la
//  silhouette noire) lors d'une action volume / luminosité. Auto-hide au
//  bout de 1.2 s d'inactivité.
//

import Combine
import SwiftUI

@MainActor
final class HUDController: ObservableObject {
    static let shared = HUDController()

    enum HUDKind: Equatable {
        case volume(level: Float, muted: Bool)
        case brightness(level: Float)
    }

    @Published private(set) var current: HUDKind?

    private var hideTask: DispatchWorkItem?

    private init() {
        // Souscriptions aux events des managers — chaque émission relance
        // le timer d'auto-hide.
        observeMediaKeys()
        observeBrightness()
    }

    func showVolume(level: Float, muted: Bool) {
        current = .volume(level: level, muted: muted)
        scheduleHide()
    }

    func showBrightness(level: Float) {
        current = .brightness(level: level)
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) {
                self?.current = nil
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func observeMediaKeys() {
        MediaKeyInterceptor.shared.volumeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showVolume(level: level, muted: VolumeManager.shared.isMuted)
            }
            .store(in: &cancellables)
        MediaKeyInterceptor.shared.volumeMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.showVolume(level: VolumeManager.shared.level, muted: muted)
            }
            .store(in: &cancellables)
    }

    private func observeBrightness() {
        // La luminosité est polled (1Hz). On émet une notification HUD à
        // chaque changement détecté supérieur à un certain delta pour
        // éviter les ré-apparitions parasites.
        BrightnessManager.shared.$level
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.showBrightness(level: level)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - View

struct NotchHUDView: View {
    @StateObject private var controller = HUDController.shared

    var body: some View {
        Group {
            if let kind = controller.current {
                hudCard(for: kind)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: controller.current)
    }

    @ViewBuilder
    private func hudCard(for kind: HUDController.HUDKind) -> some View {
        // Mini-pill : 100×14, vraiment discrète. Icône 9pt + barre 60pt
        // sans texte de pourcentage (visuellement bruyant pour un HUD
        // qui doit juste donner le niveau au coup d'œil).
        HStack(spacing: 6) {
            icon(for: kind)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            ProgressBar(level: level(for: kind), tint: tint(for: kind))
                .frame(width: 60, height: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            // Fond semi-transparent + matériau translucide pour rester
            // élégant sans crier comme un bloc noir massif.
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    private func icon(for kind: HUDController.HUDKind) -> Image {
        switch kind {
        case .volume(_, let muted):
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        case .brightness:
            Image(systemName: "sun.max.fill")
        }
    }

    private func level(for kind: HUDController.HUDKind) -> Float {
        switch kind {
        case .volume(let l, _): l
        case .brightness(let l): l
        }
    }

    private func tint(for kind: HUDController.HUDKind) -> Color {
        switch kind {
        case .volume:     DS.Color.brand
        case .brightness: .yellow
        }
    }
}

private struct ProgressBar: View {
    let level: Float
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(tint).frame(width: max(2, CGFloat(level) * geo.size.width))
            }
        }
    }
}
