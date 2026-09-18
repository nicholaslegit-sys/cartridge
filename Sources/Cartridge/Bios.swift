import CryptoKit
import Foundation

/// BIOS and firmware handling.
///
/// Cartridge never downloads a console BIOS. Those are copyrighted code that only comes off a console you own - the
/// one exception is PS3 system software, which Sony publishes for anyone, and which RPCS3 installs itself.
/// What Cartridge does do is check that what you supplied really is the thing it claims to be, say which revision it
/// is, and remember its fingerprint so a later corruption is visible.

// MARK: - What each console needs

struct BiosRequirement: Identifiable, Hashable {
    let id: String
    let system: System
    /// What to call it on screen.
    let name: String
    /// The name the file is saved as, so emulators that look for an exact name find it. nil keeps the original name.
    let filename: String?
    /// false for consoles that run without it but are more accurate with it.
    let required: Bool
    let summary: String
    /// Where a copy legitimately comes from.
    let source: String
    let check: BiosCheck
    /// Emulator folders the verified file is copied into. Empty means the emulator is pointed at Cartridge's copy.
    let targets: [BiosTarget]

    static func == (a: BiosRequirement, b: BiosRequirement) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let all: [BiosRequirement] = [
        BiosRequirement(
            id: "ps1", system: .ps1, name: "PlayStation BIOS", filename: nil, required: true,
            summary: "DuckStation won't boot a disc without a PlayStation BIOS image (512 KB).",
            source: "Dump it from a PlayStation you own with a tool like unirom, or copy it out of a console you have already dumped.",
            check: .ps1, targets: [.duckStation, .retroArch]
        ),
        BiosRequirement(
            id: "ps2", system: .ps2, name: "PlayStation 2 BIOS", filename: nil, required: true,
            summary: "PCSX2 needs a PS2 BIOS image (4 MB). Its own setup wizard asks for the same file.",
            source: "Dump it from a PS2 you own with biosdrain or a similar homebrew dumper.",
            check: .ps2, targets: [.pcsx2]
        ),
        BiosRequirement(
            id: "saturn.jp", system: .saturn, name: "Saturn BIOS (Japan)", filename: "sega_101.bin", required: false,
            summary: "Japanese Saturn BIOS, for Japanese games. Beetle Saturn needs at least one region's BIOS.",
            source: "Dump it from a Saturn you own.",
            check: .saturn, targets: [.retroArch]
        ),
        BiosRequirement(
            id: "saturn.us", system: .saturn, name: "Saturn BIOS (US / Europe)", filename: "mpr-17933.bin", required: true,
            summary: "US and European Saturn BIOS. Beetle Saturn refuses to start without it.",
            source: "Dump it from a Saturn you own.",
            check: .saturn, targets: [.retroArch]
        ),
        BiosRequirement(
            id: "ps3", system: .ps3, name: "PS3 System Software", filename: "PS3UPDAT.PUP", required: true,
            summary: "RPCS3 needs Sony's PS3 firmware, a free official download. Get PS3UPDAT.PUP from playstation.com and add it here - Cartridge checks it and hands it to RPCS3.",
            source: "playstation.com publishes it for every PS3 owner.",
            check: .pup, targets: []
        ),
        BiosRequirement(
            id: "xbox.mcpx", system: .xbox, name: "MCPX boot ROM", filename: "mcpx_1.0.bin", required: true,
            summary: "xemu needs the 512-byte MCPX boot ROM, then you point xemu's settings at it.",
            source: "Dump it from an Xbox you own.",
            check: .fixedSize([512], describing: "MCPX boot ROM"), targets: []
        ),
        BiosRequirement(
            id: "xbox.flash", system: .xbox, name: "Xbox flash BIOS", filename: nil, required: true,
            summary: "The 256 KB, 512 KB or 1 MB flash image xemu boots from.",
            source: "Dump it from an Xbox you own.",
            check: .fixedSize([256 << 10, 512 << 10, 1 << 20], describing: "Xbox flash image"), targets: []
        ),
        BiosRequirement(
            id: "nds.bios7", system: .nds, name: "DS ARM7 BIOS", filename: "bios7.bin", required: false,
            summary: "melonDS runs on its own high-level BIOS, but real DS BIOS files are more accurate.",
            source: "Dump it from a DS you own.",
            check: .fixedSize([16 << 10], describing: "DS ARM7 BIOS"), targets: [.retroArch]
        ),
        BiosRequirement(
            id: "nds.bios9", system: .nds, name: "DS ARM9 BIOS", filename: "bios9.bin", required: false,
            summary: "The second half of a real DS BIOS set.",
            source: "Dump it from a DS you own.",
            check: .fixedSize([4 << 10], describing: "DS ARM9 BIOS"), targets: [.retroArch]
        ),
        BiosRequirement(
            id: "nds.firmware", system: .nds, name: "DS firmware", filename: "firmware.bin", required: false,
            summary: "Carries the DS boot animation and your console's nickname and settings.",
            source: "Dump it from a DS you own.",
            check: .fixedSize([128 << 10, 256 << 10], describing: "DS firmware"), targets: [.retroArch]
        ),
        BiosRequirement(
            id: "dreamcast.boot", system: .dreamcast, name: "Dreamcast boot ROM", filename: "dc_boot.bin", required: false,
            summary: "Flycast boots most games without it; with it you get the real Dreamcast start-up screen.",
            source: "Dump it from a Dreamcast you own.",
            check: .fixedSize([2 << 20], describing: "Dreamcast boot ROM"), targets: []
        ),
    ]
}

