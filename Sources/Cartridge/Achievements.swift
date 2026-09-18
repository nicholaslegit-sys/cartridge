import CommonCrypto
import CryptoKit
import Foundation

/// One RetroAchievements sign-in, handed to every emulator that supports it.
///
/// Signing in trades the password for a login token with the same request the emulators send themselves (rcheevos'
/// login2). The password is never stored. The token lives in the Keychain and is written into each emulator's own
/// settings in the form that emulator reads:
///
/// - RetroArch: `cheevos_username` and `cheevos_token` in retroarch.cfg.
/// - DuckStation: [Cheevos] in settings.ini, with the token encrypted exactly as DuckStation encrypts it - AES-128-CBC
///   under a key stretched from this Mac's hardware UUID and the username. A plain token is treated by DuckStation as
///   an old config and it asks to sign in again, which is what tools that skip this step run into.
/// - PCSX2: [Achievements] in PCSX2.ini. PCSX2 moves the token into its secrets.ini on its next start.
///
/// An emulator only gets the sign-in when nobody else is signed in there, so an account chosen inside the emulator
/// is left alone, and never while it's running, since it writes its settings back when it quits.
@MainActor @Observable
final class Achievements {
    static let account = "retroachievements-token"
    static let usernameKey = "achievements.username"
    static let supported: [EmulatorID] = [.retroarch, .duckstation, .pcsx2]
    nonisolated static let site = URL(string: "https://retroachievements.org")!

