import AppKit
import Security

enum EmulatorID: String, Codable, CaseIterable, Identifiable {
    case retroarch, duckstation, pcsx2, rpcs3, shadps4, dolphin, ppsspp, flycast, azahar, xemu

    var id: String { rawValue }

    var name: String {
        switch self {
        case .retroarch: "RetroArch"
        case .duckstation: "DuckStation"
        case .pcsx2: "PCSX2"
        case .rpcs3: "RPCS3"
        case .shadps4: "shadPS4"
        case .dolphin: "Dolphin"
        case .ppsspp: "PPSSPP"
        case .flycast: "Flycast"
        case .azahar: "Azahar"
        case .xemu: "xemu"
        }
    }

    var systems: [System] { System.allCases.filter { $0.emulator == self } }

    var source: String {
        if let repo = githubRepo { return "github.com/\(repo)" }
        return self == .dolphin ? "dolphin-emu.org" : "buildbot.libretro.com"
    }

    var githubRepo: String? {
        switch self {
        case .duckstation: "stenzek/duckstation"
        case .pcsx2: "PCSX2/pcsx2"
        case .rpcs3: Releases.arch == "arm64" ? "RPCS3/rpcs3-binaries-mac-arm64" : "RPCS3/rpcs3-binaries-mac"
        case .shadps4: "shadps4-emu/shadPS4"
        case .ppsspp: "hrydgard/ppsspp"
        case .flycast: "flyinghead/flycast"
        case .azahar: "azahar-emu/azahar"
        case .xemu: "xemu-project/xemu"
        case .retroarch, .dolphin: nil
        }
    }

    /// Picks the macOS build out of a GitHub release's assets.
    func matchesAsset(_ name: String) -> Bool {
        switch self {
        case .duckstation: name == "duckstation-mac-release.zip"
        case .pcsx2: name.hasSuffix("-macos-Qt.tar.xz")
        case .rpcs3: name.hasSuffix(".7z")
        case .shadps4: name.hasPrefix("shadps4-macos-sdl-") && name.hasSuffix(".zip")
        case .ppsspp: name.hasPrefix("PPSSPPSDL-macOS") && name.hasSuffix(".zip")
        case .flycast: name.hasPrefix("flycast-macOS") && name.hasSuffix(".zip")
        case .azahar: name.hasPrefix("azahar-macos-universal-") && name.hasSuffix(".zip")
        case .xemu: name.hasSuffix("-macos-universal.zip")
        case .retroarch, .dolphin: false
        }
    }

    /// shadPS4 ships a bare executable; everything else ships an .app.
    var binaryName: String? { self == .shadps4 ? "shadps4" : nil }

    /// Command-line arguments that boot `game`, checked against each emulator's own argument parser.
    func arguments(game: URL, core: URL?) -> [String] {
        switch self {
        case .retroarch: ["-L", core?.path ?? "", game.path]
        case .duckstation, .pcsx2: ["--", game.path]
        case .rpcs3, .ppsspp, .flycast, .azahar: [game.path]
        case .shadps4: ["-g", game.path]
        case .dolphin: ["-e", game.path]
        case .xemu: ["-dvd_path", game.path]
        }
    }
}

struct Release: Equatable {
    let version: String
    let url: URL
}

enum Releases {
    static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    static func latest(_ id: EmulatorID) async throws -> Release {
        switch id {
        case .retroarch: try await retroArch()
        case .dolphin: try await dolphin()
        default: try await github(id)
        }
    }

