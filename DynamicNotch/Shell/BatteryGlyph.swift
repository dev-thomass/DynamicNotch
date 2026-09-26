//
//  BatteryGlyph.swift
//  DynamicNotch
//
//  Glyphe batterie dessiné, redimensionnable (22 pt dans l'aile, 44 pt dans
//  l'état étendu). Hauteur arrondie au point, trait de 1 ou 2 pt : net à
//  toutes les tailles.
//

import SwiftUI

struct BatteryGlyph: View {
    let level: Double
    let tint: Color
    let isCharging: Bool
    var width: CGFloat = 22

    var body: some View {
        let height = (width / 2).rounded()
        let stroke: CGFloat = width >= 40 ? 2 : 1
        let inset = stroke + 1
        let corner = height * 0.3
        HStack(spacing: max(1, (width * 0.05).rounded())) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: stroke)
                RoundedRectangle(cornerRadius: max(1, corner - inset), style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, (width - 2 * inset) * min(1, max(0, level))))
                    .padding(inset)
            }
            .frame(width: width, height: height)
            .overlay {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.7), radius: 0.5)
                }
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(width: max(1.5, (width * 0.07).rounded()), height: (height * 0.4).rounded())
        }
        .accessibilityHidden(true)
    }
}
