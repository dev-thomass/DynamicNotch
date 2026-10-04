//
//  Share.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/8.
//  Last Modified by 冷月 on 2025/5/5.
//

import Cocoa
import Observation

/// Envois AirDrop en cours (pour animer l'icône pendant l'envoi).
@Observable
final class ShareActivity {
    static let shared = ShareActivity()

    private(set) var isSending = false
    private var count = 0

    func begin() {
        count += 1
        isSending = true
    }

    func end() {
        count = max(0, count - 1)
        isSending = count > 0
    }
}

class Share: NSObject, NSSharingServiceDelegate {
    let files: [URL]
    let serviceName: NSSharingService.Name?

    /// Partages en cours, retenus jusqu'au retour du délégué.
    private static var inFlight: Set<Share> = []
    /// Appelé sur la file principale quand un envoi AirDrop a réussi.
    static var onAirDropSent: (() -> Void)?

    init(files: [URL], serviceName: NSSharingService.Name? = nil) {
        self.files = files
        self.serviceName = serviceName
        super.init()
    }

    func begin() {
        Share.inFlight.insert(self)
        if serviceName == .sendViaAirDrop {
            ShareActivity.shared.begin()
        }
        do {
            try sendEx(files)
        } catch {
            Share.inFlight.remove(self)
            if serviceName == .sendViaAirDrop {
                ShareActivity.shared.end()
            }
            NSAlert.popError(error)
        }
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) {
        if serviceName == .sendViaAirDrop {
            Share.onAirDropSent?()
            ShareActivity.shared.end()
        }
        Share.inFlight.remove(self)
    }

    func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error _: Error) {
        if serviceName == .sendViaAirDrop {
            ShareActivity.shared.end()
        }
        Share.inFlight.remove(self)
    }

    private func sendEx(_ files: [URL]) throws {
        if let serviceName {
            guard let service = NSSharingService(named: serviceName) else {
                throw NSError(domain: "ShareService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Selected sharing service not available", comment: "")
                ])
            }

            guard service.canPerform(withItems: files) else {
                throw NSError(domain: "ShareService", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "Sharing service cannot perform with given files",
                        comment: ""
                    )
                ])
            }

            service.delegate = self
            service.perform(withItems: files)
        } else {
            Share.inFlight.remove(self)
            // 弹出分享面板
            let picker = NSSharingServicePicker(items: files)
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
    }
}
