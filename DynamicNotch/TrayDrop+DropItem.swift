//
//  TrayDrop+DropItem.swift
//  TrayDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import CoreTransferable
import Foundation
import QuickLook
import UniformTypeIdentifiers

extension TrayDrop {
    struct DropItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID

        let fileName: String
        let size: Int

        let copiedDate: Date

        /// Legacy in-JSON preview blob. Kept for backward compatibility so we
        /// can read items persisted by older versions and migrate them on
        /// access (see `workspacePreviewImage`). New items leave this empty
        /// and write their preview to `previewURL` instead.
        let workspacePreviewImageData: Data

        init(url: URL) throws {
            // Performs blocking I/O (file copy + thumbnail generation).
            // Hard-fail on main thread to keep the UI responsive.
            precondition(!Thread.isMainThread, "DropItem.init must run off the main thread")

            id = UUID()
            fileName = url.lastPathComponent

            size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            copiedDate = Date()
            // New items write the preview to disk (see `previewURL` below) instead
            // of inflating the JSON. Keep this field empty in modern items.
            workspacePreviewImageData = .init()

            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: url, to: storageURL)

            // Sidecar PNG for the Quick Look thumbnail. Best-effort: a missing
            // preview falls back to the system icon at render time, so we don't
            // throw if writing fails.
            let pngData = url.snapshotPreview().pngRepresentation
            do {
                try pngData.write(to: previewURL, options: .atomic)
            } catch {
                Log.drop.error("failed to write preview sidecar: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension TrayDrop.DropItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        let exportingBehavior: @Sendable (TrayDrop.DropItem) async throws -> SentTransferredFile = { input in
            let tempDir = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let newPath = tempDir.appendingPathComponent(input.fileName)
            try FileManager.default.copyItem(
                at: input.storageURL,
                to: newPath
            )
            return .init(newPath, allowAccessingOriginalFile: true)
        }
        let importingBehavior: @Sendable (ReceivedTransferredFile) async throws -> TrayDrop.DropItem = { _ in
            // DynamicNotch items are export-only. If the system ever asks us to
            // import one (e.g. drag a DynamicNotch item back into the notch),
            // surface it as a recoverable error rather than crashing the app.
            throw DynamicNotchError.importNotSupported
        }
        return FileRepresentation(
            contentType: .data,
            shouldAttemptToOpenInPlace: true,
            exporting: exportingBehavior,
            importing: importingBehavior
        )
    }
}

extension TrayDrop.DropItem {
    static let mainDir = "CopiedItems"
    static let previewFileName = ".preview.png"

    var storageURL: URL {
        documentsDirectory
            .appendingPathComponent(Self.mainDir)
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent(fileName)
    }

    /// Sidecar PNG path next to the stored file. Avoids inflating the JSON
    /// (the legacy in-blob preview made the items file grow ~50 KB per item).
    var previewURL: URL {
        storageURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.previewFileName)
    }

    /// Resolves a thumbnail in this priority order:
    /// 1. Sidecar PNG on disk (modern path),
    /// 2. Legacy `workspacePreviewImageData` blob (items persisted by older versions),
    /// 3. The system file icon (always available, cheap),
    /// 4. An empty NSImage as a last resort.
    var workspacePreviewImage: NSImage {
        if let data = try? Data(contentsOf: previewURL),
           let image = NSImage(data: data)
        {
            return image
        }
        if !workspacePreviewImageData.isEmpty,
           let image = NSImage(data: workspacePreviewImageData)
        {
            return image
        }
        if FileManager.default.fileExists(atPath: storageURL.path) {
            return NSWorkspace.shared.icon(forFile: storageURL.path)
        }
        return NSImage()
    }

    var shouldClean: Bool {
        if !FileManager.default.fileExists(atPath: storageURL.path) { return true }
        let keepInterval = TrayDrop.shared.keepInterval
        guard keepInterval > 0 else { return true } // avoid non-reasonable value deleting user's files
        if Date().timeIntervalSince(copiedDate) > TrayDrop.shared.keepInterval { return true }
        return false
    }
}
