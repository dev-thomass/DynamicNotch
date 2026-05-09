//
//  SingleInstance.swift
//  DynamicNotch
//
//  Robust single-instance enforcement via BSD `flock(2)` + a Darwin
//  distributed notification used to "wake up" the existing instance.
//
//  Why not the previous `pidFile` + 1-Hz polling approach?
//  - The poll could kill the live instance on disk corruption / removed file.
//  - Two instances launched in parallel could kill each other (race condition).
//  - The lock file is readable by other local users → trivial DoS by writing
//    a random PID into it.
//  - 1-Hz timer wakes the CPU forever for no good reason.
//
//  This implementation:
//  - Uses an exclusive non-blocking flock on a sentinel file.
//  - When the lock is unavailable (another instance is alive), posts a
//    `wakeUp` distributed notification and exits cleanly.
//  - The live instance observes that notification and re-opens the notch.
//  - The lock is released automatically when the process exits (kernel-level).
//

import AppKit
import Darwin
import Foundation

enum SingleInstance {

    // MARK: configuration

    /// Distributed notification name used to wake the existing instance.
    static let wakeUpNotification = Notification.Name("app.notchdrop.wakeUp")

    /// Path to the lock sentinel. Lives next to other app config under ~/Documents/DynamicNotch.
    private static var lockURL: URL {
        documentsDirectory.appendingPathComponent(".instance.lock")
    }

    // MARK: lock state

    /// Held for the lifetime of the process. We never close it explicitly —
    /// the kernel releases the flock when the file descriptor is closed at exit.
    private nonisolated(unsafe) static var lockFD: Int32 = -1

    // MARK: API

    /// Attempt to claim the global app lock.
    ///
    /// - Returns: `true` if this is the live instance, `false` if another instance
    ///   is already running (in which case we've already posted a wake-up notification).
    static func acquire() -> Bool {
        // Make sure the parent directory exists (the same `documentsDirectory`
        // bootstrap from main.swift normally creates it, but be defensive).
        try? FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )

        let path = lockURL.path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            Log.lock.error("open(\(path, privacy: .public)) failed: errno=\(errno)")
            // We can't enforce single-instance — better to keep running than lock the user out.
            return true
        }

        // LOCK_EX | LOCK_NB → exclusive, non-blocking. EWOULDBLOCK means held.
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // We own the lock. Keep `fd` alive for the process lifetime.
            lockFD = fd
            Log.lock.info("acquired single-instance lock (fd=\(fd))")
            return true
        }

        // Another instance is alive. Tell it to surface itself, then exit.
        close(fd)
        Log.lock.notice("another instance is already running — posting wake-up notification")
        DistributedNotificationCenter.default().postNotificationName(
            wakeUpNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return false
    }
}
