//
//  NowPlayingWidget.swift
//  DynamicNotch
//
//  Read-only "Now Playing" display + media-key control via private
//  MediaRemote framework dlopened at runtime.
//
//  Why dlopen rather than a swift sub-process: simpler, no helper to ship,
//  works reliably for **playback control** (the part users actually need).
//  Reading the current track requires the framework's "GetNowPlayingInfo"
//  callback — provided opportunistically, with a graceful empty state.
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
    typealias SendCommandFn       = @convention(c) (Int, [String: Any]?) -> Bool

    let getNowPlayingInfo: GetNowPlayingInfoFn?
    let sendCommand: SendCommandFn?

    static let shared: MR = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else { return .init(getNowPlayingInfo: nil, sendCommand: nil) }

        let getInfoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        let sendSym    = dlsym(handle, "MRMediaRemoteSendCommand")

        let getInfo = getInfoSym.map { unsafeBitCast($0, to: GetNowPlayingInfoFn.self) }
        let send    = sendSym.map { unsafeBitCast($0, to: SendCommandFn.self) }
        return .init(getNowPlayingInfo: getInfo, sendCommand: send)
    }()
}

// MediaRemote command codes (from the public-but-undocumented enum).
private enum MRCommand: Int {
    case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5
}

// MARK: - Manager

@MainActor
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false

    private var pollTimer: Timer?

    private init() {}

    /// Start polling the system "now playing" info. Called when at least one
    /// NowPlayingWidgetView is on screen.
    func startObserving() {
        guard pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopObserving() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Refresh from MediaRemote. Silent no-op if the framework can't be
    /// resolved (sandbox restrictions on a future macOS, etc.).
    func refresh() {
        guard let getInfo = MR.shared.getNowPlayingInfo else { return }
        getInfo(.main) { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                self.title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                self.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    self.artwork = NSImage(data: data)
                }
                if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                    self.isPlaying = rate > 0
                }
            }
        }
    }

    func togglePlay() { _ = MR.shared.sendCommand?(MRCommand.togglePlayPause.rawValue, nil); refresh() }
    func next()       { _ = MR.shared.sendCommand?(MRCommand.next.rawValue, nil); refresh() }
    func previous()   { _ = MR.shared.sendCommand?(MRCommand.previous.rawValue, nil); refresh() }
}

// MARK: - View

struct NowPlayingWidgetView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var player = NowPlayingManager.shared

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            artworkView
            infoView
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .dsRimLight()
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
                mediaBtn(player.isPlaying ? "pause.fill" : "play.fill",
                         player.isPlaying ? "Pause" : "Lecture",
                         size: 14) { player.togglePlay() }
                mediaBtn("forward.fill", "Suivant") { player.next() }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mediaBtn(_ systemImage: String, _ label: LocalizedStringKey, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
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
