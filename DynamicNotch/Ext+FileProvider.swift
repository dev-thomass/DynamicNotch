//
//  Ext+FileProvider.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    /// Maximum time we'll wait for a single provider load to signal completion.
    /// Drag from a remote/cloud source can be slow but 10 s is way past
    /// "the user is still waiting".
    private static let loadTimeout: DispatchTimeInterval = .seconds(10)

    private func duplicateToOurStorage(_ url: URL?) throws -> URL {
        guard let url else { throw DynamicNotchError.providerLoadFailed }
        let temp = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.createDirectory(
            at: temp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: url, to: temp)
        return temp
    }

    /// Tries to obtain a local file URL for this provider.
    ///
    /// Two strategies are attempted in order:
    /// 1. `loadObject(ofClass: URL.self)` — works for file-URL providers (Finder).
    /// 2. `loadInPlaceFileRepresentation` — works for sandboxed sources (browsers,
    ///    cloud apps) that hand us a NSItemProvider with no URL representation.
    ///
    /// Both calls are guarded by a hard timeout so a misbehaving provider can't
    /// freeze the worker queue forever.
    func convertToFilePathThatIsWhatWeThinkItWillWorkWithDynamicNotch() -> URL? {
        if let url = waitForURL(via: { completion in
            _ = self.loadObject(ofClass: URL.self) { item, _ in
                completion(try? self.duplicateToOurStorage(item))
            }
        }) {
            return url
        }
        return waitForURL(via: { completion in
            self.loadInPlaceFileRepresentation(
                forTypeIdentifier: UTType.data.identifier
            ) { input, _, _ in
                completion(try? self.duplicateToOurStorage(input))
            }
        })
    }

    /// Bridges an asynchronous loader callback into a synchronous wait,
    /// bounded by `loadTimeout`. Logs and returns `nil` on timeout.
    ///
    /// The completion handed to `trigger` is `@escaping` because the underlying
    /// NSItemProvider loaders (`loadObject` / `loadInPlaceFileRepresentation`)
    /// store the callback and invoke it after the call returns.
    private func waitForURL(
        via trigger: (@escaping (URL?) -> Void) -> Void
    ) -> URL? {
        let sem = DispatchSemaphore(value: 0)
        var result: URL?
        // Guard against the loader calling back twice.
        let signalOnce = { [weak sem] (url: URL?) in
            if result == nil { result = url }
            sem?.signal()
        }
        trigger(signalOnce)

        switch sem.wait(timeout: .now() + Self.loadTimeout) {
        case .success:
            return result
        case .timedOut:
            Log.drop.error("NSItemProvider load timed out after 10s")
            return nil
        }
    }
}

extension [NSItemProvider] {
    /// Noms / patterns à TOUJOURS ignorer dans un drop.
    /// Quand on drag un dossier, le système peut ramener avec lui ses
    /// fichiers cachés / système (`.DS_Store`, `__MACOSX`, AppleDouble
    /// `._*`). On les filtre pour ne pas polluer le tray.
    private static let ignoredFileNames: Set<String> = [".DS_Store", "Thumbs.db", "__MACOSX"]

    private static func shouldIgnore(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if ignoredFileNames.contains(name) { return true }
        if name.hasPrefix("._") { return true } // AppleDouble side-files
        if name.hasPrefix(".") { return true }  // Hidden files Unix-style
        return false
    }

    func interfaceConvert() -> [URL]? {
        var loaded: [URL] = []
        var failures = 0
        for provider in self {
            guard let url = provider.convertToFilePathThatIsWhatWeThinkItWillWorkWithDynamicNotch()
            else {
                failures += 1
                continue
            }
            // Le filtrage hidden NE compte PAS comme un échec — c'est une
            // suppression intentionnelle pour éviter de polluer le tray.
            if Self.shouldIgnore(url) {
                Log.drop.info("ignored hidden/system file: \(url.lastPathComponent, privacy: .public)")
                continue
            }
            loaded.append(url)
        }
        if failures > 0 {
            Log.drop.error("interfaceConvert: \(failures) of \(self.count) provider(s) failed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAlert.popError(DynamicNotchError.multipleFilesFailedToLoad)
            }
            return nil
        }
        return loaded
    }
}