/// A folder an emulator reads BIOS files from. Only emulators whose location Cartridge is sure of are listed;
/// for the others the file stays in Cartridge's BIOS folder and the player points the emulator at it.
enum BiosTarget: String, Hashable {
    case retroArch, duckStation, pcsx2

    /// The emulator that reads this folder.
    var emulator: EmulatorID {
        switch self {
        case .retroArch: .retroarch
        case .duckStation: .duckstation
        case .pcsx2: .pcsx2
        }
    }

    var name: String {
        switch self {
        case .retroArch: "RetroArch"
        case .duckStation: "DuckStation"
        case .pcsx2: "PCSX2"
        }
    }

    var folder: URL {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        switch self {
        case .retroArch: return Paths.retroArchSystem
        case .duckStation: return support.appendingPathComponent("DuckStation/bios", isDirectory: true)
        case .pcsx2: return support.appendingPathComponent("PCSX2/bios", isDirectory: true)
        }
    }
}

extension BiosRequirement {
    /// Whether a folder already holds a usable copy: the file under the name the emulator looks for, or - for a BIOS
    /// kept under its own name - any file the check accepts.
    func isPresent(in folder: URL) -> Bool {
        let fm = FileManager.default
        if let filename { return fm.fileExists(atPath: folder.appendingPathComponent(filename).path) }
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return false }
        return files.contains { file in
            // BIOS images are a few megabytes at most; don't read anything bigger than that.
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 << 20,
                  let data = try? Data(contentsOf: file) else { return false }
            return (try? check.identify(data)) != nil
        }
    }

    /// A BIOS `system` can't boot without that the emulator running it can't see, or nil.
    /// Only folders Cartridge knows are checked: where it can't tell (PS3 firmware inside RPCS3, xemu's own
    /// settings) it says nothing rather than nag someone who set things up by hand.
    static func missing(for system: System) -> BiosRequirement? {
        all.first { requirement in
            guard requirement.system == system, requirement.required,
                  let target = requirement.targets.first(where: { $0.emulator == system.emulator }) else { return false }
            return !requirement.isPresent(in: target.folder)
        }
    }
}

// MARK: - Integrity

/// How a file is checked before Cartridge will accept it as a BIOS.
///
/// These read the format itself rather than comparing against a table of hashes: published BIOS hash lists disagree
/// with each other, and a table would reject a perfectly good dump of a model nobody wrote down. Reading the image
/// says which revision it actually is, which is the thing worth knowing.
/// ponytail: structure + recorded fingerprint. Matching against No-Intro/Redump DATs is the upgrade if anyone ever
/// needs "this is bit-identical to a known dump" rather than "this is a real BIOS and hasn't changed since".
enum BiosCheck: Hashable {
    case ps1
    case ps2
    case saturn
    case pup
    case fixedSize([Int], describing: String)