    static func coreURL(_ core: String) -> URL {
        URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/\(core)_libretro.dylib.zip")!
    }

    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let updated_at: String
        }
        let tag_name: String
        let assets: [Asset]
    }

    static func github(_ id: EmulatorID) async throws -> Release {
        guard let repo = id.githubRepo else { throw CartridgeError("\(id.name) isn't released on GitHub") }
        let data = try await Net.data(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        return try pick(id, fromGitHub: data)
    }

    static func pick(_ id: EmulatorID, fromGitHub data: Data) throws -> Release {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { id.matchesAsset($0.name) }) else {
            throw CartridgeError("The latest \(id.name) release (\(release.tag_name)) has no macOS download")
        }
        // The link comes out of an API response, so check it still points at the release we asked about rather than
        // trusting whatever host the JSON names.
        let expected = "https://github.com/\(id.githubRepo ?? "")/releases/download/"
        guard asset.browser_download_url.absoluteString.lowercased().hasPrefix(expected.lowercased()) else {
            throw CartridgeError("The \(id.name) download link points at \(asset.browser_download_url.host ?? "an unknown host"), not \(id.source)")
        }
        return Release(version: version(asset: asset.name, tag: release.tag_name, updated: asset.updated_at), url: asset.browser_download_url)
    }

    /// The version number in the asset name, else the tag, else the upload date (DuckStation's rolling "latest" release).
    static func version(asset: String, tag: String, updated: String) -> String {
        if let match = asset.firstMatch(of: #/\d+(?:\.\d+)+(?:-\d+)?/#) { return String(match.0) }
        if tag.first?.isNumber == true { return tag }
        return String(updated.prefix(10))
    }

    struct DolphinUpdate: Decodable {
        struct Artifact: Decodable {
            let system: String
            let url: URL
        }
        let shortrev: String
        let artifacts: [Artifact]
    }

    static func dolphin() async throws -> Release {
        try pick(fromDolphin: await Net.data(URL(string: "https://dolphin-emu.org/update/latest/beta")!))
    }

    static func pick(fromDolphin data: Data) throws -> Release {
        let update = try JSONDecoder().decode(DolphinUpdate.self, from: data)
        guard let mac = update.artifacts.first(where: { $0.system.contains("macOS") && $0.url.pathExtension == "dmg" }) else {
            throw CartridgeError("Dolphin \(update.shortrev) has no macOS download")
        }
        // Dolphin's update service names a full URL, so it decides where Cartridge downloads from. Keep it on their
        // own servers: the builds live on dl.dolphin-emu.org.
        let host = mac.url.host?.lowercased() ?? ""
        guard mac.url.scheme == "https", host == "dolphin-emu.org" || host.hasSuffix(".dolphin-emu.org") else {
            throw CartridgeError("Dolphin's update service offered a download from \(mac.url.host ?? "an unknown host"), not dolphin-emu.org")
        }
        return Release(version: update.shortrev, url: mac.url)
    }

    static func retroArch() async throws -> Release {
        let listing = String(decoding: try await Net.data(URL(string: "https://buildbot.libretro.com/stable/")!), as: UTF8.self)
        for version in retroArchVersions(in: listing).prefix(3) {
            let url = URL(string: "https://buildbot.libretro.com/stable/\(version)/apple/osx/universal/RetroArch_Metal.dmg")!
            if await Net.exists(url) { return Release(version: version, url: url) }
        }
        throw CartridgeError("Couldn't find a macOS build of RetroArch on buildbot.libretro.com")
    }

    /// Stable version folders in the buildbot listing, newest first.
    static func retroArchVersions(in listing: String) -> [String] {
        let versions = Set(listing.matches(of: #/stable/(\d{1,4})\.(\d{1,4})\.(\d{1,4})/#).map { [Int($0.1)!, Int($0.2)!, Int($0.3)!] })
        return versions.sorted { $1.lexicographicallyPrecedes($0) }.map { $0.map(String.init).joined(separator: ".") }
    }
}

/// Checks the code signature of a downloaded emulator. Cartridge fetches these itself, so macOS never marks them as
/// downloaded from the internet and Gatekeeper never looks at them.
enum CodeSignature {
    /// The Team ID the code is signed with, or nil when it is unsigned or only ad-hoc signed. Never throws: this is
    /// what an already-installed copy is asked for, and a copy whose signature has since broken still has to answer.
    static func team(of url: URL) -> String? {
        guard let (_, team) = signing(of: url) else { return nil }
        return team
    }

    /// Same, but a signature that doesn't match what it signs means a damaged or tampered download, so refuse it.
    /// Unsigned and ad-hoc builds have nothing to check against - several emulators ship that way - and pass.
    static func verifiedTeam(of url: URL, name: String) throws -> String? {
        guard let (code, team) = signing(of: url), team != nil else { return nil }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            throw CartridgeError("The \(name) download is signed, but the signature doesn't match what was downloaded "
                                 + "(OSStatus \(status)). It may be damaged or tampered with, so Cartridge didn't install it.")
        }
        return team
    }

    /// Why `replacement` must not be installed over `installed`, or nil when the signer hasn't changed.
    /// A release signed by somebody else - or suddenly signed by nobody - is not the same release.
    static func changedSigner(installed: String?, replacement: String?) -> String? {
        guard let installed, installed != replacement else { return nil }
        return "it is signed by \(replacement.map { "team \($0)" } ?? "nobody") instead of team \(installed)"
    }

    private static func signing(of url: URL) -> (SecStaticCode, String?)? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (code, (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}

enum Archive {
    static func extract(_ archive: URL, into dir: URL) async throws {
        let name = archive.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") {
            // ditto keeps the symlinks and permissions app bundles depend on.
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
        } else if name.hasSuffix(".dmg") {
            let mount = archive.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            // "Y" accepts a licence prompt if the image has one.
            try await Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, archive.path], input: "Y\n")
            do {
                let apps = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
                guard !apps.isEmpty else { throw CartridgeError("\(archive.lastPathComponent) contains no app") }
                for app in apps {
                    try await Shell.run("/usr/bin/ditto", [app.path, dir.appendingPathComponent(app.lastPathComponent).path])
                }
            } catch {
                _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                throw error
            }
            _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        } else {
            // bsdtar reads .tar.xz and .7z alike.
            try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", dir.path])
        }
    }
}

