//
//  FilesTabView.swift
//  DynamicNotch
//
//  L'étagère de fichiers en grand, avec la zone AirDrop à gauche.
//

import SwiftUI

struct FilesTabView: View {
    var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            ShareView(vm: vm, type: .airdrop)
                .frame(width: 120)
            TrayView(vm: vm)
        }
    }
}
