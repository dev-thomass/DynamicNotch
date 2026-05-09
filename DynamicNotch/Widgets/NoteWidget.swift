//
//  NoteWidget.swift
//  DynamicNotch
//
//  Quick-note widget. Plain UTF-8 file persisted under
//  ~/Documents/DynamicNotch/Config/quickNote.txt with a 0.5 s debounce so
//  every keystroke doesn't hit the disk.
//

import Combine
import SwiftUI

private let noteFileURL = documentsDirectory.appendingPathComponent("Config/quickNote.txt")

struct NoteView: View {
    @StateObject var vm: NotchViewModel
    @State private var content: String = ""
    @FocusState private var isFocused: Bool
    @State private var saveTask: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 4) {
            // ─── header (label + clear) ─────────────────────────────────────
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "note.text")
                    .font(.system(size: 9, weight: .semibold))
                Text("Note rapide")
                    .font(DS.Typography.captionSmall)
                Spacer()
                if !content.isEmpty {
                    clearButton
                }
            }
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.top, DS.Spacing.xs)

            // ─── editor ──────────────────────────────────────────────────────
            TextEditor(text: $content)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DS.Color.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, DS.Spacing.xs)
                .onChange(of: content) { newValue in
                    debounceSave(newValue)
                }
        }
        // Explicit fill so this tile always claims the same height as its
        // siblings. Without it, the TextEditor's intrinsic small size let the
        // whole panel shrink on pages that contain a note.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .dsRimLight()
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .accessibilityLabel(Text("Note rapide"))
    }

    // MARK: lifecycle

    private func handleAppear() {
        content = loadNote()
        // Defer focus by one runloop tick so the host window has time to
        // become key — otherwise the text view doesn't get firstResponder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isFocused = true
        }
    }

    private func handleDisappear() {
        saveTask?.cancel()
        saveNote(content)
    }

    // MARK: clear

    private var clearButton: some View {
        Button {
            content = ""
            saveTask?.cancel()
            saveNote("")
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Color.textTertiary)
        .accessibilityLabel(Text("Effacer la note"))
    }

    // MARK: persistence

    private func debounceSave(_ text: String) {
        saveTask?.cancel()
        let task = DispatchWorkItem { saveNote(text) }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func loadNote() -> String {
        guard let data = try? Data(contentsOf: noteFileURL),
              let str = String(data: data, encoding: .utf8)
        else { return "" }
        // Legacy: very old builds wrapped the body in JSON-style quotes.
        if str.hasPrefix("\""), str.hasSuffix("\"") {
            return String(str.dropFirst().dropLast())
        }
        return str
    }

    private func saveNote(_ text: String) {
        do {
            try FileManager.default.createDirectory(
                at: noteFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: noteFileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.app.error("save note failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