    private(set) var username: String?
    private(set) var signingIn = false
    /// What happened in each emulator the last time the sign-in was handed out.
    private(set) var status: [EmulatorID: String] = [:]
    var error: String?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.usernameKey)
        username = saved != nil && Keychain.get(Self.account) != nil ? saved : nil
    }

    // MARK: Signing in

    func signIn(user: String, password: String) async {
        guard !signingIn else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            let (data, _) = try await URLSession.shared.data(for: Self.loginRequest(user: user, password: password))
            let login = try Self.login(from: data)
            try Keychain.set(login.token, for: Self.account)
            UserDefaults.standard.set(login.user, forKey: Self.usernameKey)
            username = login.user
            error = nil
            applyToEmulators()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Forgets the sign-in, and takes it back out of the emulators it was given to - only where it's still ours.
    func signOut() {
        if let username {
            for id in Self.supported where !SaveBackups.isRunning(id) {
                _ = try? Self.edit(id) { text in Self.remove(user: username, from: text, emulator: id) }
            }
        }
        try? Keychain.set(nil, for: Self.account)
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
        username = nil
        status = [:]
    }

    /// Reads who each emulator is signed in as, without changing anything.
    func refreshStatus() {
        for id in Self.supported {
            guard let file = Self.settingsFile(id), let text = try? String(contentsOf: file, encoding: .utf8) else {
                status[id] = "Not opened yet - it gets the sign-in after you first play a game with it."
                continue
            }
            switch Self.signedIn(id, in: text) {
            case let name? where !name.isEmpty && name.caseInsensitiveCompare(username ?? "") == .orderedSame:
                status[id] = "Signed in as \(name)."
            case let name? where !name.isEmpty:
                status[id] = "Signed in as \(name), chosen inside \(id.name)."
            default:
                status[id] = username == nil ? "Not signed in." : "Not signed in yet - use Update Emulators Now."
            }
        }
    }

    // MARK: Handing it to the emulators

    /// Writes the sign-in into every supported emulator that has settings to write into.
    func applyToEmulators() {
        for id in Self.supported { apply(to: id) }
    }

    /// Writes the sign-in into one emulator's settings. Also called when an emulator quits, which is how one that
    /// had never been opened before gets it: it creates its settings on that first run.
    func apply(to id: EmulatorID) {
        guard let username, let token = Keychain.get(Self.account) else { return }
        if SaveBackups.isRunning(id) {
            status[id] = "Open right now - it gets the sign-in when it quits."
            return
        }
        do {
            var skipped: String?
            let found = try Self.edit(id) { text in
                if let current = Self.signedIn(id, in: text), !current.isEmpty, current.caseInsensitiveCompare(username) != .orderedSame {
                    skipped = current
                    return text
                }
                return Self.signIn(id, text: text, user: username, token: token, now: Date(), machineKey: Self.machineKey())
            }
            status[id] = !found ? "Not opened yet - it gets the sign-in after you first play a game with it."
                : skipped.map { "Left signed in as \($0), the account chosen inside \(id.name)." }
                ?? "Signed in as \(username)."
        } catch {
            status[id] = "Couldn't update its settings: \(error.localizedDescription)"
        }
    }

    // MARK: The settings, per emulator

    nonisolated static func settingsFile(_ id: EmulatorID) -> URL? {
        switch id {
        case .retroarch: EmulatorData.retroArchConfig
        case .duckstation: EmulatorData.duckStationSettings
        case .pcsx2: EmulatorData.pcsx2Settings
        default: nil
        }
    }

    @discardableResult
    nonisolated static func edit(_ id: EmulatorID, _ change: (String) -> String) throws -> Bool {
        guard let file = settingsFile(id) else { return false }
        return try EmulatorData.edit(file, change)
    }

    /// Who is signed in to RetroAchievements in an emulator's settings, if anyone.
    nonisolated static func signedIn(_ id: EmulatorID, in text: String) -> String? {
        switch id {
        case .retroarch: CfgFile.value("cheevos_username", in: text)
        case .duckstation: IniFile.value("Username", section: "Cheevos", in: text)
        case .pcsx2: IniFile.value("Username", section: "Achievements", in: text)
        default: nil
        }
    }

    nonisolated static func signIn(_ id: EmulatorID, text: String, user: String, token: String, now: Date, machineKey: String) -> String {
        let timestamp = String(Int(now.timeIntervalSince1970))
        switch id {
        case .retroarch:
            var text = CfgFile.set("cheevos_enable", "true", in: text)
            text = CfgFile.set("cheevos_username", user, in: text)
            return CfgFile.set("cheevos_token", token, in: text)
        case .duckstation:
            var text = IniFile.set("Enabled", "true", section: "Cheevos", in: text)
            text = IniFile.set("Username", user, section: "Cheevos", in: text)
            text = IniFile.set("Token", duckStationToken(token, user: user, machineKey: machineKey), section: "Cheevos", in: text)
            return IniFile.set("LoginTimestamp", timestamp, section: "Cheevos", in: text)
        case .pcsx2:
            var text = IniFile.set("Enabled", "true", section: "Achievements", in: text)
            text = IniFile.set("Username", user, section: "Achievements", in: text)
            text = IniFile.set("Token", token, section: "Achievements", in: text)
            return IniFile.set("LoginTimestamp", timestamp, section: "Achievements", in: text)
        default:
            return text
        }
    }

    /// Clears the sign-in from an emulator's settings if it's the one Cartridge put there.
    nonisolated static func remove(user: String, from text: String, emulator id: EmulatorID) -> String {
        guard signedIn(id, in: text)?.caseInsensitiveCompare(user) == .orderedSame else { return text }
        switch id {
        case .retroarch:
            return CfgFile.set("cheevos_token", "", in: CfgFile.set("cheevos_username", "", in: text))
        case .duckstation:
            return IniFile.set("Token", "", section: "Cheevos", in: IniFile.set("Username", "", section: "Cheevos", in: text))
        case .pcsx2:
            return IniFile.set("Token", "", section: "Achievements", in: IniFile.set("Username", "", section: "Achievements", in: text))
        default:
            return text
        }
    }

    // MARK: Talking to RetroAchievements

    /// rcheevos' login2: a form POST to dorequest.php with r, u and p.
    nonisolated static func loginRequest(user: String, password: String) -> URLRequest {
        var request = Net.request(site.appending(path: "dorequest.php"), method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Stricter than URLComponents, which leaves "+" alone - and a "+" in a form body means a space.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        request.httpBody = Data("r=login2&u=\(encode(user))&p=\(encode(password))".utf8)
        return request
    }

    struct LoginFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The user name (as RetroAchievements spells it) and token from a login response, or its error.
    nonisolated static func login(from data: Data) throws -> (user: String, token: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoginFailed(message: "RetroAchievements sent back something that wasn't a sign-in response.")
        }
        guard json["Success"] as? Bool == true, let token = json["Token"] as? String, !token.isEmpty,
              let user = json["User"] as? String else {
            throw LoginFailed(message: (json["Error"] as? String) ?? "RetroAchievements didn't accept that sign-in.")
        }
        return (user, token)
    }

    // MARK: DuckStation's token encryption

    /// This Mac's hardware UUID as lowercase hex, which is what DuckStation keys its token encryption with.
    nonisolated static func machineKey() -> String {
        var uuid = [UInt8](repeating: 0, count: 16)
        var wait = timespec(tv_sec: 0, tv_nsec: 0)
        guard gethostuuid(&uuid, &wait) == 0 else { return String(format: "%08X", gethostid()) }
        return uuid.map { String(format: "%02x", $0) }.joined()
    }

    /// DuckStation's EncryptLoginToken: SHA-256 of the machine key and username, rehashed 100 times; the first 16
    /// bytes are the AES-128 key and the last 16 the CBC IV; the token is zero-padded to a whole block, and the
    /// result is base64.
    nonisolated static func duckStationToken(_ token: String, user: String, machineKey: String) -> String {
        guard !token.isEmpty, !user.isEmpty else { return "" }
        var key = Array(SHA256.hash(data: Data(machineKey.utf8) + Data(user.utf8)))
        for _ in 0..<100 { key = Array(SHA256.hash(data: Data(key))) }
        var plain = Array(token.utf8)
        plain += [UInt8](repeating: 0, count: (16 - plain.count % 16) % 16)
        var output = [UInt8](repeating: 0, count: plain.count)
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
                             key, kCCKeySizeAES128, Array(key[16..<32]),
                             plain, plain.count, &output, output.count, &written)
        guard status == kCCSuccess else { return "" }
        return Data(output.prefix(written)).base64EncodedString()
    }
}
