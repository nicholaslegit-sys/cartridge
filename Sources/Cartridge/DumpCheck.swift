import CryptoKit
import Foundation

/// Checks game files against the lists of known-good dumps - No-Intro for cartridges, Redump for discs - as libretro
/// publishes them per console. The lists hold names, sizes and hashes only, never game data.
///
/// A bad dump is the most common reason a game won't boot or crashes partway in, and it's invisible until then.
/// A match also gives the game's exact catalogue name, which is better for artwork than a guessed title.
enum DumpCheck {
    enum Verdict: Codable, Hashable {
        /// Every file matches the list.
        case verified(String)
        /// The files are named like a listed game but their contents differ: a bad, incomplete or modified dump.
        case bad(String)
        /// Not in the list at all: a hack, translation, homebrew, prototype, or a dump nobody has catalogued.
        case unknown
        /// Can't be compared, and why.
        case unsupported(String)
    }

    struct Entry: Hashable {
        let game: String
        let file: String
        let size: Int
        let sha1: String
    }

    struct Catalogue {
        let bySHA1: [String: Entry]
        let byFile: [String: Entry]

        init(_ entries: [Entry]) {
            bySHA1 = Dictionary(entries.map { ($0.sha1, $0) }, uniquingKeysWith: { first, _ in first })
            byFile = Dictionary(entries.map { ($0.file.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    // MARK: The lists

    /// libretro-database's folder and file for a console, named the same as its thumbnail set.
    static func list(for system: System) -> (folder: String, name: String)? {
        // 3DS dumps come encrypted or decrypted and PS4 dumps are folders, so neither matches a list.
        guard let name = system.thumbnailSet, system != .n3ds, system != .ps4 else { return nil }
        return (system.isDisc ? "redump" : "no-intro", name)
    }

    static func remoteURL(for system: System) -> URL? {
        guard let list = list(for: system) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat")?
            .appending(path: list.folder).appending(path: "\(list.name).dat")
    }

    static func localURL(for system: System) -> URL? {
        guard let list = list(for: system) else { return nil }
        return Paths.root.appendingPathComponent("Dump lists", isDirectory: true).appendingPathComponent("\(list.name).dat")
    }

    /// The list for a console: downloaded the first time and refreshed once a month.
    static func catalogue(for system: System) async throws -> Catalogue {
        guard let remote = remoteURL(for: system), let local = localURL(for: system) else {
            throw CartridgeError("There's no list of known-good \(system.name) dumps.")
        }
        let age = (try? local.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) }
        if age == nil || age! > 30 * 86_400 {
            do {
                _ = try Paths.ensure(local.deletingLastPathComponent())
                try await Net.download(remote, to: local) { _ in }
            } catch {
                // An old list is far better than none; only fail when there isn't one at all.
                if !FileManager.default.fileExists(atPath: local.path) { throw error }
            }
        }
        let text = try String(contentsOf: local, encoding: .utf8)
        return await Task.detached { Catalogue(parse(text)) }.value
    }

    /// Reads a clrmamepro DAT: a `name "…"` line per game, and a `rom ( name "…" size … sha1 … )` line per file.
    static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var game = ""
        func quoted(after marker: String, in line: Substring) -> String? {
            guard let start = line.range(of: marker) else { return nil }
            var value = ""
            var escaped = false
            for char in line[start.upperBound...] {
                if escaped { value.append(char); escaped = false; continue }
                if char == "\\" { escaped = true; continue }
                if char == "\"" { return value }
                value.append(char)
            }
            return nil
        }
        func word(after marker: String, in line: Substring) -> Substring? {
            guard let start = line.range(of: marker) else { return nil }
            return line[start.upperBound...].prefix { !$0.isWhitespace }
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop { $0.isWhitespace }
            if trimmed.hasPrefix("rom (") {
                guard let file = quoted(after: "name \"", in: trimmed),
                      let size = word(after: " size ", in: trimmed).flatMap({ Int($0) }),
                      let sha1 = word(after: " sha1 ", in: trimmed), sha1.count == 40 else { continue }
                entries.append(Entry(game: game, file: file, size: size, sha1: sha1.lowercased()))
            } else if trimmed.hasPrefix("name \""), let name = quoted(after: "name \"", in: trimmed) {
                game = name
            }
        }
        return entries
    }

    // MARK: Checking

    /// Formats that can't be compared, because the lists only hold the plain, uncompressed files.
    static let compressed: Set<String> = ["chd", "rvz", "gcz", "wia", "wbfs", "cso", "ciso", "pbp", "ecm", "zip", "7z"]
    static let sheets: Set<String> = ["cue", "gdi", "m3u", "ccd"]

    /// Compares a game's files with the list. Reads every byte, so it takes a few seconds for a DVD image.
    static func verify(_ game: URL, system: System, against catalogue: Catalogue) throws -> Verdict {
        let ext = game.pathExtension.lowercased()
        if Detect.isDirectory(game) {
            return .unsupported("Games dumped as folders can't be compared with Redump's disc images.")
        }
        if compressed.contains(ext) {
            return .unsupported(".\(ext) files are compressed, and the lists only know the uncompressed files.")
        }
        if ext == "xiso" {
            return .unsupported(".xiso files are trimmed copies of the disc, so they never match Redump's images.")
        }
        let files: [URL]
        if sheets.contains(ext) {
            let folder = game.deletingLastPathComponent()
            files = try Library.companions(of: game).dropFirst()
                .map { folder.appendingPathComponent($0) }
                .filter { !sheets.contains($0.pathExtension.lowercased()) }
        } else {
            files = [game]
        }
        guard !files.isEmpty else { return .unknown }

        var matched: [Entry] = []
        for file in files {
            if let entry = try match(file, in: catalogue) {
                matched.append(entry)
            } else if let named = catalogue.byFile[file.lastPathComponent.lowercased()] {
                return .bad(named.game)
            }
        }
        if matched.count == files.count, let first = matched.first, matched.allSatisfy({ $0.game == first.game }) {
            return .verified(first.game)
        }
        return matched.first.map { .bad($0.game) } ?? .unknown
    }

    /// The listed file this one is, trying it without a copier header too - old cartridge dumps often carry a
    /// 16-byte iNES header (NES) or a 512-byte copier header (SNES) that the lists leave out.
    static func match(_ file: URL, in catalogue: Catalogue) throws -> Entry? {
        let handle = try FileHandle(forReadingFrom: file)
        let header = try handle.read(upToCount: 4) ?? Data()
        try? handle.close()
        let size = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var skips = [0]
        if header.starts(with: [0x4E, 0x45, 0x53, 0x1A]) { skips.append(16) }
        if size % 1024 == 512 { skips.append(512) }
        for skip in skips {
            if let entry = catalogue.bySHA1[try sha1(of: file, skipping: skip)] { return entry }
        }
        return nil
    }

    static func sha1(of file: URL, skipping skip: Int = 0) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        if skip > 0 { try handle.seek(toOffset: UInt64(skip)) }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension DumpCheck.Verdict {
    var title: String {
        switch self {
        case .verified: "Verified dump"
        case .bad: "Bad or modified dump"
        case .unknown: "Not in the list"
        case .unsupported: "Can't be checked"
        }
    }

    var detail: String {
        switch self {
        case .verified(let name): "Matches “\(name)” exactly."
        case .bad(let name): "Named like “\(name)”, but the contents differ. A bad dump is the usual reason a game won't boot or crashes partway in - dump it again if you can."
        case .unknown: "Not a dump the list knows: often a hack, translation, homebrew or prototype, which is fine."
        case .unsupported(let why): why
        }
    }

    var symbol: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .bad: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        case .unsupported: "minus.circle"
        }
    }
}