    /// A description of what the file is, or a CartridgeError saying why it isn't what it should be.
    func identify(_ data: Data) throws -> String {
        switch self {
        case .ps1: return try Bios.identifyPS1(data)
        case .ps2: return try Bios.identifyPS2(data)
        case .saturn: return try Bios.identifySaturn(data)
        case .pup: return try Bios.identifyPUP(data)
        case .fixedSize(let sizes, let label):
            guard sizes.contains(data.count) else {
                throw CartridgeError("A \(label) is \(sizes.map(Bios.size).joined(separator: " or ")); this file is \(Bios.size(data.count)). "
                                     + "If it came out of a zip or a 7z, unpack it first.")
            }
            return "\(label), \(Bios.size(data.count))"
        }
    }
}

enum Bios {
    // MARK: Identification

    /// A PS1 BIOS is 512 KB and carries Sony's copyright and a "System ROM Version 4.5 05/25/00 A" line.
    static func identifyPS1(_ data: Data) throws -> String {
        guard data.count == 512 << 10 else {
            throw CartridgeError("A PlayStation BIOS is 512 KB; this file is \(size(data.count)). "
                                 + "If it is still in a zip, unpack it first.")
        }
        guard find(data, "Sony Computer Entertainment") != nil else {
            throw CartridgeError("That file is the right size for a PlayStation BIOS but doesn't contain Sony's copyright notice, so it isn't one.")
        }
        guard let version = string(after: "System ROM Version", in: data, limit: 40) else {
            return "PlayStation BIOS, 512 KB (no version string - an unusual dump, but it looks genuine)"
        }
        // "4.5 05/25/00 A" - number, date, then a region letter.
        let fields = version.split(separator: " ").map(String.init)
        let region = fields.count >= 3 ? ps1Region(fields[2]) : nil
        return (["PlayStation BIOS", fields.first.map { "System ROM \($0)" }, fields.dropFirst().first, region]
            .compactMap { $0 }).joined(separator: " · ")
    }

    static func ps1Region(_ letter: String) -> String? {
        switch letter.prefix(1) {
        case "A": "America"
        case "E": "Europe"
        case "I", "J": "Japan"
        default: nil
        }
    }

    /// A PS2 BIOS is a ROM image whose directory starts with a RESET entry; the ROMVER entry spells out the revision.
    static func identifyPS2(_ data: Data) throws -> String {
        guard (4 << 20)...(8 << 20) ~= data.count else {
            throw CartridgeError("A PS2 BIOS is 4 MB; this file is \(size(data.count)). Cartridge needs the .bin itself, not a zip or the whole memory-card dump.")
        }
        guard let romver = romdirEntry("ROMVER", in: data), romver.count >= 14 else {
            throw CartridgeError("That file is the right size for a PS2 BIOS but has no ROM directory inside it, so it isn't one. "
                                 + "PCSX2 wants the .bin (called .ROM0 in newer dumps), not the .ROM1/.ROM2/.EROM/.DIFF files next to it.")
        }
        let text = String(decoding: romver.prefix(14), as: UTF8.self)
        let version = Double(text.prefix(4)).map { String(format: "%.2f", $0 / 100) } ?? String(text.prefix(4))
        let region = ps2Region(Array(text)[4])
        let kind = Array(text)[5] == "C" ? "retail" : "devkit"
        let date = text.dropFirst(6)
        let readable = date.count == 8 ? "\(date.prefix(4))-\(date.dropFirst(4).prefix(2))-\(date.suffix(2))" : String(date)
        return "PS2 BIOS v\(version) · \(region) \(kind) · \(readable)"
    }

    static func ps2Region(_ letter: Character) -> String {
        switch letter {
        case "J": "Japan"
        case "A": "USA"
        case "E": "Europe"
        case "H": "Asia"
        case "C": "China"
        case "T": "T10K"
        case "X": "Test"
        default: "region \(letter)"
        }
    }

