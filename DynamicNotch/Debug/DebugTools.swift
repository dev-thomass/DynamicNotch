//
//  DebugTools.swift
//  DynamicNotch
//
//  Outils de développement, absents des builds Release :
//   - `--simulate <activité>` : déclenche une activité 1 s après le lancement ;
//   - `--render-states <dossier>` : rend chaque état de la coque en PNG
//     (ImageRenderer) puis quitte, sans autorisation d'enregistrement d'écran ;
//   - une simulation d'activité dans le menu « … » de la rangée de l'encoche.
//

#if DEBUG
    import AppKit
    import SwiftUI

    @MainActor
    enum ActivitySimulator {
        static func run(_ name: String, center: ActivityCenter = .shared) {
            switch name {
            case "charging":
                center.setPersistent(.charging, active: true)
                center.post(.charging)
            case "unplugged":
                center.post(.unplugged)
            case "lowBattery":
                center.post(.lowBattery(percent: 10))
            case "pomodoroPhase":
                let model = PomodoroModel.shared
                if model.phase == .idle { model.performPrimary() }
                model.skip()
            case "stopwatch":
                if !StopwatchModel.shared.running { StopwatchModel.shared.toggle() }
            case "filesAdded":
                center.post(.filesAdded(count: 3))
            case "airDropSent":
                center.post(.airDropSent)
            case "nowPlaying":
                center.setPersistent(.nowPlaying, active: true)
                center.post(.nowPlaying)
            case "calendarSoon":
                center.setPersistent(.calendarSoon, active: true)
            case "hudVolume":
                HUDController.shared.show(HUDState(kind: .volume, level: 0.62))
            case "hudBrightness":
                HUDController.shared.show(HUDState(kind: .brightness, level: 0.4))
            default:
                Log.app.error("activité simulée inconnue : \(name, privacy: .public)")
            }
        }

        static func handleLaunchArguments() {
            guard let index = CommandLine.arguments.firstIndex(of: "--simulate"),
                  index + 1 < CommandLine.arguments.count
            else { return }
            let name = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { run(name) }
            }
        }
    }

    @MainActor
    enum StateRenderer {
        static func renderAll(to directory: URL) {
            let geometry = NSScreen.main.map { NotchGeometry(screen: ScreenDescriptor($0)) } ?? .preview
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var states: [(String, NotchPresentation)] = [("closed", .closed), ("peek", .peek), ("opened-settings", .opened(.settings))]
            for tab in NotchTab.allCases {
                states.append(("opened-\(tab)", .opened(.tab(tab))))
            }
            for id in ActivityID.samples {
                states.append(("compact-\(id.debugName)", .compact(id)))
                states.append(("expanded-\(id.debugName)", .expanded(id)))
            }
            states.append(("hud-volume", .hud(.volume)))
            states.append(("hud-brightness", .hud(.brightness)))

            for (name, state) in states {
                if case let .hud(kind) = state {
                    HUDController.shared.show(HUDState(kind: kind, level: kind == .volume ? 0.62 : 0.4))
                }
                let vm = NotchViewModel(geometry: geometry)
                vm.setPresentationForRendering(state)
                // Haut de fenêtre seulement, sauf pour le panneau ouvert.
                let height: CGFloat = state.isOpened ? NotchGeometry.windowSize.height : 120
                let view = NotchView(vm: vm)
                    .frame(width: NotchGeometry.windowSize.width, height: height, alignment: .top)
                    .clipped()
                    .background(Color(white: 0.82))
                let renderer = ImageRenderer(content: view)
                renderer.scale = geometry.screen.scale
                if let image = renderer.cgImage,
                   let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                {
                    try? png.write(to: directory.appendingPathComponent("\(name).png"))
                }
                vm.destroy()
            }
            print("rendu : \(states.count) états dans \(directory.path)")
        }
    }
#endif
