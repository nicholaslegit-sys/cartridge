import Foundation

/// Where each emulator keeps its settings and its saves on macOS.
///
/// Every location here comes from the emulator's own macOS code, not from guessing. Where versions differ, each known
/// place is listed and the first one that exists wins. RetroArch is the odd one out: its settings live in Application
/// Support, but since early 2024 its saves, states and BIOS folder live in ~/Documents/RetroArch.
enum EmulatorData {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var support: URL { home.appendingPathComponent("Library/Application Support", isDirectory: true) }

    /// Every folder an emulator might keep its data in, most likely first.
    static func roots(_ id: EmulatorID) -> [URL] {
        func support(_ name: String) -> URL { Self.support.appendingPathComponent(name, isDirectory: true) }
        switch id {
        case .retroarch: return [retroArchDocuments]
        case .duckstation: return [support("DuckStation")]
        case .pcsx2: return [support("PCSX2")]
        case .dolphin: return [support("Dolphin")]
        // PPSSPP puts its memory stick in ~/Documents/.config/ppsspp on macOS; older builds used ~/.config/ppsspp.
        case .ppsspp: return [home.appendingPathComponent("Documents/.config/ppsspp", isDirectory: true),
                              home.appendingPathComponent(".config/ppsspp", isDirectory: true)]
        case .rpcs3: return [support("rpcs3")]
        // Flycast prefers ~/.flycast when it exists.
        case .flycast: return [home.appendingPathComponent(".flycast", isDirectory: true), support("Flycast")]
        case .azahar: return [support("Azahar"), support("azahar-emu")]
        case .shadps4: return [support("shadPS4")]
        case .xemu: return [support("xemu/xemu")]
        }
    }

    static func root(_ id: EmulatorID) -> URL? {
        roots(id).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: RetroArch

    static var retroArchConfig: URL { support.appendingPathComponent("RetroArch/config/retroarch.cfg") }
    /// ~/Documents/RetroArch: where a non-portable RetroArch keeps what players are meant to find.
    static var retroArchDocuments: URL { home.appendingPathComponent("Documents/RetroArch", isDirectory: true) }

    /// A folder RetroArch's config names, else its default. "default" or blank means the default.
    static func retroArchDirectory(_ key: String, default name: String, config: String? = nil) -> URL {
        let text = config ?? (try? String(contentsOf: retroArchConfig, encoding: .utf8))
        if let text, let value = CfgFile.value(key, in: text), !value.isEmpty, value != "default" {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        }
        return retroArchDocuments.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: Saves

    /// One kind of save data an emulator keeps: a base folder plus paths inside it, which may contain * wildcards.
    struct SaveSet: Hashable {
        let name: String
        let base: URL
        let patterns: [String]

        /// The paths inside `base` that exist right now. An empty pattern means the base folder itself.
        var paths: [String] {
            patterns.flatMap { EmulatorData.expand($0, in: base) }
        }
    }

    /// Where an emulator keeps in-game saves and save states. Folders that also hold installed games (Dolphin's Wii
    /// NAND, Azahar's SD card) are narrowed to their save-data folders, so a backup isn't gigabytes of game files.
    static func saves(_ id: EmulatorID) -> [SaveSet] {
        if id == .retroarch {
            return [SaveSet(name: "Saves", base: retroArchDirectory("savefile_directory", default: "saves"), patterns: [""]),
                    SaveSet(name: "Save states", base: retroArchDirectory("savestate_directory", default: "states"), patterns: [""])]
        }
        guard let root = root(id) ?? roots(id).first else { return [] }
        func set(_ name: String, _ patterns: String...) -> SaveSet { SaveSet(name: name, base: root, patterns: patterns) }
        switch id {
        case .duckstation: return [set("Memory cards", "memcards"), set("Save states", "savestates")]
        case .pcsx2: return [set("Memory cards", "memcards"), set("Save states", "sstates")]
        case .dolphin: return [set("GameCube memory cards", "GC"), set("Wii saves", "Wii/title/00010000/*/data"), set("Save states", "StateSaves")]
        case .ppsspp: return [set("Saves", "PSP/SAVEDATA"), set("Save states", "PSP/PPSSPP_STATE")]
        case .rpcs3: return [set("Saves", "dev_hdd0/home/00000001/savedata"), set("Trophies", "dev_hdd0/home/00000001/trophy")]
        case .flycast: return [set("VMU saves and states", "data")]
        case .azahar: return [set("Saves", "sdmc/Nintendo 3DS/*/*/title/*/*/data"), set("Save states", "states")]
        case .shadps4: return [set("Saves", "user/savedata")]
        // xemu keeps saves inside its hard-disk image, which is too big to copy after every session.
        case .xemu, .retroarch: return []
        }
    }

    /// Expands a relative path whose components may contain * wildcards into the matching paths that exist.
    static func expand(_ pattern: String, in base: URL) -> [String] {
        let fm = FileManager.default
        guard !pattern.isEmpty else { return fm.fileExists(atPath: base.path) ? [""] : [] }
        var matches = [""]
        for component in pattern.split(separator: "/").map(String.init) {
            matches = matches.flatMap { prefix -> [String] in
                let folder = prefix.isEmpty ? base : base.appendingPathComponent(prefix)
                guard component.contains("*") else {
                    let path = prefix.isEmpty ? component : "\(prefix)/\(component)"
                    return fm.fileExists(atPath: base.appendingPathComponent(path).path) ? [path] : []
                }
                let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
                return names.filter { !$0.hasPrefix(".") && fnmatch(component, $0, 0) == 0 }.sorted()
                    .map { prefix.isEmpty ? $0 : "\(prefix)/\($0)" }
            }
        }
        return matches
    }

    // MARK: Settings files

    /// DuckStation's and PCSX2's main settings files.
    static var duckStationSettings: URL { support.appendingPathComponent("DuckStation/settings.ini") }
    static var pcsx2Settings: URL { support.appendingPathComponent("PCSX2/inis/PCSX2.ini") }

    /// PCSX2 shows its setup wizard instead of booting the game until that wizard is finished (cancelling it quits),
    /// and leaves its BIOS setting empty. Cartridge has already put the BIOS where PCSX2 looks, so it marks the
    /// wizard done and picks that BIOS.
    static func preparePCSX2(_ app: URL) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: pcsx2Settings.path) {
            // PCSX2 saves its full defaults, key bindings included, before it opens the wizard. Start it once and quit
            // as soon as the file is there, rather than hand-write a file that would lose those defaults.
            let process = Process()
            process.executableURL = app.appendingPathComponent("Contents/MacOS/PCSX2")
            try process.run()
            for _ in 0..<200 where !fm.fileExists(atPath: pcsx2Settings.path) {
                try await Task.sleep(for: .milliseconds(50))
            }
            process.terminate()
            await Task.detached { process.waitUntilExit() }.value
        }
        let bios = (try? fm.contentsOfDirectory(at: BiosTarget.pcsx2.folder, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { file in
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 << 20,
                      let data = try? Data(contentsOf: file) else { return false }
                return (try? Bios.identifyPS2(data)) != nil
            }
        try edit(pcsx2Settings) { text in
            var text = IniFile.set("SetupWizardIncomplete", "false", section: "UI", in: text)
            let chosen = IniFile.value("BIOS", section: "Filenames", in: text) ?? ""
            if let bios, chosen.isEmpty || !fm.fileExists(atPath: BiosTarget.pcsx2.folder.appendingPathComponent(chosen).path) {
                text = IniFile.set("BIOS", bios.lastPathComponent, section: "Filenames", in: text)
            }
            return text
        }
    }

    /// Edits a settings file an emulator owns: keeps a one-time copy of the original next to it, then writes the
    /// change atomically. Files that don't exist yet are left alone - the emulator creates them, with all its
    /// defaults, the first time it runs, and writing a stub first could skip its own first-run setup.
    @discardableResult
    static func edit(_ file: URL, _ change: (String) -> String) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return false }
        let original = try String(contentsOf: file, encoding: .utf8)
        let updated = change(original)
        guard updated != original else { return true }
        let backup = file.appendingPathExtension("cartridge-backup")
        if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
        try updated.write(to: file, atomically: true, encoding: .utf8)
        return true
    }
}

