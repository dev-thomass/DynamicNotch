//
//  NotchMiniPlayer.swift
//  DynamicNotch
//
//  Mini lecteur de la rangée du haut du panneau ouvert : pochette, lecture /
//  pause et morceau suivant. Visible sur tous les onglets dès qu'un morceau
//  est connu ; le survol de la pochette donne le titre et l'artiste.
//

import SwiftUI

struct NotchMiniPlayer: View {
    private let player = NowPlayingManager.shared

    var body: some View {
        if !player.title.isEmpty {
            HStack(spacing: 2) {
                artwork
                    .padding(.trailing, 4)
                DSIconButton(
                    player.isPlaying ? "pause.fill" : "play.fill",
                    label: player.isPlaying ? "Pause" : "Lecture"
                ) { player.togglePlay() }
                DSIconButton("forward.fill", label: "Suivant") { player.next() }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var artwork: some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    DS.Color.surfaceRaisedStrong
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help(Text(nowPlayingText))
        .accessibilityLabel(Text(nowPlayingText))
    }

    private var nowPlayingText: String {
        player.artist.isEmpty ? player.title : "\(player.title) · \(player.artist)"
    }
}
