//
//  MediaRemoteAdapter.swift
//  DynamicNotch
//
//  Lecture de la musique en cours via mediaremote-adapter (Vendor/) : le
//  script Perl, lancé par /usr/bin/perl (binaire système autorisé à lire
//  MediaRemote depuis macOS 15.4), charge MediaRemoteAdapter.framework et
//  écrit une ligne JSON à chaque changement. Donne titre, artiste, état et
//  pochette pour toutes les apps, là où MediaRemote seul ne renvoie plus rien.
//

import AppKit

/// État publié par l'adaptateur (une ligne `stream --no-diff`).
struct AdapterNowPlaying: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkData: Data?

    /// Lit une ligne du flux. `nil` si la ligne n'est pas une donnée ;
    /// une charge vide (rien en lecture) donne un état vide à l'arrêt.
    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }
        title = payload["title"] as? String ?? ""
        artist = payload["artist"] as? String ?? ""
        isPlaying = payload["playing"] as? Bool ?? false
        artworkData = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
    }

    init(title: String, artist: String, isPlaying: Bool, artworkData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.artworkData = artworkData
    }
}

/// Découpe un flux d'octets en lignes complètes.
struct LineBuffer {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex ..< newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            pending.removeSubrange(pending.startIndex ... newline)
        }
        return lines
    }
}

@MainActor
final class MediaRemoteAdapter {
    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private let script: URL
    private let framework: URL

    private var process: Process?
    private var buffer = LineBuffer()
    private var restarts = 0
    private let maxRestarts = 3
    private var stopped = false

    /// `nil` si le script ou le framework manquent dans le paquet de l'app.
    init?(bundle: Bundle = .main) {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        self.script = script
        self.framework = framework
    }

    /// Lance le flux ; `onUpdate` reçoit chaque nouvel état sur le MainActor.
    /// `onGiveUp` est appelé si l'adaptateur s'arrête pour de bon (relances
    /// épuisées) : l'appelant reprend alors ses autres sources.
    func start(
        onUpdate: @escaping @MainActor (AdapterNowPlaying) -> Void,
        onGiveUp: @escaping @MainActor () -> Void = {}
    ) {
        guard process == nil, !stopped else { return }
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--debounce=150"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // Fin de flux : sans ça le gestionnaire boucle sur des lectures vides.
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for line in self.buffer.append(chunk) {
                        if let state = AdapterNowPlaying(line: line) {
                            self.restarts = 0
                            onUpdate(state)
                        }
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.process = nil
                    self.buffer = LineBuffer()
                    guard !self.stopped else { return }
                    // Relance limitée : un adaptateur cassé par une mise à
                    // jour de macOS ne doit pas tourner en boucle.
                    guard self.restarts < self.maxRestarts else {
                        Log.app.error("mediaremote-adapter stopped, giving up")
                        onGiveUp()
                        return
                    }
                    self.restarts += 1
                    self.start(onUpdate: onUpdate, onGiveUp: onGiveUp)
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            Log.app.error("mediaremote-adapter failed to launch: \(error.localizedDescription, privacy: .public)")
            onGiveUp()
        }
    }

    /// Arrête le flux sans relance (fermeture de l'app).
    func stop() {
        stopped = true
        process?.terminate()
    }

    /// Commande MediaRemote (0 lecture, 1 pause, 2 bascule, 4 suivant, 5 précédent).
    func send(_ command: Int) {
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "send", String(command)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
