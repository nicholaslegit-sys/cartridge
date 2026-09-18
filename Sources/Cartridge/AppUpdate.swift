import Foundation

/// Notices when a newer Cartridge has been released.
///
/// The emulators update through Cartridge, but Cartridge itself had nothing. This reads the project's latest GitHub
/// release, the same way the emulator installer reads theirs. While the repository is private GitHub answers "not
/// found" to anyone not signed in, so the automatic check stays quiet until releases are public.
@MainActor @Observable
final class AppUpdate {
    struct Available: Equatable {
        let version: String
        let page: URL
    }

    private(set) var available: Available?
    private(set) var checking = false
    /// What a check the player asked for found, for its alert.
    var report: String?

    static let lastCheckKey = "update.lastCheck"
    static let api = URL(string: "https://api.github.com/repos/nicholaslegit-sys/cartridge/releases/latest")!

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// On its own, at most once a day and silently. When the player asks, always, and it says what it found.
    func check(userAsked: Bool = false) async {
        let defaults = UserDefaults.standard
        if !userAsked, let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: Net.request(Self.api))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                if userAsked {
                    report = status == 404 ? "Cartridge's releases aren't public yet, so there's nothing to compare with." : "GitHub answered HTTP \(status)."
                }
                return
            }
            defaults.set(Date(), forKey: Self.lastCheckKey)
            available = try Self.newer(than: Self.current, in: data)
            if userAsked {
                report = available.map { "Cartridge \($0.version) is out. You have \(Self.current)." } ?? "You have the latest Cartridge, \(Self.current)."
            }
        } catch {
            if userAsked { report = "Couldn't check: \(error.localizedDescription)" }
        }
    }

    /// The release in a GitHub API response, if it's newer than `current`.
    nonisolated static func newer(than current: String, in data: Data) throws -> Available? {
        let release = try JSONDecoder().decode(Releases.GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard isNewer(version, than: current) else { return nil }
        return Available(version: version, page: About.repository.appending(path: "releases/tag/\(release.tag_name)"))
    }

    /// Compares dotted version numbers part by part, so 1.10.0 is newer than 1.9.3.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
