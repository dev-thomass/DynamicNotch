//
//  ClaudeUsageWidget.swift
//  DynamicNotch
//
//  Quota du forfait Claude (Max/Pro) : % de la session 5 h et de la semaine,
//  avec compte à rebours avant réinitialisation.
//
//  Source : token OAuth de Claude Code dans le Trousseau ("Claude Code-
//  credentials[-suffixe]"), puis endpoint officiel api.anthropic.com/api/
//  oauth/usage. Le token ne sert qu'à cet appel ; s'il est expiré il est
//  rafraîchi en mémoire uniquement (le Trousseau n'est jamais modifié).
//

import Combine
import Security
import SwiftUI

@MainActor
final class ClaudeUsageModel: ObservableObject {
    static let shared = ClaudeUsageModel()

    struct Window {
        let label: String
        let pct: Double
        let resetsAt: Date?
    }

    @Published private(set) var session: Window?
    @Published private(set) var week: Window?
    @Published private(set) var error: String?
    @Published private(set) var refreshing = false

    /// Entrées Trousseau possibles : l'installation active suffixe la sienne.
    private let keychainServices = [
        "Claude Code-credentials-5839aa1d",
        "Claude Code-credentials",
    ]
    private let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e" // client public Claude Code

    /// Token rafraîchi gardé en mémoire uniquement.
    private var freshToken: (value: String, expires: Date)?
    private var timer: AnyCancellable?

    private init() {
        timer = Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.refresh() } }
    }

    // MARK: - Credentials

    private struct Creds {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    private func keychainJSON(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func loadCreds() -> Creds? {
        var best: Creds?
        for service in keychainServices {
            guard let data = keychainJSON(service: service),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = root["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String
            else { continue }
            let expMs = oauth["expiresAt"] as? Double
            let creds = Creds(
                accessToken: token,
                refreshToken: oauth["refreshToken"] as? String,
                expiresAt: expMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
            // On garde le token qui expire le plus tard (= le plus récent).
            if best == nil || (creds.expiresAt ?? .distantPast) > (best!.expiresAt ?? .distantPast) {
                best = creds
            }
        }
        return best
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else { throw URLError(.userAuthenticationRequired) }
        let ttl = (json["expires_in"] as? Double) ?? 3600
        freshToken = (token, Date().addingTimeInterval(ttl - 60))
        return token
    }

    private func usableToken() async throws -> String {
        if let fresh = freshToken, fresh.expires > Date() { return fresh.value }
        guard let creds = loadCreds() else { throw URLError(.userAuthenticationRequired) }
        if let exp = creds.expiresAt, exp < Date() {
            guard let rt = creds.refreshToken else { throw URLError(.userAuthenticationRequired) }
            return try await refreshAccessToken(rt)
        }
        return creds.accessToken
    }

    // MARK: - Fetch

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let token = try await usableToken()
            var raw: [String: Any]
            do {
                raw = try await callUsage(token: token)
            } catch let e as URLError where e.code == .userAuthenticationRequired {
                // Token du Trousseau rejeté → refresh forcé puis nouvel essai.
                guard let rt = loadCreds()?.refreshToken else { throw e }
                raw = try await callUsage(token: refreshAccessToken(rt))
            }
            parse(raw)
            error = nil
        } catch {
            if session == nil { self.error = "Connexion Claude requise" }
        }
    }

    private func callUsage(token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw URLError(code == 401 ? .userAuthenticationRequired : .badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func parse(_ raw: [String: Any]) {
        func window(_ key: String, label: String) -> Window? {
            guard let w = raw[key] as? [String: Any],
                  let pct = w["utilization"] as? Double else { return nil }
            var date: Date?
            if let iso = w["resets_at"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = fmt.date(from: iso)
                if date == nil {
                    fmt.formatOptions = [.withInternetDateTime]
                    date = fmt.date(from: iso)
                }
            }
            return Window(label: label, pct: pct, resetsAt: date)
        }
        session = window("five_hour", label: "Session")
        week = window("seven_day", label: "Semaine")
    }
}

// MARK: - View

struct ClaudeUsageWidgetView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var model = ClaudeUsageModel.shared

    /// Tick pour rafraîchir le compte à rebours affiché.
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                Text("Claude")
                    .font(DS.Typography.captionSmall)
                Spacer()
                if let week = model.week {
                    Text("sem. \(Int(week.pct)) %")
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Color.textQuaternary)
                }
            }
            .foregroundStyle(DS.Color.textTertiary)

            if let s = model.session {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text("\(Int(s.pct)) %")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint(for: s.pct))
                    Text("utilisés")
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                bar(pct: s.pct)

                Text(resetLabel(s.resetsAt))
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(model.error ?? "Chargement…")
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .dsRimLight()
        .onAppear { Task { await model.refresh() } }
        .onReceive(clock) { now = $0 }
    }

    private func tint(for pct: Double) -> Color {
        if pct >= 90 { return DS.Color.destructive }
        if pct >= 70 { return DS.Color.warning }
        return DS.Color.brand
    }

    @ViewBuilder
    private func bar(pct: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.surfaceRaisedStrong)
                Capsule()
                    .fill(tint(for: pct))
                    .frame(width: max(4, geo.size.width * min(pct, 100) / 100))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: pct)
    }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "réinitialisé" }
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        return h > 0 ? "reset dans \(h) h \(String(format: "%02d", m))" : "reset dans \(m) min"
    }
}