    /// Walks the ROMDIR table at the front of a PS2 BIOS and returns one entry's bytes.
    /// Entries are 16 bytes - a 10-byte name, a 2-byte ext-info size and a 4-byte size - and the files they describe
    /// follow the table in the same order, each padded up to a 16-byte boundary.
    static func romdirEntry(_ wanted: String, in data: Data) -> Data? {
        let base = data.startIndex
        // The table begins at the RESET entry, 0x2700-0x2780 into every retail dump (the boot code comes first),
        // and 0x10 in the ROM1 images. The trailing NUL keeps it from matching "RESET" in text.
        guard let start = find(data, "RESET\0", searching: 0..<min(data.count, 64 << 10)) else { return nil }
        var entry = start
        var offset = 0
        while entry + 16 <= data.endIndex {
            let nameBytes = data[entry..<(entry + 10)].prefix { $0 != 0 }
            guard !nameBytes.isEmpty else { return nil }
            let name = String(decoding: nameBytes, as: UTF8.self)
            // Bytes 12...15 are the entry's length, little-endian.
            let length = (0..<4).reduce(0) { $0 | Int(data[entry + 12 + $1]) << (8 * $1) }
            if name == wanted {
                let from = base + offset
                guard from + length <= data.endIndex, length > 0 else { return nil }
                return data[from..<(from + length)]
            }
            offset += (length + 15) & ~15
            entry += 16
        }
        return nil
    }

    /// Saturn BIOS images are 512 KB and carry Sega's copyright.
    static func identifySaturn(_ data: Data) throws -> String {
        guard data.count == 512 << 10 else {
            throw CartridgeError("A Saturn BIOS is 512 KB; this file is \(size(data.count)).")
        }
        guard find(data, "SEGA") != nil else {
            throw CartridgeError("That file is the right size for a Saturn BIOS but Sega's name doesn't appear in it, so it isn't one.")
        }
        // The version line reads like "Sega Saturn OS ... Version 1.01".
        let version = string(after: "Version", in: data, limit: 12).map { "Version \($0.split(separator: " ").first ?? "")" }
        return (["Saturn BIOS, 512 KB", version].compactMap { $0 }).joined(separator: " · ")
    }

    /// A PS3 update package starts with the ASCII magic "SCEUF".
    static func identifyPUP(_ data: Data) throws -> String {
        guard data.count > 16, data.prefix(5).elementsEqual("SCEUF".utf8) else {
            throw CartridgeError("That isn't a PS3 update package. The file you want is called PS3UPDAT.PUP and starts with Sony's update header.")
        }
        // Anything under a few hundred MB is a truncated download, not firmware.
        guard data.count > 100 << 20 else {
            throw CartridgeError("That PS3UPDAT.PUP is only \(size(data.count)); a complete one is around 200 MB, so the download didn't finish.")
        }
        return "PS3 system software · \(size(data.count))"
    }

    // MARK: Fingerprints