/// RetroArch's cfg format: one `key = "value"` per line, no sections.
enum CfgFile {
    static func value(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /// Sets a key, replacing its line where it is or adding it at the end, and leaves every other line alone.
    static func set(_ key: String, _ value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let line = "\(key) = \"\(value)\""
        if let index = lines.firstIndex(where: { $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key }) {
            lines[index] = line
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append(line)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// The INI format DuckStation and PCSX2 use: `[Section]` headers and `Key = Value` lines, where a key can repeat to
/// hold several values.
enum IniFile {
    static func value(_ key: String, section: String, in text: String) -> String? {
        var current = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") { current = String(line.dropFirst().dropLast()); continue }
            guard current == section else { continue }
            // Keep an empty value: "Key =" is a key set to nothing, not a missing key.
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Sets `key = value` in `[section]`: every existing value of that key in the section is replaced by the one
    /// line, the section is added if it's missing, and nothing else changes.
    static func set(_ key: String, _ value: String, section: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let entry = "\(key) = \(value)"
        func isKey(_ line: String) -> Bool {
            line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key && line.contains("=")
        }
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else {
            while lines.last == "" { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines += ["[\(section)]", entry, ""]
            return lines.joined(separator: "\n")
        }
        let end = lines[(header + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.endIndex
        let existing = lines[(header + 1)..<end].indices.filter { isKey(lines[$0]) }
        if let first = existing.first {
            lines[first] = entry
            for index in existing.dropFirst().reversed() { lines.remove(at: index) }
        } else {
            // After the section's last non-blank line, so a blank line separating sections stays where it was.
            var insert = end
            while insert > header + 1, lines[insert - 1].trimmingCharacters(in: .whitespaces).isEmpty { insert -= 1 }
            lines.insert(entry, at: insert)
        }
        return lines.joined(separator: "\n")
    }
}