@MainActor @Observable
final class Installer {
    /// Progress from 0 to 1 for each running job, keyed by emulator id or "core:<name>".
    private(set) var jobs: [String: Double] = [:]
    private(set) var latest: [EmulatorID: Release] = [:]
    private(set) var checkErrors: [EmulatorID: String] = [:]
    private(set) var checking = false
    /// Bumped whenever something is installed or removed, so views re-read the disk.
    private(set) var revision = 0
    @ObservationIgnored private var running: [String: Task<Void, Error>] = [:]

    nonisolated static func folder(_ id: EmulatorID) -> URL {
        Paths.emulators.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    /// Kept apart from RetroArch's own folder so updating RetroArch keeps its cores.
    nonisolated static var coresFolder: URL {
        Paths.emulators.appendingPathComponent("retroarch-cores", isDirectory: true)
    }

    nonisolated static func coreURL(_ core: String) -> URL {
        coresFolder.appendingPathComponent("\(core)_libretro.dylib")
    }

    func installedVersion(_ id: EmulatorID) -> String? {
        _ = revision
        guard executable(id) != nil else { return nil }
        return try? String(contentsOf: Self.folder(id).appendingPathComponent("version.txt"), encoding: .utf8)
    }

    /// The .app bundle or binary to launch, if installed.
    func executable(_ id: EmulatorID) -> URL? {
        _ = revision
        return Self.locate(id, in: Self.folder(id))
    }

    func hasCore(_ core: String) -> Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: Self.coreURL(core).path)
    }

    func isReady(for system: System) -> Bool {
        executable(system.emulator) != nil && (system.core.map(hasCore) ?? true)
    }

    func updateAvailable(_ id: EmulatorID) -> Bool {
        guard let installed = installedVersion(id), let latest = latest[id] else { return false }
        return installed != latest.version
    }

    /// Finds the shallowest .app (or the named binary) under `root`.
    nonisolated static func locate(_ id: EmulatorID, in root: URL) -> URL? {
        let fm = FileManager.default
        var queue = [(root, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if let binary = id.binaryName {
                    if !isDir, item.lastPathComponent == binary, fm.isExecutableFile(atPath: item.path) { return item }
                } else if isDir, item.pathExtension == "app" {
                    return item
                }
                if isDir, item.pathExtension != "app", depth < 3 { queue.append((item, depth + 1)) }
            }
        }
        return nil
    }

    func install(_ id: EmulatorID) async throws {
        try await job(id.rawValue) { progress in
            try await Self.performInstall(id, progress: progress)
        }
    }

    func installCore(_ core: String) async throws {
        try await job("core:\(core)") { progress in
            try await Self.performCoreInstall(core, progress: progress)
        }
    }

    func cancel(_ key: String) {
        running[key]?.cancel()
    }

    func uninstall(_ id: EmulatorID) throws {
        defer { revision += 1 }
        let fm = FileManager.default
        var folders = [Self.folder(id)]
        if id == .retroarch { folders.append(Self.coresFolder) }
        for folder in folders where fm.fileExists(atPath: folder.path) {
            try fm.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    func checkForUpdates() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        await withTaskGroup(of: (EmulatorID, Result<Release, Error>).self) { group in
            for id in EmulatorID.allCases {
                group.addTask {
                    do { return (id, .success(try await Releases.latest(id))) } catch { return (id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let release):
                    latest[id] = release
                    checkErrors[id] = nil
                case .failure(let error):
                    checkErrors[id] = error.localizedDescription
                }
            }
        }
    }

    /// Runs one job per key; a second caller for the same key waits on the first.
    private func job(_ key: String, _ work: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void) async throws {
        if let existing = running[key] { return try await existing.value }
        jobs[key] = 0
        let report: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                if self?.jobs[key] != nil { self?.jobs[key] = value }
            }
        }
        let task = Task.detached { try await work(report) }
        running[key] = task
        defer {
            running[key] = nil
            jobs[key] = nil
            revision += 1
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Downloads into a staging folder and only replaces the installed copy once the new one is complete.
    nonisolated static func performInstall(_ id: EmulatorID, progress: @escaping @Sendable (Double) -> Void) async throws {
        let release = try await Releases.latest(id)
        let fm = FileManager.default
        let staging = Paths.emulators.appendingPathComponent(".staging-\(id.rawValue)-\(UUID().uuidString)", isDirectory: true)
        let contents = staging.appendingPathComponent("contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let archive = staging.appendingPathComponent(release.url.lastPathComponent)
        try await Net.download(release.url, to: archive) { progress($0 * 0.9) }
        try Task.checkCancellation()
        try await Archive.extract(archive, into: contents)
        guard let downloaded = locate(id, in: contents) else {
            throw CartridgeError("The \(id.name) download didn't contain the app Cartridge expected")
        }
        let target = folder(id)
        // Whoever signed the copy already installed has to be whoever signed this one. It is the one thing an update
        // can be held to without knowing each project's signing identity in advance.
        let installedTeam = locate(id, in: target).flatMap(CodeSignature.team)
        let newTeam = try CodeSignature.verifiedTeam(of: downloaded, name: id.name)
        if let changed = CodeSignature.changedSigner(installed: installedTeam, replacement: newTeam) {
            throw CartridgeError("Cartridge didn't install this \(id.name) update because \(changed). "
                                 + "Uninstall \(id.name) first if you trust the new one.")
        }
        try release.version.write(to: contents.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: contents, to: target)
        progress(1)
    }

    nonisolated static func performCoreInstall(_ core: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let staging = Paths.emulators.appendingPathComponent(".staging-core-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("\(core).zip")
        try await Net.download(Releases.coreURL(core), to: archive) { progress($0 * 0.95) }
        try Task.checkCancellation()
        try await Archive.extract(archive, into: staging)
        let dylib = staging.appendingPathComponent("\(core)_libretro.dylib")
        guard fm.fileExists(atPath: dylib.path) else { throw CartridgeError("The \(core) core download didn't contain \(dylib.lastPathComponent)") }
        try fm.createDirectory(at: coresFolder, withIntermediateDirectories: true)
        let target = coreURL(core)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: dylib, to: target)
        progress(1)
    }

    /// Starts an emulator and calls `onExit` with its pid when it quits.
    func launch(_ id: EmulatorID, arguments: [String], onExit: @escaping @MainActor (pid_t) -> Void) async throws -> pid_t {
        guard let executable = executable(id) else { throw CartridgeError("\(id.name) isn't installed") }
        if id.binaryName == nil {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = arguments
            // Arguments only reach a fresh process; an already-open emulator would ignore them.
            config.createsNewApplicationInstance = true
            config.activates = true
            let app = try await NSWorkspace.shared.openApplication(at: executable, configuration: config)
            return app.processIdentifier
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        let logs = try Paths.ensure(Paths.root.appendingPathComponent("Logs", isDirectory: true))
        let log = logs.appendingPathComponent("\(id.rawValue).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { process in
            try? handle.close()
            let pid = process.processIdentifier
            Task { @MainActor in onExit(pid) }
        }
        try process.run()
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
        return process.processIdentifier
    }

    /// Hands a PS3UPDAT.PUP to RPCS3's firmware installer.
    func installPS3Firmware(_ pup: URL) async throws {
        if executable(.rpcs3) == nil { try await install(.rpcs3) }
        _ = try await launch(.rpcs3, arguments: ["--installfw", pup.path]) { _ in }
    }
}
