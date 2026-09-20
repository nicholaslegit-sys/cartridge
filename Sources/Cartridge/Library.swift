import AppKit

struct Game: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var system: System
    var path: String
    /// Cartridge copied or downloaded these files itself, so removing the game trashes them.
    var managed: Bool
    var added = Date()
    var lastPlayed: Date?
    var playSeconds: Double = 0
    var developer: String?
    var homebrewSlug: String?
    var artChecked = false
    var overview: String?
    var publisher: String?
    var releaseYear: Int?
    var genres: String?
    var launchBoxID: Int?
    var igdbID: Int?
    /// A trailer, usually a YouTube link.
    var videoURL: String?
    /// Where the saved instruction booklet came from.
    var manualSource: String?
    /// What comparing the game's files with the known-good dump list found, and when.
    var dump: DumpCheck.Verdict?
    var dumpChecked: Date?
    /// Advanced Mode display settings for this game alone.
    var tweaks: DisplayTweaks?

    var url: URL { URL(fileURLWithPath: path) }
    var artURL: URL { Paths.art.appendingPathComponent("\(id.uuidString).png") }
    var labelArtURL: URL { Paths.art.appendingPathComponent("\(id.uuidString)-label.png") }
    var manualURL: URL { Paths.art.appendingPathComponent("\(id.uuidString)-manual.pdf") }
    /// Homebrew screenshots are pixel art and should scale without smoothing.
    var pixelArt: Bool { homebrewSlug != nil }
}

struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
    var system: System?
    /// The temporary folder this came out of a zip or 7z into; the game is moved out of it when it's added.
    var unpackedFolder: URL?
}

@MainActor @Observable
final class Library {
    var games: [Game] = []
    /// Start time of every game that is running right now.
    private(set) var sessions: [UUID: Date] = [:]
    /// What Cartridge is doing for a game before it starts ("Installing PCSX2…").
    private(set) var status: [UUID: String] = [:]
    /// Homebrew downloads in flight, by slug.
    private(set) var downloads: [String: Double] = [:]
    private(set) var copying: [String] = []
    private(set) var unpacking: [String] = []
    private(set) var artRevision = 0
    var pending: [PendingImport] = []
    /// A game waiting for the player to agree to download its emulator.
    var confirmingPlay: Game?
    var isPickingFiles = false
    /// Whether the demo library is showing instead of the player's own.
    private(set) var demoMode = Paths.isDemo
    var error: String?

    let installer = Installer()
    let artwork = ArtworkSources()
    let saves = SaveBackups()
    let achievements = Achievements()
    /// Progress of "Fetch Missing Artwork" across the library.
    private(set) var artworkProgress: (done: Int, total: Int)?
    @ObservationIgnored private var pids: [pid_t: UUID] = [:]
    /// Decoded covers, bounded so scrolling a big library doesn't hold every image it ever showed.
    @ObservationIgnored private let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    @ObservationIgnored private var noTrailer = Set<UUID>()
    @ObservationIgnored private var manualTasks: [UUID: Task<URL?, Never>] = [:]

