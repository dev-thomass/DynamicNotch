//
//  ClipboardTabView.swift
//  DynamicNotch
//
//  Les derniers textes copiés : un clic les remet dans le presse-papiers.
//

import SwiftUI

struct ClipboardTabView: View {
    var vm: NotchViewModel
    private let settings = AppSettings.shared
    private let history = ClipboardHistory.shared

    var body: some View {
        DSModule {
            if !settings.clipboardHistoryEnabled {
                placeholder("Historique désactivé dans les réglages")
            } else if history.entries.items.isEmpty {
                placeholder("Copiez du texte : il apparaîtra ici")
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Copiés récemment")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button("Effacer") { history.clear() }
                    .buttonStyle(.plain)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.brand)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(history.entries.items, id: \.self) { text in
                        row(text)
                    }
                }
            }
        }
    }

    private func row(_ text: String) -> some View {
        Button {
            history.copy(text)
            vm.hapticSender.send()
        } label: {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSHighlightButtonStyle(shape: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)))
        .help(Text("Copier"))
        .accessibilityLabel(Text("Copier : \(text)"))
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(DS.Color.textSecondary)
            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
