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
                // Quand le focus est demandé / repris, on (ré)active l'app
                // ET la fenêtre. Sans ça, Cmd+V (et tous les raccourcis
                // d'édition) ne fonctionnent pas : SwiftUI a besoin que
                // l'app `.accessory` soit explicitement active pour que les
                // events clavier système soient routés vers le TextEditor.
                .onChange(of: isFocused) { focused in
                    if focused { activateForEditing() }
                }
                // Bloquer la propagation du tap au handler global de
                // mouseDown qui ferait fermer la notch.
                .onTapGesture { activateForEditing() }
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
        // Defer focus + activation par 1 runloop tick pour que la fenêtre
        // ait le temps d'être présentée — puis on active explicitement
        // l'app + on rend la fenêtre key, sans quoi Cmd+V ne fonctionne
        // pas dans le TextEditor d'une app `.accessory`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            activateForEditing()
            isFocused = true
        }
    }

    /// Active l'app DynamicNotch + rend sa fenêtre key. Indispensable
    /// pour que les raccourcis clavier d'édition (Cmd+V, Cmd+C, Cmd+X,
    /// Cmd+A, etc.) soient routés vers le TextEditor.
    private func activateForEditing() {
        NSApp.activate(ignoringOtherApps: true)
        // Trouve la fenêtre `NotchWindow` qui héberge ce widget et la rend
        // key. `NSApp.keyWindow` peut être nil quand on vient juste
        // d'activer l'app — on cherche dans toutes les windows.
        for window in NSApp.windows where window is NotchWindow {
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
            break
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
