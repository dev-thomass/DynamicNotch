//
//  Ext+URL.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import QuickLookThumbnailing

extension URL {
    /// Generate a Quick Look thumbnail (or fall back to the file's icon).
    ///
    /// Uses the modern `QLThumbnailGenerator` API. The legacy
    /// `QLThumbnailImageCreate` it replaces is deprecated since macOS 10.15
    /// and will likely be removed in a future SDK.
    ///
    /// We block on the asynchronous request via a semaphore (with a 5 s ceiling)
    /// because the only caller — `TrayDrop.DropItem.init` — runs on a background
    /// queue and *needs* the bitmap synchronously to embed it in the persisted
    /// item. T-30 will eventually move the storage to a separate file so this
    /// can become truly async.
    func snapshotPreview() -> NSImage {
        precondition(!Thread.isMainThread, "snapshotPreview must run off the main thread")

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: 128, height: 128)

        let request = QLThumbnailGenerator.Request(
            fileAt: self,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        let sem = DispatchSemaphore(value: 0)
        var result: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            if let rep { result = rep.nsImage }
            sem.signal()
        }
        switch sem.wait(timeout: .now() + .seconds(5)) {
        case .success:
            if let image = result { return image }
        case .timedOut:
            Log.drop.error("QLThumbnailGenerator timed out for \(self.lastPathComponent, privacy: .public)")
        }

        // Fallback: the system file icon. Always available and cheap.
        return NSWorkspace.shared.icon(forFile: path)
    }
}