    static func sha256(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Helpers

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    /// The index of `needle` in `data`, searched as plain ASCII.
    static func find(_ data: Data, _ needle: String, searching range: Range<Int>? = nil) -> Int? {
        let bytes = Array(needle.utf8)
        let slice = range.map { data[(data.startIndex + $0.lowerBound)..<(data.startIndex + $0.upperBound)] } ?? data[...]
        return slice.firstRange(of: bytes)?.lowerBound
    }

    /// The printable text following `marker`, up to `limit` bytes, trimmed. Used to pull version lines out of a ROM.
    static func string(after marker: String, in data: Data, limit: Int) -> String? {
        guard let index = find(data, marker) else { return nil }
        let from = index + marker.utf8.count
        let to = min(from + limit, data.endIndex)
        guard from < to else { return nil }
        let text = String(decoding: data[from..<to].prefix { $0 >= 0x20 && $0 < 0x7f }, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Store

/// A BIOS file Cartridge has accepted, and what it was when it was accepted.
struct InstalledBios: Codable, Identifiable, Hashable {
    var id: String
    var filename: String
    var identity: String
    var sha256: String
    var bytes: Int
    var added = Date()

    var url: URL { Paths.bios.appendingPathComponent(filename) }
}

/// Keeps the verified BIOS files, copies them where emulators look, and can check later that they haven't changed.
@MainActor @Observable
final class BiosStore {
    private(set) var installed: [String: InstalledBios] = [:]
    /// The result of the last "Verify" for each requirement: nil when it still matches.
    private(set) var problems: [String: String] = [:]
    var busy: Set<String> = []

    init() { load() }

    private var file: URL { Paths.root.appendingPathComponent("bios.json") }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? Library.decoder.decode([String: InstalledBios].self, from: data) else { return }
        installed = decoded
    }

    private func save() {
        _ = try? Paths.ensure(Paths.root)
        try? Library.encoder.encode(installed).write(to: file, options: .atomic)
    }

    func has(_ requirement: BiosRequirement) -> Bool { installed[requirement.id] != nil }

    /// Requirements the chosen consoles can't run without and that are still missing.
    func missing(for requirements: [BiosRequirement]) -> [BiosRequirement] {
        requirements.filter { $0.required && !has($0) }
    }

    /// Checks `source`, copies it into Cartridge's BIOS folder and into every emulator folder that wants it.
    func accept(_ source: URL, for requirement: BiosRequirement) throws {
        let data: Data
        do {
            data = try Data(contentsOf: source, options: .mappedIfSafe)
        } catch {
            throw CartridgeError("Couldn't read \(source.lastPathComponent): \(error.localizedDescription)")
        }
        let identity = try requirement.check.identify(data)
        let filename = requirement.filename ?? source.lastPathComponent
        let destination = try Paths.ensure(Paths.bios).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)

        var copyFailures: [String] = []
        for target in requirement.targets {
            do {
                let folder = try Paths.ensure(target.folder)
                let copy = folder.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: destination, to: copy)
            } catch {
                copyFailures.append(target.name)
            }
        }
        installed[requirement.id] = InstalledBios(
            id: requirement.id, filename: filename, identity: identity,
            sha256: Bios.sha256(data), bytes: data.count
        )
        problems[requirement.id] = copyFailures.isEmpty ? nil
            : "Saved, but Cartridge couldn't copy it into \(copyFailures.joined(separator: " and ")). Install the emulator first, then verify again."
        save()
    }

    /// Re-reads a stored file and reports anything that has changed since it was accepted.
    func verify(_ requirement: BiosRequirement) {
        guard let record = installed[requirement.id] else { return }
        guard let data = try? Data(contentsOf: record.url, options: .mappedIfSafe) else {
            problems[requirement.id] = "\(record.filename) is gone from Cartridge's BIOS folder."
            return
        }
        guard Bios.sha256(data) == record.sha256 else {
            problems[requirement.id] = "\(record.filename) has changed since it was added - it may be damaged. Add it again."
            return
        }
        // A copy an emulator reads can rot independently of Cartridge's own.
        for target in requirement.targets {
            let copy = target.folder.appendingPathComponent(record.filename)
            guard let copied = try? Data(contentsOf: copy, options: .mappedIfSafe) else {
                problems[requirement.id] = "\(target.name) doesn't have a copy. Use Reinstall to put it back."
                return
            }
            if Bios.sha256(copied) != record.sha256 {
                problems[requirement.id] = "The copy in \(target.name)'s folder doesn't match. Use Reinstall to replace it."
                return
            }
        }
        problems[requirement.id] = nil
    }

    /// Puts the stored copy back into the emulator folders, for when an emulator was installed afterwards.
    func reinstall(_ requirement: BiosRequirement) throws {
        guard let record = installed[requirement.id] else { return }
        try accept(record.url, for: requirement)
    }

    func remove(_ requirement: BiosRequirement) {
        guard let record = installed[requirement.id] else { return }
        try? FileManager.default.removeItem(at: record.url)
        for target in requirement.targets {
            try? FileManager.default.removeItem(at: target.folder.appendingPathComponent(record.filename))
        }
        installed[requirement.id] = nil
        problems[requirement.id] = nil
        save()
    }
}
