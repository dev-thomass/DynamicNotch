//
//  NowPlayingWidget.swift
//  DynamicNotch
//
//  Musique en cours, de deux sources :
//   1. MediaRemote (framework privé, chargé par dlopen) : toutes les apps,
//      pochette comprise. Depuis macOS 15.4, la lecture des infos peut être
//      refusée aux apps tierces ; les commandes (lecture, suivant) restent.
//   2. Les notifications distribuées de Musique et Spotify : titre, artiste,
//      état. Aucune permission requise, fonctionne quand MediaRemote se tait.
//
//  Tout est piloté par notifications, sans interrogation périodique.
//

import AppKit
import Combine
import SwiftUI

// MARK: - MediaRemote dlopen helpers

/// Function signatures we need from the private framework. Resolved on first
/// access; if the framework moves between macOS versions we just hide the
/// widget body instead of crashing.
private struct MR {
    typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias SendCommandFn = @convention(c) (Int, [String: Any]?) -> Bool
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    let getNowPlayingInfo: GetNowPlayingInfoFn?
    let sendCommand: SendCommandFn?
    let register: RegisterFn?

    static let shared: MR = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else { return .init(getNowPlayingInfo: nil, sendCommand: nil, register: nil) }

        let getInfoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        let sendSym = dlsym(handle, "MRMediaRemoteSendCommand")
        let registerSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")

        let getInfo = getInfoSym.map { unsafeBitCast($0, to: GetNowPlayingInfoFn.self) }
        let send = sendSym.map { unsafeBitCast($0, to: SendCommandFn.self) }
        let register = registerSym.map { unsafeBitCast($0, to: RegisterFn.self) }
        return .init(getNowPlayingInfo: getInfo, sendCommand: send, register: register)
    }()
}

/// MediaRemote command codes (from the public-but-undocumented enum).
private enum MRCommand: Int {
    case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
}

// MARK: - Sources

/// Détecte un changement de morceau. Le premier titre vu sert de référence.
struct NowPlayingTrackTracker {
    private var lastTitle: String?

    mutating func update(title: String) -> Bool {
        guard !title.isEmpty else { return false }
        defer { lastTitle = title }
        guard let lastTitle else { return false }
        return lastTitle != title
    }
}

/// Morceau annoncé par Musique ou Spotify dans leurs notifications distribuées.
struct PlayerTrackInfo: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool

    /// Noms des notifications que Musique et Spotify publient à chaque
    /// changement de morceau ou d'état (lecture, pause, arrêt).
    static let notificationNames = [
        "com.apple.Music.playerInfo",
        "com.spotify.client.PlaybackStateChanged"
    ]
}

extension PlayerTrackInfo {
    /// Lit le `userInfo` d'une de ces notifications. Renvoie `nil` si rien
    /// d'exploitable (dictionnaire vide ou sans état de lecture).
    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo, let state = userInfo["Player State"] as? String else { return nil }
        isPlaying = state == "Playing"
        if state == "Stopped" {
            title = ""
            artist = ""
        } else {
            title = userInfo["Name"] as? String ?? ""
            artist = userInfo["Artist"] as? String ?? ""
        }
    }
}

// MARK: - Manager

@MainActor
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false

    /// Appelé quand le titre change (hors premier titre vu).
    var onTrackChange: (() -> Void)?

    private var observing = false
    private var tracker = NowPlayingTrackTracker()
    private var observers: [NSObjectProtocol] = []
    /// Dernier état annoncé par Musique / Spotify, utilisé quand MediaRemote
    /// ne renvoie rien.
    private var playerInfo: PlayerTrackInfo?

    private init() {}

    /// Abonnement aux notifications MediaRemote, Musique et Spotify.
    /// Idempotent : appelé au lancement par ActivityWiring et à l'apparition
    /// du widget.
    func startObserving() {
        guard !observing else { return }
        observing = true

        MR.shared.register?(DispatchQueue.main)
        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        ] {
            observers.append(NotificationCenter.default.addObserver(
                forName: .init(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        let distributed = DistributedNotificationCenter.default()
        for name in PlayerTrackInfo.notificationNames {
            observers.append(distributed.addObserver(
                forName: .init(name),
                object: nil,
                queue: .main
            ) { [weak self] note in
                let info = PlayerTrackInfo(userInfo: note.userInfo)
                MainActor.assumeIsolated { self?.receive(playerInfo: info) }
            })
        }
        refresh()
    }

    private func receive(playerInfo info: PlayerTrackInfo?) {
        guard let info else { return }
        playerInfo = info
        apply(title: info.title, artist: info.artist, artwork: nil, isPlaying: info.isPlaying)
        // MediaRemote, s'il répond, complète avec la pochette.
        refresh()
    }

    /// Interroge MediaRemote. Une réponse vide (rien en lecture, ou accès
    /// refusé depuis macOS 15.4) laisse la place à la dernière info de
    /// Musique / Spotify.
    func refresh() {
        guard let getInfo = MR.shared.getNowPlayingInfo else { return }
        getInfo(.main) { [weak self] info in
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            Task { @MainActor in
                guard let self else { return }
                if title.isEmpty {
                    let fallback = self.playerInfo
                    self.apply(
                        title: fallback?.title ?? "",
                        artist: fallback?.artist ?? "",
                        artwork: nil,
                        isPlaying: fallback?.isPlaying ?? false
                    )
                } else {
                    self.apply(
                        title: title,
                        artist: artist,
                        artwork: artworkData.flatMap { NSImage(data: $0) },
                        isPlaying: rate > 0
                    )
                }
            }
        }
    }

    private func apply(title: String, artist: String, artwork: NSImage?, isPlaying: Bool) {
        let trackChanged = tracker.update(title: title)
        if self.title != title {
            self.title = title
        }
        if self.artist != artist {
            self.artist = artist
        }
        // Une source sans pochette n'efface pas celle du morceau en cours.
        if artwork != nil || title.isEmpty || trackChanged {
            self.artwork = artwork
        }
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
        }
        if trackChanged {
            onTrackChange?()
        }
    }

    func togglePlay() {
        _ = MR.shared.sendCommand?(MRCommand.togglePlayPause.rawValue, nil)
        refresh()
    }

    func next() {
        _ = MR.shared.sendCommand?(MRCommand.next.rawValue, nil)
        refresh()
    }

    func previous() {
        _ = MR.shared.sendCommand?(MRCommand.previous.rawValue, nil)
        refresh()
    }
}

// MARK: - View

struct NowPlayingWidgetView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var player = NowPlayingManager.shared

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            artworkView
            infoView
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .onAppear { player.startObserving() }
    }

    private var artworkView: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(DS.Color.surfaceRaisedStrong)
            .frame(width: 56, height: 56)
            .overlay {
                if let art = player.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
    }

    private var infoView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if player.title.isEmpty {
                Text("Rien en lecture")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            } else {
                Text(player.title)
                    .font(DS.Typography.bodyEmphasis)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(player.artist)
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: DS.Spacing.sm) {
                mediaBtn("backward.fill", "Précédent") { player.previous() }
                mediaBtn(
                    player.isPlaying ? "pause.fill" : "play.fill",
                    player.isPlaying ? "Pause" : "Lecture",
                    size: 14
                ) { player.togglePlay() }
                mediaBtn("forward.fill", "Suivant") { player.next() }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediaBtn(
        _ systemImage: String,
        _ label: LocalizedStringKey,
        size: CGFloat = 11,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                        .fill(DS.Color.surfaceRaisedStrong)
                )
                .foregroundStyle(DS.Color.textPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
