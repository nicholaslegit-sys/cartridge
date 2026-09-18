import Foundation

/// Works out what a dropped file or folder is, from its extension and, where that is ambiguous, its header bytes.
enum Detect {
    static let cartridgeSystems: [System] = [.nes, .snes, .n64, .gb, .gbc, .gba, .nds, .mastersystem, .genesis, .gamegear, .atari2600, .pce]

    /// Best guess at the system. nil means the player has to pick.
    static func system(for url: URL) -> System? {
        if isDirectory(url) { return folderSystem(url) }
        let ext = url.pathExtension.lowercased()
        if ext == "zip" || ext == "7z" { return archiveSystem(url) }
        let candidates = System.allCases.filter { $0.extensions.contains(ext) }
        if candidates.count == 1 { return candidates[0] }
        return candidates.isEmpty ? nil : sniff(url, ext: ext)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func folderSystem(_ url: URL) -> System? {
        if bootFile(in: url, for: .ps3) != nil { return .ps3 }
        if bootFile(in: url, for: .ps4) != nil { return .ps4 }
        return nil
    }

    /// The executable inside a PS3 or PS4 game folder that the emulator boots.
    static func bootFile(in folder: URL, for system: System) -> URL? {
        let fm = FileManager.default
        switch system {
        case .ps3:
            return ["PS3_GAME/USRDIR/EBOOT.BIN", "USRDIR/EBOOT.BIN"]
                .map { folder.appendingPathComponent($0) }
                .first { fm.fileExists(atPath: $0.path) }
        case .ps4:
            let eboot = folder.appendingPathComponent("eboot.bin")
            let sceSys = folder.appendingPathComponent("sce_sys")
            return fm.fileExists(atPath: eboot.path) && fm.fileExists(atPath: sceSys.path) ? eboot : nil
        default:
            return nil
        }
    }

    /// RetroArch opens zipped cartridge ROMs directly, so look inside for the ROM's extension.
    static func archiveSystem(_ url: URL) -> System? {
        for name in archiveListing(url) {
            let matches = cartridgeSystems.filter { $0.extensions.contains(name.pathExtension) }
            if matches.count == 1 { return matches[0] }
        }
        return nil
    }

    /// The lowercased paths inside a zip or 7z (bsdtar reads both).
    static func archiveListing(_ url: URL) -> [NSString] {
        guard let listing = try? Shell.runSync("/usr/bin/tar", ["-tf", url.path]) else { return [] }
        return listing.split(separator: "\n").map { $0.lowercased() as NSString }
    }

    /// Extensions of disc games and other non-cartridge files emulators can't boot from inside an archive.
    static let discExtensions = Set(System.allCases.filter { !cartridgeSystems.contains($0) }.flatMap(\.extensions))

    /// A zip or 7z that holds a disc image (or a PS3/PS4 folder) rather than a cartridge ROM, so it has to be unpacked.
    static func needsUnpacking(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" || ext == "7z", archiveSystem(url) == nil else { return false }
        return archiveListing(url).contains { discExtensions.contains($0.pathExtension) || $0.lastPathComponent == "eboot.bin" }
    }

    static func sniff(_ url: URL, ext: String) -> System? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        func read(_ offset: UInt64, _ count: Int) -> [UInt8] {
            guard (try? h.seek(toOffset: offset)) != nil, let d = try? h.read(upToCount: count) else { return [] }
            return [UInt8](d)
        }
        func ascii(_ offset: UInt64, _ count: Int) -> String { String(decoding: read(offset, count), as: UTF8.self) }
        func be(_ offset: UInt64, _ width: Int) -> UInt64 {
            let b = read(offset, width)
            return b.count == width ? b.reduce(0) { $0 << 8 | UInt64($1) } : 0
        }

        switch ext {
        case "rvz", "wia":
            // The WIA/RVZ disc struct starts at 0x48 with disc_type: 1 GameCube, 2 Wii.
            switch be(0x48, 4) {
            case 1: return .gamecube
            case 2: return .wii
            default: return nil
            }
        case "iso", "gcm":
            if be(0x18, 4) == 0x5D1C_9EA3 { return .wii }
            if be(0x1C, 4) == 0xC233_9F3D { return .gamecube }
            let xbox = "MICROSOFT*XBOX*MEDIA"
            if ascii(0x10000, 20) == xbox || ascii(0x1831_0000, 20) == xbox { return .xbox }
            if ascii(0x8001, 5) == "CD001" {
                let systemID = ascii(0x8008, 32)
                if systemID.hasPrefix("PSP GAME") { return .psp }
                if systemID.hasPrefix("PLAYSTATION") { return .ps2 }
            }
            return nil
        case "bin":
            if ascii(0x100, 16).contains("SEGA") { return .genesis }
            // Raw 2352-byte sectors: the ISO 9660 system identifier of sector 16 lands at 0x9320.
            if ascii(0x9320, 11) == "PLAYSTATION" { return .ps1 }
            if ascii(0x10, 15) == "SEGA SEGASATURN" { return .saturn }
            return nil
        case "cue":
            guard let text = readText(url),
                  let match = text.firstMatch(of: #/FILE\s+"([^"]+)"/#) ?? text.firstMatch(of: #/FILE\s+(\S+)/#)
            else { return nil }
            let track = url.deletingLastPathComponent().appendingPathComponent(String(match.1))
            let found = sniff(track, ext: "bin")
            return found == .ps1 || found == .saturn ? found : nil
        case "chd":
            // CHD keeps track metadata uncompressed: GD-ROM tags mean Dreamcast, DVD means PS2, CD is most often PS1.
            guard ascii(0, 8) == "MComprHD" else { return nil }
            var offset = be(12, 4) >= 5 ? be(0x30, 8) : be(0x24, 8)
            var hops = 0
            while offset != 0, hops < 64 {
                let tag = ascii(offset, 4)
                if tag == "CHGD" || tag == "CHGT" { return .dreamcast }
                if tag == "DVD " { return .ps2 }
                if tag == "CHT2" || tag == "CHTR" || tag == "CHCD" { return .ps1 }
                offset = be(offset + 8, 8)
                hops += 1
            }
            return nil
        case "pbp":
            guard read(0, 4) == [0, 0x50, 0x42, 0x50] else { return nil }
            let psar = read(0x24, 4)
            guard psar.count == 4 else { return nil }
            let magic = ascii(UInt64(le32(psar, 0)), 8)
            return magic == "PSISOIMG" || magic == "PSTITLEI" ? .ps1 : .psp
        case "m3u":
            guard let first = readText(url)?
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty && !$0.hasPrefix("#") && !$0.lowercased().hasSuffix(".m3u") })
            else { return nil }
            return system(for: url.deletingLastPathComponent().appendingPathComponent(first))
        default:
            return nil
        }
    }

    static func readText(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
    }

    static func le32(_ b: [UInt8], _ o: Int) -> Int {
        o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0
    }

    // MARK: Titles and icons

    /// "Super Mario Bros. (World) [!]" → "Super Mario Bros."
    static func title(fromFilename stem: String) -> String {
        // "Game (USA) 2" / "Game (USA) copy": a number after the tags is Finder's duplicate suffix, not a sequel.
        let stem = stem.replacingOccurrences(of: #"(?<=[\)\]])\s+(\d+|copy( \d+)?)$"#, with: "", options: .regularExpression)
        var t = stem.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        if !t.contains(" ") { t = t.replacingOccurrences(of: "_", with: " ") }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? stem : t
    }

    /// TITLE from a PlayStation PARAM.SFO.
    static func sfoTitle(_ data: Data) -> String? {
        let b = [UInt8](data)
        guard b.count >= 20, Array(b[0..<4]) == [0, 0x50, 0x53, 0x46] else { return nil }
        let keys = le32(b, 8), values = le32(b, 12), count = le32(b, 16)
        for i in 0..<min(count, 256) {
            let entry = 20 + i * 16
            guard entry + 16 <= b.count else { break }
            let keyStart = keys + (Int(b[entry]) | Int(b[entry + 1]) << 8)
            guard keyStart < b.count, let keyEnd = b[keyStart...].firstIndex(of: 0),
                  String(decoding: b[keyStart..<keyEnd], as: UTF8.self) == "TITLE" else { continue }
            let start = values + le32(b, entry + 12), length = le32(b, entry + 4)
            guard start + length <= b.count else { return nil }
            let title = String(decoding: b[start..<(start + length)], as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
            return title.isEmpty ? nil : title
        }
        return nil
    }

    /// A title and icon for a new library entry: PARAM.SFO and ICON0 where the format has them, else the filename.
    static func metadata(for url: URL, system: System) -> (title: String, icon: Data?) {
        let fallback = title(fromFilename: url.deletingPathExtension().lastPathComponent)
        func file(_ paths: [String]) -> Data? {
            paths.lazy.compactMap { try? Data(contentsOf: url.appendingPathComponent($0)) }.first
        }
        switch system {
        case .ps3 where isDirectory(url):
            let title = file(["PS3_GAME/PARAM.SFO", "PARAM.SFO"]).flatMap(sfoTitle)
            return (title ?? fallback, file(["PS3_GAME/ICON0.PNG", "ICON0.PNG"]))
        case .ps4 where isDirectory(url):
            return (file(["sce_sys/param.sfo"]).flatMap(sfoTitle) ?? fallback, file(["sce_sys/icon0.png"]))
        case .ps1 where url.pathExtension.lowercased() == "pbp", .psp where url.pathExtension.lowercased() == "pbp":
            guard let h = try? FileHandle(forReadingFrom: url), let head = try? h.read(upToCount: 4 << 20) else { return (fallback, nil) }
            try? h.close()
            let b = [UInt8](head)
            guard b.count >= 40, Array(b[0..<4]) == [0, 0x50, 0x42, 0x50] else { return (fallback, nil) }
            let sfo = le32(b, 8), icon = le32(b, 12), icon1 = le32(b, 16)
            let title = sfo < icon && icon <= b.count ? sfoTitle(Data(b[sfo..<icon])) : nil
            let png = icon < icon1 && icon1 <= b.count ? Data(b[icon..<icon1]) : nil
            return (title ?? fallback, png?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true ? png : nil)
        default:
            return (fallback, nil)
        }
    }
}