    enum ManualStatus: Equatable {
        case searching, downloading(Double), failed(String)
    }
    /// Booklet lookups in progress or that didn't find anything, by game.
    private(set) var manualStatus: [UUID: ManualStatus] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        load()
        seedDemoIfEmpty()
        // Left over if Cartridge quit while an unpacked archive was waiting to be added.
        try? FileManager.default.removeItem(at: Paths.unpacking)
        Advanced.restoreLeftovers()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.ended(pid) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSessions() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Coming back from Finder is when new games have usually just been dropped in.
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastScan) > 30 else { return }
                Task { await self.scanGamesFolderIfEnabled() }
            }
        })
        Task {
            await fetchMissingArt()
            await scanGamesFolderIfEnabled()
        }
    }

    // MARK: Persistence

    private func load() {
        let file = Paths.libraryFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            games = try Self.decoder.decode([Game].self, from: Data(contentsOf: file))
            // Games added before Finder's "Game (USA) 2" duplicate suffix was recognised kept the " 2" in their
            // title, which reads as a sequel and throws off artwork and manual lookups.
            var healed = false
            for index in games.indices {
                let title = games[index].title
                let fresh = Detect.title(fromFilename: games[index].url.deletingPathExtension().lastPathComponent)
                if title != fresh, title.hasPrefix(fresh), title.dropFirst(fresh.count).wholeMatch(of: #/ (\d+|copy( \d+)?)/#) != nil {
                    games[index].title = fresh
                    healed = true
                }
            }
            if healed { save() }
        } catch {
            // Keep the unreadable file so the next save can't overwrite someone's library.
            let backup = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: backup)
            self.error = "Your library file couldn't be read, so it was set aside as \(backup.lastPathComponent). \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            _ = try Paths.ensure(Paths.library)
            try Self.encoder.encode(games).write(to: Paths.libraryFile, options: .atomic)
        } catch {
            self.error = "Couldn't save the library: \(error.localizedDescription)"
        }
    }

    // MARK: Demo Mode

    /// Swaps between the real library and the demo one. Not while a game is running: its play time belongs to the
    /// library it was started from.
    func setDemoMode(_ on: Bool) {
        guard on != Paths.isDemo, sessions.isEmpty else { return }
        UserDefaults.standard.set(on, forKey: Paths.demoKey)
        demoMode = on
        images.removeAllObjects()
        noTrailer = []
        manualTasks = [:]
        manualStatus = [:]
        pending = []
        games = []
        load()
        seedDemoIfEmpty()
        artRevision += 1
        Task { await fetchMissingArt() }
    }

    /// The demo library fills itself the first time it's shown, or again if its folder was cleared out.
    private func seedDemoIfEmpty() {
        guard Paths.isDemo, games.isEmpty else { return }
        games = Self.demoGames()
        save()
    }

    /// Well-known games as empty placeholder files, named the way No-Intro and Redump name them so their artwork
    /// can be found. They show off the shelf; they can't be played.
    nonisolated static let demoTitles: [(title: String, system: System, file: String)] = [
        ("Crash Bandicoot", .ps1, "Crash Bandicoot (USA).bin"),
        ("Final Fantasy VII", .ps1, "Final Fantasy VII (USA) (Disc 1).bin"),
        ("Shadow of the Colossus", .ps2, "Shadow of the Colossus (USA).iso"),
        ("Ico", .ps2, "Ico (USA).iso"),
        ("Metal Gear Solid 3 - Snake Eater", .ps2, "Metal Gear Solid 3 - Snake Eater (USA).iso"),
        ("Metroid Prime", .gamecube, "Metroid Prime (USA).iso"),
        ("The Legend of Zelda - The Wind Waker", .gamecube, "Legend of Zelda, The - The Wind Waker (USA).iso"),
        ("Super Mario Galaxy", .wii, "Super Mario Galaxy (USA).iso"),
        ("Halo - Combat Evolved", .xbox, "Halo - Combat Evolved (USA).iso"),
        ("Sonic Adventure", .dreamcast, "Sonic Adventure (USA).gdi"),
        ("Jet Set Radio", .dreamcast, "Jet Set Radio (USA).gdi"),
        ("NiGHTS into Dreams", .saturn, "NiGHTS into Dreams... (USA).cue"),
        ("Daxter", .psp, "Daxter (USA).iso"),
        ("Super Mario 64", .n64, "Super Mario 64 (USA).z64"),
        ("Super Metroid", .snes, "Super Metroid (Japan, USA) (En,Ja).sfc"),
        ("Sonic the Hedgehog 2", .genesis, "Sonic The Hedgehog 2 (World).md"),
    ]

    nonisolated static func demoGames(in games: URL = Paths.defaultGames) -> [Game] {
        let fm = FileManager.default
        return demoTitles.compactMap { demo in
            let folder = games.appendingPathComponent(demo.system.rawValue, isDirectory: true)
                .appendingPathComponent((demo.file as NSString).deletingPathExtension, isDirectory: true)
            let file = folder.appendingPathComponent(demo.file)
            guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                  fm.createFile(atPath: file.path, contents: nil) else { return nil }
            return Game(title: demo.title, system: demo.system, path: file.path, managed: true)
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func update(_ id: UUID, _ change: (inout Game) -> Void) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        change(&games[i])
        save()
    }

    func rename(_ game: Game, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(game.id) { $0.title = trimmed }
    }

    func setSystem(_ game: Game, _ system: System) {
        update(game.id) { $0.system = system }
    }

    // MARK: Importing

    /// Detects each item's system in the background and queues it for the review sheet. A zip or 7z holding a disc
    /// image is unpacked first - emulators can't boot a disc from inside an archive - all archives at once.
    func review(_ urls: [URL]) {
        Task {
            let archives = await Task.detached { urls.filter(Detect.needsUnpacking) }.value
            let plain = urls.filter { !archives.contains($0) }
            var items = await Task.detached { plain.map { PendingImport(url: $0, system: Detect.system(for: $0)) } }.value
            unpacking += archives.map(\.lastPathComponent)
            await withTaskGroup(of: Result<[PendingImport], Error>.self) { group in
                for archive in archives {
                    group.addTask { Result { try Self.unpack(archive) } }
                }
                for await result in group {
                    switch result {
                    case .success(let found): items += found
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
            }
            unpacking.removeAll { name in archives.contains { $0.lastPathComponent == name } }
            items = Self.withoutCompanions(items)
            pending.append(contentsOf: items.filter { item in !pending.contains { $0.url == item.url } })
        }
    }

    /// Unpacks an archive next to the games folder, so adding the game is a move rather than a second copy, and
    /// returns the games inside it.
    nonisolated static func unpack(_ archive: URL) throws -> [PendingImport] {
        try Paths.checkGamesFolder()
        let folder = try Paths.ensure(Paths.unpacking.appendingPathComponent(UUID().uuidString, isDirectory: true))
        do {
            // bsdtar reads zip and 7z, and refuses entries that would land outside the folder.
            _ = try Shell.runSync("/usr/bin/tar", ["-xf", archive.path, "-C", folder.path])
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw CartridgeError("Couldn't unpack \(archive.lastPathComponent): \(error.localizedDescription)")
        }
        let found = discover(in: folder, known: [])
        let games = found.games.map { PendingImport(url: $0.0, system: $0.1, unpackedFolder: folder) }
            + found.unrecognised.filter { Detect.discExtensions.contains($0.pathExtension.lowercased()) }
                .map { PendingImport(url: $0, system: nil, unpackedFolder: folder) }
        if games.isEmpty {
            try? FileManager.default.removeItem(at: folder)
            throw CartridgeError("There's no game Cartridge recognises inside \(archive.lastPathComponent).")
        }
        return games
    }

    /// Drops the track files another item on the list already brings with it, so picking a .cue and its .bin in the
    /// file picker adds one game rather than two - the folder scan has always done this.
    nonisolated static func withoutCompanions(_ items: [PendingImport]) -> [PendingImport] {
        var consumed = Set<String>()
        for item in items {
            let folder = item.url.deletingLastPathComponent()
            for name in ((try? companions(of: item.url)) ?? []).dropFirst() {
                consumed.insert(folder.appendingPathComponent(name).standardizedFileURL.path)
            }
        }
        return items.filter { !consumed.contains($0.url.standardizedFileURL.path) }
    }

    /// Takes items off the review list, deleting unpacked folders nothing left on the list still needs.
    func discardPending(_ items: [PendingImport]) {
        pending.removeAll { item in items.contains { $0.id == item.id } }
        for folder in Set(items.compactMap(\.unpackedFolder)) where !pending.contains(where: { $0.unpackedFolder == folder }) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func importPending(copy: Bool) async {
        let items = pending
        pending = []
        var failures: [String] = []
        for item in items {
            guard let system = item.system else { continue }
            do {
                // An unpacked game is always moved in: its temporary folder is deleted next.
                _ = try await add(item.url, system: system, copy: copy || item.unpackedFolder != nil)
            } catch {
                failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        discardPending(items)
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func add(_ source: URL, system: System, copy: Bool) async throws -> Game {
        if let existing = games.first(where: { $0.path == source.path }) { return existing }
        if copy, let existing = games.first(where: { $0.managed && $0.system == system && $0.url.lastPathComponent == source.lastPathComponent }) {
            return existing
        }
        let (title, icon) = await Task.detached { Detect.metadata(for: source, system: system) }.value
        var game = Game(title: title, system: system, path: source.path, managed: false)

        if copy {
            copying.append(source.lastPathComponent)
            defer { copying.removeAll { $0 == source.lastPathComponent } }
            game.path = try await Task.detached { try Self.copyIntoLibrary(source, system: system) }.value.path
            game.managed = true
        }
        if let icon {
            _ = try? Paths.ensure(Paths.art)
            try? icon.write(to: game.artURL)
            game.artChecked = true
        }
        games.append(game)
        save()
        if !game.artChecked { Task { await fetchArt(game.id) } }
        return game
    }

    /// Copies a game, and every track file a .cue/.gdi/.m3u refers to, into its own folder under Games/<system>.
    /// Returns the path of the copied game file (or folder, for PS3 and PS4).
    nonisolated static func copyIntoLibrary(_ source: URL, system: System) throws -> URL {
        let fm = FileManager.default
        try Paths.checkGamesFolder()
        let systemFolder = try Paths.ensure(Paths.games.appendingPathComponent(system.rawValue, isDirectory: true))
        let isFolder = Detect.isDirectory(source)
        let stem = isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let folder = uniqueURL(systemFolder.appendingPathComponent(stem, isDirectory: true))
        // Something Cartridge unpacked itself is moved, not copied: it's on the same drive, so that's instant.
        let place = source.path.hasPrefix(Paths.unpacking.path + "/") ? fm.moveItem(at:to:) : fm.copyItem(at:to:)

        if isFolder {
            try place(source, folder)
            return folder
        }
        let files = try companions(of: source)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            for relative in files {
                let destination = folder.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try place(source.deletingLastPathComponent().appendingPathComponent(relative), destination)
            }
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
        return folder.appendingPathComponent(source.lastPathComponent)
    }

    /// Whether a name a disc file refers to would lead out of the folder that file sits in.
    nonisolated static func escapesFolder(_ name: String) -> Bool {
        name.hasPrefix("/") || name.split(separator: "/").contains("..")
    }

    nonisolated static func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// The file itself plus the track files multi-file disc formats point at, relative to its folder.
    nonisolated static func companions(of file: URL) throws -> [String] {
        let dir = file.deletingLastPathComponent()
        var result = [file.lastPathComponent]
        var referenced: [String] = []
        let text = Detect.readText(file) ?? ""
        switch file.pathExtension.lowercased() {
        case "cue":
            referenced = text.matches(of: #/(?m)^\s*FILE\s+(?:"([^"]+)"|(\S+))/#).map { String($0.1 ?? $0.2 ?? "") }
        case "gdi":
            // "1 0 4 2352 track01.bin 0" or a quoted name containing spaces.
            referenced = text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
                if let quoted = line.firstMatch(of: #/"([^"]+)"/#) { return String(quoted.1) }
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                return fields.count >= 5 ? String(fields[4]) : nil
            }
        case "m3u":
            for line in text.split(whereSeparator: \.isNewline) {
                let entry = line.trimmingCharacters(in: .whitespaces)
                guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
                referenced.append(entry)
                // Check before following it. The loop below rejects an entry that leaves the folder, but only after
                // this line would already have opened a file outside it.
                if !escapesFolder(entry), entry.lowercased().hasSuffix(".cue") || entry.lowercased().hasSuffix(".gdi") {
                    let nested = try companions(of: dir.appendingPathComponent(entry)).dropFirst()
                    let prefix = (entry as NSString).deletingLastPathComponent
                    referenced += nested.map { prefix.isEmpty ? $0 : "\(prefix)/\($0)" }
                }
            }
        case "ccd":
            let stem = file.deletingPathExtension().lastPathComponent
            referenced = ["img", "sub"].map { "\(stem).\($0)" }.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        default:
            break
        }
        for name in referenced where !name.isEmpty {
            guard !escapesFolder(name) else {
                throw CartridgeError("\(file.lastPathComponent) points outside its folder (\(name)); add it without copying instead")
            }
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) else {
                throw CartridgeError("\(file.lastPathComponent) needs \(name), which isn't next to it")
            }
            if !result.contains(name) { result.append(name) }
        }
        return result
    }

    func remove(_ game: Game) {
        if sessions[game.id] != nil { stop(game) }
        if game.managed {
            // A managed game owns exactly one Games/<system>/<folder>. Work that out from the path, never from
            // the game's current system, which the player may have changed since it was copied.
            // Look in every games folder, not just the current one: the player may have moved it since this was copied.
            let storage = Paths.gamesRoots.lazy.compactMap { Self.managedFolder(of: game.url, games: $0) }.first
            if let storage, FileManager.default.fileExists(atPath: storage.path) {
                do {
                    try FileManager.default.trashItem(at: storage, resultingItemURL: nil)
                } catch {
                    self.error = "Couldn't move \(game.title) to the Trash: \(error.localizedDescription)"
                    return
                }
            }
        }
        let prefix = game.id.uuidString
        for file in (try? FileManager.default.contentsOfDirectory(at: Paths.art, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
        forgetImages(of: game)
        games.removeAll { $0.id == game.id }
        save()
    }

    /// Games/<system>/<folder> for a path inside Cartridge's Games directory, else nil.
    nonisolated static func managedFolder(of url: URL, games: URL = Paths.games) -> URL? {
        let root = games.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= root.count + 2, Array(parts.prefix(root.count)) == root,
              !parts[root.count..<(root.count + 2)].contains("..") else { return nil }
        return games.appendingPathComponent(parts[root.count], isDirectory: true).appendingPathComponent(parts[root.count + 1], isDirectory: true)
    }

    // MARK: Scanning the games folder

    static let scanKey = "games.scanFolder"
    /// On unless the player switched it off.
    static var scansGamesFolder: Bool { UserDefaults.standard.object(forKey: scanKey) as? Bool ?? true }

    private(set) var scanning = false
    /// What the last scan the player asked for turned up, for the menu command's alert.
    var scanReport: String?
    @ObservationIgnored private var lastScan = Date.distantPast

    func scanGamesFolderIfEnabled() async {
        guard Self.scansGamesFolder else { return }
        await scanGamesFolder()
    }

    /// Adds games that turned up in the games folder since Cartridge last looked. They are added where they are,
    /// not copied. Files it can't place on a console are returned for the player to add by hand, never guessed at.
    @discardableResult
    func scanGamesFolder() async -> (added: [Game], unrecognised: [URL]) {
        guard !scanning else { return ([], []) }
        scanning = true
        defer {
            scanning = false
            lastScan = Date()
        }
        let roots = Paths.gamesRoots.filter { Paths.disconnectedVolume(of: $0) == nil }
        let known = Set(games.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        let found = await Task.detached { roots.map { Self.discover(in: $0, known: known) } }.value
        var added: [Game] = []
        for result in found {
            for (url, system) in result.games {
                if let game = try? await add(url, system: system, copy: false) { added.append(game) }
            }
        }
        return (added, found.flatMap(\.unrecognised))
    }

    /// The menu command: scans, then says what happened.
    func scanGamesFolderAndReport() async {
        let (added, unrecognised) = await scanGamesFolder()
        var lines = [added.isEmpty ? "No new games in \(Paths.games.path)." :
                        "Added \(added.count) game\(added.count == 1 ? "" : "s"): \(added.prefix(5).map(\.title).joined(separator: ", "))\(added.count > 5 ? "…" : "")."]
        if !unrecognised.isEmpty {
            lines.append("\(unrecognised.count) file\(unrecognised.count == 1 ? " wasn't" : "s weren't") recognised as a game - add \(unrecognised.count == 1 ? "it" : "them") with Add Games… to pick the console: \(unrecognised.prefix(5).map(\.lastPathComponent).joined(separator: ", "))\(unrecognised.count > 5 ? "…" : "").")
        }
        scanReport = lines.joined(separator: "\n\n")
    }

    /// Files that are never games, so a folder full of scans and notes doesn't come back as "unrecognised".
    nonisolated static let notGames: Set<String> = [
        "txt", "nfo", "md", "pdf", "jpg", "jpeg", "png", "gif", "webp", "html", "htm", "url", "xml", "json", "dat",
        "sfv", "md5", "sha1", "log", "ini", "cfg", "db", "sav", "srm", "state", "mcd", "mcr", "ps2", "sub", "sbi",
    ]

    /// Every game inside `root` that isn't in `known`, and the files that looked like they might be but weren't
    /// recognised. A PS3 or PS4 game is one folder. Disc sheets (.m3u, .cue, .gdi, .ccd) are read first, so the
    /// track files they name are part of their game rather than games of their own.
    nonisolated static func discover(in root: URL, known: Set<String>) -> (games: [(URL, System)], unrecognised: [URL]) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return ([], []) }
        var files: [URL] = []
        var games: [(URL, System)] = []
        for case let url as URL in walker {
            guard Detect.isDirectory(url) else {
                files.append(url.standardizedFileURL)
                continue
            }
            if let system = Detect.folderSystem(url) {
                if !known.contains(url.standardizedFileURL.path) { games.append((url.standardizedFileURL, system)) }
                walker.skipDescendants()
            }
        }
        func rank(_ url: URL) -> Int {
            switch url.pathExtension.lowercased() {
            case "m3u": 0
            case "cue", "gdi", "ccd": 1
            default: 2
            }
        }
        var consumed = Set<String>()
        var unrecognised: [URL] = []
        for url in files.sorted(by: { (rank($0), $0.path) < (rank($1), $1.path) }) where !consumed.contains(url.path) {
            let ext = url.pathExtension.lowercased()
            if rank(url) < 2 {
                let folder = url.deletingLastPathComponent()
                for name in ((try? companions(of: url)) ?? []).dropFirst() {
                    consumed.insert(folder.appendingPathComponent(name).standardizedFileURL.path)
                }
            }
            guard !known.contains(url.path), !notGames.contains(ext) else { continue }
            if let system = Detect.system(for: url) {
                games.append((url, system))
            } else {
                unrecognised.append(url)
            }
        }
        return (games, unrecognised)
    }

    // MARK: Checking dumps

    private(set) var checkingDump: Set<UUID> = []
    private(set) var dumpProgress: (done: Int, total: Int)?
    var dumpReport: String?
    /// The game whose Find Artwork sheet is open. One sheet at the window, so it opens from anywhere.
    var searchingArtwork: Game?
    var artworkReport: (text: String, missing: Game?)?
    @ObservationIgnored private var catalogues: [System: DumpCheck.Catalogue] = [:]

    private func catalogue(for system: System) async throws -> DumpCheck.Catalogue {
        if let cached = catalogues[system] { return cached }
        let fresh = try await DumpCheck.catalogue(for: system)
        catalogues[system] = fresh
        return fresh
    }

    /// Compares a game's files with its console's list of known-good dumps and keeps the verdict.
    @discardableResult
    func checkDump(_ id: UUID) async throws -> DumpCheck.Verdict? {
        guard let game = games.first(where: { $0.id == id }), !checkingDump.contains(id) else { return nil }
        checkingDump.insert(id)
        defer { checkingDump.remove(id) }
        guard FileManager.default.fileExists(atPath: game.path) else {
            if let drive = Paths.disconnectedVolume(of: game.url) { throw CartridgeError("\(game.title) is on “\(drive)”, which isn't connected.") }
            throw CartridgeError("The game file is missing: \(game.path)")
        }
        let verdict: DumpCheck.Verdict
        if DumpCheck.list(for: game.system) == nil {
            verdict = .unsupported("There's no list of known-good \(game.system.name) dumps to compare with.")
        } else {
            let catalogue = try await catalogue(for: game.system)
            let url = game.url
            let system = game.system
            verdict = try await Task.detached { try DumpCheck.verify(url, system: system, against: catalogue) }.value
        }
        update(id) {
            $0.dump = verdict
            $0.dumpChecked = Date()
        }
        return verdict
    }

    /// Checks one game and reports a failure the usual way.
    func checkDumpShowingErrors(_ id: UUID) async {
        do { try await checkDump(id) } catch { self.error = error.localizedDescription }
    }

    /// For the right-click menu, where the details pane showing the verdict may not be open.
    func checkDumpReporting(_ id: UUID) async {
        do {
            guard let verdict = try await checkDump(id), let game = games.first(where: { $0.id == id }) else { return }
            dumpReport = "\(game.title)\n\n\(verdict.title). \(verdict.detail)"
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Checks every game, then says how many were verified, bad, unknown or couldn't be checked.
    func checkAllDumps() async {
        guard dumpProgress == nil else { return }
        let ids = games.filter { $0.homebrewSlug == nil }.map(\.id)
        dumpProgress = (0, ids.count)
        defer { dumpProgress = nil }
        var verified = 0, bad: [String] = [], unknown = 0, unsupported = 0, failed = 0
        for (done, id) in ids.enumerated() {
            if Task.isCancelled { break }
            switch try? await checkDump(id) {
            case .verified: verified += 1
            case .bad: bad.append(games.first { $0.id == id }?.title ?? "")
            case .unknown: unknown += 1
            case .unsupported: unsupported += 1
            case nil: failed += 1
            }
            dumpProgress = (done + 1, ids.count)
        }
        var lines = ["\(verified) verified, \(bad.count) bad or modified, \(unknown) not in the lists, \(unsupported) couldn't be compared."]
        if !bad.isEmpty { lines.append("Worth dumping again: \(bad.prefix(8).joined(separator: ", "))\(bad.count > 8 ? "…" : "").") }
        if failed > 0 { lines.append("\(failed) couldn't be read - their files may be missing or on a drive that isn't connected.") }
        dumpReport = lines.joined(separator: "\n\n")
    }

    // MARK: Homebrew

    func installHomebrew(_ entry: HomebrewEntry) async {
        guard downloads[entry.slug] == nil, !games.contains(where: { $0.homebrewSlug == entry.slug }) else { return }
        guard let system = entry.system, let file = entry.romFile, let url = entry.fileURL(file.filename) else {
            error = "\(entry.title) has no ROM Cartridge can play"
            return
        }
        downloads[entry.slug] = 0
        defer { downloads[entry.slug] = nil }
        let folder = Self.uniqueURL(Paths.games.appendingPathComponent(system.rawValue, isDirectory: true).appendingPathComponent(entry.slug, isDirectory: true))
        do {
            try Paths.checkGamesFolder()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var name = (file.filename as NSString).lastPathComponent
            // gambatte only accepts .gb/.gbc; .cgb is the same format.
            if name.lowercased().hasSuffix(".cgb") { name = String(name.dropLast(4)) + ".gbc" }
            let destination = folder.appendingPathComponent(name)
            let slug = entry.slug
            try await Net.download(url, to: destination) { [weak self] value in
                Task { @MainActor in
                    if self?.downloads[slug] != nil { self?.downloads[slug] = value }
                }
            }
            var game = Game(title: entry.title, system: system, path: destination.path, managed: true)
            game.developer = entry.developer
            game.homebrewSlug = entry.slug
            game.artChecked = true
            if let shot = entry.screenshotURLs.first {
                _ = try? Paths.ensure(Paths.art)
                try? await Net.download(shot, to: game.artURL) { _ in }
            }
            games.append(game)
            save()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if !Self.isCancellation(error) { self.error = "Couldn't download \(entry.title): \(error.localizedDescription)" }
        }
    }

    // MARK: Artwork

    func image(for game: Game, _ kind: ArtKind = .front) -> NSImage? {
        _ = artRevision
        return cachedImage(game.artFile(kind))
    }

    /// Read without observing, so the shelf doesn't rebuild when a disc label arrives.
    func labelImage(for game: Game) -> NSImage? {
        cachedImage(game.labelArtURL)
    }

    func screenshots(for game: Game) -> [URL] {
        _ = artRevision
        return (0..<6).map(game.screenshotFile).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func cachedImage(_ url: URL) -> NSImage? {
        if let image = images.object(forKey: url.path as NSString) { return image }
        // Decode from data so the file's contents, not its .png name, decide the format.
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: url.path as NSString)
        return image
    }

    private func forgetImages(of game: Game) {
        for url in ArtKind.allCases.map(game.artFile) + [game.labelArtURL] {
            images.removeObject(forKey: url.path as NSString)
        }
    }

    private func artChanged(_ id: UUID) {
        if let game = games.first(where: { $0.id == id }) { forgetImages(of: game) }
        artRevision += 1
    }

    /// Puts a picture the player chose, such as a scan from The Cover Project, into one art slot.
    func setArt(_ data: Data, kind: ArtKind, for game: Game) throws {
        guard NSImage(data: data) != nil else { throw CartridgeError("That file isn't an image Cartridge can read") }
        _ = try Paths.ensure(Paths.art)
        try data.write(to: game.artFile(kind), options: .atomic)
        artChanged(game.id)
    }

    func removeArt(_ kind: ArtKind, for game: Game) {
        try? FileManager.default.removeItem(at: game.artFile(kind))
        artChanged(game.id)
    }

    /// Box art from the libretro thumbnail server, which is named after No-Intro/Redump file names.
    nonisolated static func thumbnailURL(_ system: System, kind: String = "Named_Boxarts", name: String) -> URL? {
        guard let set = system.thumbnailSet else { return nil }
        let safe = String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
        return URL(string: "https://thumbnails.libretro.com")?.appending(path: set).appending(path: kind).appending(path: "\(safe).png")
    }

    /// Fills in missing artwork and details from whatever is set up: LaunchBox, then IGDB, then libretro's thumbnails.
    func fetchArt(_ id: UUID) async {
        guard let game = games.first(where: { $0.id == id }), !game.artChecked else { return }
        let stem = Detect.withoutDuplicateSuffix(game.system.isFolderBased ? game.url.lastPathComponent : game.url.deletingPathExtension().lastPathComponent)
        if let db = artwork.launchBoxDB, let match = db.match(game.title, system: game.system) ?? db.match(stem, system: game.system) {
            try? await applyLaunchBox(match, to: id, overwrite: false)
        } else if let igdb = artwork.igdb, let results = try? await igdb.search(game.title, system: game.system),
                  let match = results.first(where: { TitleKey.make($0.name) == TitleKey.make(game.title) }) {
            try? await applyIGDB(match, to: id, overwrite: false)
        }
        if !FileManager.default.fileExists(atPath: game.artURL.path), let url = Self.thumbnailURL(game.system, name: stem),
           let data = try? await Net.data(url), NSImage(data: data) != nil {
            _ = try? Paths.ensure(Paths.art)
            try? data.write(to: game.artURL)
            artChanged(id)
        }
        // That last one only hits when the file is named exactly the way the thumbnail is. A game renamed by hand,
        // or named after its disc id, needs the listing searched - the same source Find Artwork offers, run for you.
        // A console libretro keeps no artwork for is an answer, not a failure - don't keep asking about those.
        var reachedTheSources = true
        if !FileManager.default.fileExists(atPath: game.artURL.path), game.system.thumbnailSet != nil {
            do {
                if let closest = Self.closestThumbnail(try await searchLibretro(game.title, system: game.system)) {
                    try? await applyLibretro(closest, to: id)
                }
            } catch {
                reachedTheSources = false
            }
        }
        // Games added with no connection are left to try again next time, rather than marked as having no cover.
        if reachedTheSources { update(id) { $0.artChecked = true } }
    }

    /// Runs the automatic lookup again for every game, filling only what's missing.
    func fetchMissingArtwork() async {
        guard artworkProgress == nil else { return }
        let ids = games.filter { $0.homebrewSlug == nil }.map(\.id)
        artworkProgress = (0, ids.count)
        defer { artworkProgress = nil }
        for (done, id) in ids.enumerated() {
            if Task.isCancelled { break }
            update(id) { $0.artChecked = false }
            await fetchArt(id)
            artworkProgress = (done + 1, ids.count)
        }
        let missing = games.filter { $0.homebrewSlug == nil && !FileManager.default.fileExists(atPath: $0.artURL.path) }
        artworkReport = missing.isEmpty
            ? ("Every game has a cover.", nil)
            : ("No cover found for \(missing.prefix(6).map(\.title).joined(separator: ", "))\(missing.count > 6 ? "…" : ""). Search the sources by hand to pick one.", missing.first)
    }

    func applyLaunchBox(_ match: LBGame, to id: UUID, overwrite: Bool) async throws {
        guard let db = artwork.launchBoxDB else { throw CartridgeError("The LaunchBox database isn't installed") }
        let picked = LaunchBox.pick(db.images(match.id))
        try await downloadArt(picked.art.mapValues(\.url), screenshots: picked.screenshots.map(\.url), to: id, overwrite: overwrite)
        update(id) { game in
            game.launchBoxID = match.id
            Self.fill(&game.overview, match.overview, overwrite)
            Self.fill(&game.developer, match.developer, overwrite)
            Self.fill(&game.publisher, match.publisher, overwrite)
            Self.fill(&game.releaseYear, match.year, overwrite)
            Self.fill(&game.genres, match.genres?.replacingOccurrences(of: ";", with: ", "), overwrite)
            Self.fill(&game.videoURL, match.video, overwrite)
        }
    }

    func applyIGDB(_ match: IGDBGame, to id: UUID, overwrite: Bool) async throws {
        var art: [ArtKind: URL] = [:]
        if let cover = match.cover { art[.front] = IGDB.imageURL(cover.image_id, size: "1080p") }
        if let artwork = match.artworks?.first { art[.fanart] = IGDB.imageURL(artwork.image_id, size: "1080p") }
        let shots = (match.screenshots ?? []).prefix(6).map { IGDB.imageURL($0.image_id, size: "1080p") }
        try await downloadArt(art, screenshots: Array(shots), to: id, overwrite: overwrite)
        update(id) { game in
            game.igdbID = match.id
            Self.fill(&game.overview, match.summary, overwrite)
            Self.fill(&game.developer, match.companies(developer: true), overwrite)
            Self.fill(&game.publisher, match.companies(developer: false), overwrite)
            Self.fill(&game.releaseYear, match.year, overwrite)
            Self.fill(&game.genres, match.genres.map { $0.map(\.name).joined(separator: ", ") }, overwrite)
            Self.fill(&game.videoURL, match.videos?.first.map { "https://www.youtube.com/watch?v=\($0.video_id)" }, overwrite)
        }
    }

    /// Box art names on thumbnails.libretro.com matching every word of `query`.
    func searchLibretro(_ query: String, system: System) async throws -> [String] {
        let names = try await boxArtNames(system)
        let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }
        return names.filter { name in
            let lower = name.lowercased()
            return words.allSatisfy { lower.contains($0) }
        }
    }

    /// A console's whole box art listing, one page, fetched once per run. What's kept is the download rather than
    /// its result, so a library added all at once waits on a single request instead of starting one per game.
    private func boxArtNames(_ system: System) async throws -> [String] {
        if let running = libretroNames[system] { return try await running.value }
        guard let set = system.thumbnailSet, let url = URL(string: "https://thumbnails.libretro.com")?
            .appending(path: set).appending(path: "Named_Boxarts", directoryHint: .isDirectory)
        else { throw CartridgeError("libretro has no artwork for \(system.name)") }
        let task = Task {
            let page = String(decoding: try await Net.data(url), as: UTF8.self)
            return page.matches(of: #/href="([^"?/]+)\.png"/#).compactMap { String($0.1).removingPercentEncoding }
        }
        libretroNames[system] = task
        do {
            return try await task.value
        } catch {
            // A connection that dropped once shouldn't leave the console without artwork for the rest of the run.
            libretroNames[system] = nil
            throw error
        }
    }
    @ObservationIgnored private var libretroNames: [System: Task<[String], Error>] = [:]

    /// The likeliest of libretro's names for a game: an American release before other regions, and the plainest
    /// name before revisions, discs and demos. Every word of the title had to appear for a name to get here, so a
    /// file named after its disc id matches nothing and keeps no cover rather than the wrong one.
    nonisolated static func closestThumbnail(_ names: [String]) -> String? {
        func rank(_ name: String) -> (Int, Int) {
            let region = ["(USA", "(World", "(Europe", "(Japan"].firstIndex { name.contains($0) } ?? 4
            return (region, name.count)
        }
        return names
            .filter { !$0.contains("(Demo") && !$0.contains("(Beta") && !$0.contains("(Proto") }
            .min { rank($0) < rank($1) }
    }

    func applyLibretro(_ name: String, to id: UUID) async throws {
        guard let system = games.first(where: { $0.id == id })?.system else { return }
        let art = [ArtKind.front: "Named_Boxarts", .title: "Named_Titles"].compactMapValues { Self.thumbnailURL(system, kind: $0, name: name) }
        try await downloadArt(art, screenshots: [], to: id, overwrite: true)
    }

    nonisolated static func fill<T>(_ field: inout T?, _ value: T?, _ overwrite: Bool) {
        if let value, overwrite || field == nil { field = value }
    }

    /// Downloads into the game's art slots. Without `overwrite`, only empty slots are filled.
    private func downloadArt(_ art: [ArtKind: URL], screenshots: [URL], to id: UUID, overwrite: Bool) async throws {
        guard let game = games.first(where: { $0.id == id }) else { return }
        _ = try Paths.ensure(Paths.art)
        let fm = FileManager.default
        var jobs: [(source: URL, target: URL)] = art.compactMap { kind, source in
            let target = game.artFile(kind)
            return overwrite || !fm.fileExists(atPath: target.path) ? (source, target) : nil
        }
        if !screenshots.isEmpty, overwrite || self.screenshots(for: game).isEmpty {
            (0..<6).forEach { try? fm.removeItem(at: game.screenshotFile($0)) }
            jobs += screenshots.prefix(6).enumerated().map { ($1, game.screenshotFile($0)) }
        }
        guard !jobs.isEmpty else { return }
        let saved = await withTaskGroup(of: Bool.self) { group in
            for job in jobs {
                group.addTask {
                    guard let data = try? await Net.data(job.source), NSImage(data: data) != nil else { return false }
                    return (try? data.write(to: job.target, options: .atomic)) != nil
                }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        artChanged(id)
        if saved == 0 { throw CartridgeError("None of the artwork could be downloaded") }
    }

    /// The title screen, used as the printed label on a disc when there's no disc scan.
    func fetchLabelArt(_ game: Game) async {
        guard !FileManager.default.fileExists(atPath: game.labelArtURL.path) else { return }
        let stem = Detect.withoutDuplicateSuffix(game.url.deletingPathExtension().lastPathComponent)
        guard let url = Self.thumbnailURL(game.system, kind: "Named_Titles", name: stem),
              let data = try? await Net.data(url), NSImage(data: data) != nil else { return }
        _ = try? Paths.ensure(Paths.art)
        try? data.write(to: game.labelArtURL)
        images.removeObject(forKey: game.labelArtURL.path as NSString)
    }

    /// The YouTube id of a game's trailer: from its saved link, else its LaunchBox entry, else an IGDB lookup.
    func trailerID(for id: UUID) async -> String? {
        guard !noTrailer.contains(id), let game = games.first(where: { $0.id == id }) else { return nil }
        if let saved = game.videoURL.flatMap(YouTube.videoID) { return saved }
        var link: String?
        if let launchBoxID = game.launchBoxID {
            link = artwork.launchBoxDB?.game(launchBoxID)?.video
        }
        if link.flatMap(YouTube.videoID) == nil, let igdb = artwork.igdb,
           let results = try? await igdb.search(game.title, system: game.system),
           let match = results.first(where: { $0.id == game.igdbID }) ?? results.first(where: { TitleKey.make($0.name) == TitleKey.make(game.title) }),
           let video = match.videos?.first {
            link = "https://www.youtube.com/watch?v=\(video.video_id)"
        }
        guard let link, let videoID = YouTube.videoID(from: link) else {
            noTrailer.insert(id)
            return nil
        }
        update(id) { $0.videoURL = link }
        return videoID
    }

    /// Remembers, until the app quits, that a game's trailer can't be played here (removed, or embedding disabled).
    func trailerFailed(_ id: UUID) {
        noTrailer.insert(id)
    }

    // MARK: Manuals

    /// The game's instruction booklet as a PDF, found and downloaded from the Internet Archive the first time.
    func manual(for id: UUID) async -> URL? {
        guard let game = games.first(where: { $0.id == id }) else { return nil }
        if FileManager.default.fileExists(atPath: game.manualURL.path) { return game.manualURL }
        if let running = manualTasks[id] { return await running.value }
        let task = Task { await fetchManual(id) }
        manualTasks[id] = task
        defer { manualTasks[id] = nil }
        return await task.value
    }

    /// Every match the last lookup found, best first, for choosing another when the best isn't right.
    private(set) var manualCandidates: [UUID: [Manuals.Candidate]] = [:]

    private func fetchManual(_ id: UUID) async -> URL? {
        guard let game = games.first(where: { $0.id == id }) else { return nil }
        manualStatus[id] = .searching
        let candidates = await Manuals.find(title: game.title, system: game.system)
        manualCandidates[id] = candidates
        guard let best = candidates.first, best.score >= Manuals.confidentScore else {
            manualStatus[id] = .failed(candidates.isEmpty
                ? "Couldn't find a \(game.system.name) manual for \(game.title) on the Internet Archive, Musée des jeux vidéo or Digital Press. Search the Internet Archive yourself, or choose a PDF you already have."
                : "Found \(candidates.count == 1 ? "1 possible manual" : "\(candidates.count) possible manuals") for \(game.title), but none is a sure match. Pick one from Possible Matches, or search the Internet Archive yourself.")
            return nil
        }
        return await useManual(best, for: id)
    }

    /// Downloads a particular match as the game's booklet.
    @discardableResult
    func useManual(_ candidate: Manuals.Candidate, for id: UUID) async -> URL? {
        guard let game = games.first(where: { $0.id == id }) else { return nil }
        manualStatus[id] = .downloading(0)
        do {
            let url = try await Manuals.resolve(candidate)
            _ = try Paths.ensure(Paths.art)
            let staged = Paths.art.appendingPathComponent("\(id.uuidString)-manual.download")
            try await Net.download(url, to: staged) { [weak self] value in
                Task { @MainActor in
                    if case .downloading = self?.manualStatus[id] { self?.manualStatus[id] = .downloading(value) }
                }
            }
            guard BookletPages.pageSizes(of: staged) != nil else {
                try? FileManager.default.removeItem(at: staged)
                throw CartridgeError("“\(candidate.title)” from \(candidate.source.rawValue) isn't a PDF Cartridge can read.")
            }
            _ = try FileManager.default.replaceItemAt(game.manualURL, withItemAt: staged)
            update(id) { $0.manualSource = candidate.page }
            manualStatus[id] = nil
            return game.manualURL
        } catch {
            manualStatus[id] = .failed(Self.isCancellation(error) ? "The download was cancelled." : error.localizedDescription)
            return nil
        }
    }

    /// Uses a PDF the player chose as the game's booklet.
    func setManual(_ source: URL, for game: Game) throws {
        guard BookletPages.pageSizes(of: source) != nil else { throw CartridgeError("That file isn't a PDF Cartridge can read.") }
        _ = try Paths.ensure(Paths.art)
        let staged = Paths.art.appendingPathComponent("\(game.id.uuidString)-manual.incoming")
        try? FileManager.default.removeItem(at: staged)
        try FileManager.default.copyItem(at: source, to: staged)
        _ = try FileManager.default.replaceItemAt(game.manualURL, withItemAt: staged)
        update(game.id) { $0.manualSource = source.lastPathComponent }
        manualStatus[game.id] = nil
    }

    func removeManual(for game: Game) {
        try? FileManager.default.removeItem(at: game.manualURL)
        update(game.id) { $0.manualSource = nil }
        manualStatus[game.id] = nil
    }

    private func fetchMissingArt() async {
        for id in games.filter({ !$0.artChecked }).map(\.id) {
            await fetchArt(id)
        }
    }

    // MARK: Playing

    // MARK: Advanced Mode

    var emulatorSettings = Advanced.loadEmulators() {
        didSet { Advanced.save(emulatorSettings) }
    }
    /// What each running emulator's settings files held before Cartridge changed them for its game.
    @ObservationIgnored private var tweakRestores: [pid_t: [ConfigKey: String?]] = [:]

    func setTweaks(_ tweaks: DisplayTweaks, forGame id: UUID) {
        update(id) { $0.tweaks = tweaks.isEmpty ? nil : tweaks }
    }

    func needsDownload(_ game: Game) -> [String] {
        var items: [String] = []
        let emulator = game.system.emulator
        if installer.executable(emulator) == nil { items.append("\(emulator.name) from \(emulator.source)") }
        if let core = game.system.core, !installer.hasCore(core) { items.append("the \(core) core from buildbot.libretro.com") }
        return items
    }

    /// A game waiting on the player's answer about a BIOS its emulator can't see.
    var missingBios: BiosPrompt?

    struct BiosPrompt: Identifiable {
        let game: Game
        let requirement: BiosRequirement
        var id: UUID { game.id }
    }

    /// Plays straight away when everything is installed, otherwise asks before downloading - and first, when the
    /// emulator plainly has no BIOS to boot with, says so instead of letting it fail with its own error.
    func requestPlay(_ game: Game, skippingBiosCheck: Bool = false) {
        if !skippingBiosCheck, let requirement = BiosRequirement.missing(for: game.system) {
            missingBios = BiosPrompt(game: game, requirement: requirement)
            return
        }
        if needsDownload(game).isEmpty {
            Task { await play(game) }
        } else {
            confirmingPlay = game
        }
    }

    func play(_ game: Game) async {
        guard sessions[game.id] == nil, status[game.id] == nil else { return }
        defer { status[game.id] = nil }
        do {
            guard FileManager.default.fileExists(atPath: game.path) else {
                if let drive = Paths.disconnectedVolume(of: game.url) {
                    throw CartridgeError("\(game.title) is on “\(drive)”, which isn't connected. Plug it in and try again.")
                }
                throw CartridgeError("The game file is missing: \(game.path)")
            }
            let emulator = game.system.emulator
            if installer.executable(emulator) == nil {
                status[game.id] = "Installing \(emulator.name)…"
                try await installer.install(emulator)
            }
            var core: URL?
            if let name = game.system.core {
                if !installer.hasCore(name) {
                    status[game.id] = "Installing \(name) core…"
                    try await installer.installCore(name)
                }
                core = Installer.coreURL(name)
            }
            let target = game.system.isFolderBased ? Detect.bootFile(in: game.url, for: game.system) : game.url
            guard let target else { throw CartridgeError("Couldn't find the boot file inside \(game.url.lastPathComponent)") }

            // Getting past an emulator's first-run wizard is worth trying, not worth refusing to play over: if it
            // fails, the emulator still opens and says what it wants itself.
            if emulator == .pcsx2, let app = installer.executable(.pcsx2) { try? await EmulatorData.preparePCSX2(app) }
            if emulator == .duckstation, let app = installer.executable(.duckstation) { try? await EmulatorData.prepareDuckStation(app) }
            var originals: [ConfigKey: String?] = [:]
            if UserDefaults.standard.bool(forKey: Advanced.enabledKey) {
                let tweaks = (emulatorSettings[emulator] ?? DisplayTweaks()).overlaid(by: games.first { $0.id == game.id }?.tweaks)
                originals = try Advanced.apply(Advanced.writes(tweaks, for: emulator))
            }
            status[game.id] = "Starting \(emulator.name)…"
            let pid: pid_t
            do {
                pid = try await installer.launch(emulator, arguments: emulator.arguments(game: target, core: core)) { [weak self] pid in
                    self?.ended(pid)
                }
            } catch {
                Advanced.restore(originals)
                throw error
            }
            if !originals.isEmpty {
                // ponytail: two games in one emulator at once would restore in the wrong order; one at a time is the norm.
                tweakRestores[pid] = originals
                Advanced.savePending(Array(tweakRestores.values))
            }
            pids[pid] = game.id
            sessions[game.id] = Date()
            update(game.id) { $0.lastPlayed = Date() }
        } catch {
            if !Self.isCancellation(error) { self.error = "Couldn't start \(game.title): \(error.localizedDescription)" }
        }
    }

    func stop(_ game: Game) {
        for (pid, id) in pids where id == game.id {
            if let app = NSRunningApplication(processIdentifier: pid), app.terminate() { continue }
            kill(pid, SIGTERM)
        }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func ended(_ pid: pid_t) {
        if let originals = tweakRestores.removeValue(forKey: pid) {
            Advanced.restore(originals)
            Advanced.savePending(Array(tweakRestores.values))
        }
        guard let id = pids.removeValue(forKey: pid), let start = sessions.removeValue(forKey: id) else { return }
        update(id) { $0.playSeconds += Date().timeIntervalSince(start) }
        // The emulator has just written its saves and quit, so this is the moment to copy them.
        if let emulator = games.first(where: { $0.id == id })?.system.emulator {
            if saves.automatic { Task { await saves.backUp(emulator) } }
            // An emulator opened for the first time has only now written its settings, so this is when it can be
            // given the RetroAchievements sign-in.
            if achievements.username != nil, Achievements.supported.contains(emulator) { achievements.apply(to: emulator) }
        }
    }

    private func flushSessions() {
        for (pid, _) in pids { ended(pid) }
    }
}
