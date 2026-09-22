import SwiftUI

/// Advanced Mode: display settings Cartridge writes into an emulator's own settings file just before it starts a game,
/// and puts back when the emulator quits. Opening the emulator by itself is untouched, and one game's override can't
/// leak into the next game.
///
/// Every key here was read from the emulator's own source (PCSX2 v2.8.2, DuckStation, Dolphin, PPSSPP, Flycast),
/// with EmuDeck's resolution presets as the reference for which multiplier makes which output size.
struct DisplayTweaks: Codable, Hashable {
    enum Resolution: String, Codable, CaseIterable, Identifiable {
        case native, hd720, hd1080, qhd1440, uhd4k
        var id: Self { self }
        var name: String {
            switch self {
            case .native: "Native"
            case .hd720: "720p"
            case .hd1080: "1080p"
            case .qhd1440: "1440p"
            case .uhd4k: "4K"
            }
        }
    }

    enum Aspect: String, Codable, CaseIterable, Identifiable {
        case auto, standard, wide, stretch
        var id: Self { self }
        var name: String {
            switch self {
            case .auto: "Game's own"
            case .standard: "4:3"
            case .wide: "16:9"
            case .stretch: "Stretch"
            }
        }
    }

    enum Option: CaseIterable { case resolution, widescreen, aspect, fullscreen }

    /// nil everywhere means "leave the emulator's own setting alone".
    var resolution: Resolution?
    var widescreen: Bool?
    var aspect: Aspect?
    var fullscreen: Bool?

    var isEmpty: Bool { self == DisplayTweaks() }

    /// This, with every setting `game` sets taking its place.
    func overlaid(by game: DisplayTweaks?) -> DisplayTweaks {
        guard let game else { return self }
        return DisplayTweaks(resolution: game.resolution ?? resolution, widescreen: game.widescreen ?? widescreen,
                             aspect: game.aspect ?? aspect, fullscreen: game.fullscreen ?? fullscreen)
    }
}

/// One setting in an emulator's file. `section` is nil for RetroArch's section-less cfg.
struct ConfigKey: Codable, Hashable {
    let file: URL
    let section: String?
    let key: String
}

extension EmulatorID {
    /// The Advanced Mode settings this emulator has a plain settings-file key for.
    var displayOptions: [DisplayTweaks.Option] {
        switch self {
        case .pcsx2, .duckstation, .dolphin: DisplayTweaks.Option.allCases
        case .ppsspp: [.resolution, .fullscreen]
        case .flycast: [.resolution, .widescreen]
        case .retroarch: [.fullscreen]
        case .rpcs3, .shadps4, .azahar, .xemu: []
        }
    }
}

enum Advanced {
    static let enabledKey = "advancedMode"

    /// The keys and values `tweaks` means for `emulator`, in its own spelling.
    static func writes(_ tweaks: DisplayTweaks, for emulator: EmulatorID) -> [(ConfigKey, String)] {
        let support = EmulatorData.support
        var out: [(ConfigKey, String)] = []
        func put(_ file: URL, _ section: String?, _ key: String, _ value: String?) {
            if let value { out.append((ConfigKey(file: file, section: section, key: key), value)) }
        }
        func scale(_ steps: [Int]) -> String? {
            tweaks.resolution.map { String(steps[DisplayTweaks.Resolution.allCases.firstIndex(of: $0)!]) }
        }
        func bool(_ value: Bool?, _ yes: String, _ no: String) -> String? { value.map { $0 ? yes : no } }
        switch emulator {
        case .pcsx2:
            let ini = EmulatorData.pcsx2Settings
            put(ini, "EmuCore/GS", "upscale_multiplier", scale([1, 2, 3, 4, 6]))
            put(ini, "EmuCore", "EnableWideScreenPatches", bool(tweaks.widescreen, "true", "false"))
            put(ini, "EmuCore/GS", "AspectRatio", tweaks.aspect.map { ["Auto 4:3/3:2", "4:3", "16:9", "Stretch"][$0.index] })
            put(ini, "UI", "StartFullscreen", bool(tweaks.fullscreen, "true", "false"))
        case .duckstation:
            let ini = EmulatorData.duckStationSettings
            put(ini, "GPU", "ResolutionScale", scale([1, 3, 5, 6, 9]))
            put(ini, "GPU", "WidescreenHack", bool(tweaks.widescreen, "true", "false"))
            put(ini, "Display", "AspectRatio", tweaks.aspect.map { ["Auto (Game Native)", "4:3", "16:9", "Stretch To Fill"][$0.index] })
            put(ini, "Main", "StartFullscreen", bool(tweaks.fullscreen, "true", "false"))
        case .dolphin:
            let config = support.appendingPathComponent("Dolphin/Config", isDirectory: true)
            let gfx = config.appendingPathComponent("GFX.ini")
            put(gfx, "Settings", "InternalResolution", scale([1, 2, 3, 4, 6]))
            put(gfx, "Settings", "wideScreenHack", bool(tweaks.widescreen, "True", "False"))
            // Dolphin's AspectMode: 0 auto, 1 force 16:9, 2 force 4:3, 3 stretch.
            put(gfx, "Settings", "AspectRatio", tweaks.aspect.map { ["0", "2", "1", "3"][$0.index] })
            put(config.appendingPathComponent("Dolphin.ini"), "Display", "Fullscreen", bool(tweaks.fullscreen, "True", "False"))
        case .ppsspp:
            // PSP renders 480x272: 4x is 1088 lines.
            let ini = (EmulatorData.root(.ppsspp) ?? EmulatorData.roots(.ppsspp)[0]).appendingPathComponent("PSP/SYSTEM/ppsspp.ini")
            put(ini, "Graphics", "InternalResolution", scale([1, 3, 4, 5, 8]))
            put(ini, "Graphics", "FullScreen", bool(tweaks.fullscreen, "True", "False"))
        case .flycast:
            // Flycast stores the output height itself, and both widescreen switches together.
            let cfg = (EmulatorData.root(.flycast) ?? EmulatorData.roots(.flycast)[0]).appendingPathComponent("emu.cfg")
            put(cfg, "config", "rend.Resolution", scale([480, 720, 1080, 1440, 2160]))
            put(cfg, "config", "rend.WideScreen", bool(tweaks.widescreen, "yes", "no"))
            put(cfg, "config", "rend.WidescreenGameHacks", bool(tweaks.widescreen, "yes", "no"))
        case .retroarch:
            put(EmulatorData.retroArchConfig, nil, "video_fullscreen", bool(tweaks.fullscreen, "true", "false"))
        case .rpcs3, .shadps4, .azahar, .xemu:
            break
        }
        return out
    }

    /// Writes the settings and returns what was there before, for `restore`. A file the emulator hasn't created yet
    /// is skipped: it writes its defaults on first run, and a stub could stop that.
    static func apply(_ writes: [(ConfigKey, String)]) throws -> [ConfigKey: String?] {
        var originals: [ConfigKey: String?] = [:]
        for file in Set(writes.map(\.0.file)) {
            try EmulatorData.edit(file) { text in
                var text = text
                for (key, value) in writes where key.file == file {
                    originals[key] = read(key, in: text)
                    text = write(key, value, in: text)
                }
                return text
            }
        }
        return originals
    }

    static func restore(_ originals: [ConfigKey: String?]) {
        for file in Set(originals.keys.map(\.file)) {
            _ = try? EmulatorData.edit(file) { text in
                originals.filter { $0.key.file == file }.reduce(text) { text, entry in write(entry.key, entry.value, in: text) }
            }
        }
    }

    static func read(_ key: ConfigKey, in text: String) -> String? {
        key.section.map { IniFile.value(key.key, section: $0, in: text) } ?? CfgFile.value(key.key, in: text)
    }

    /// Sets a value, or with nil removes the key, which puts the emulator back on its built-in default.
    static func write(_ key: ConfigKey, _ value: String?, in text: String) -> String {
        if let value {
            return key.section.map { IniFile.set(key.key, value, section: $0, in: text) } ?? CfgFile.set(key.key, value, in: text)
        }
        var section: String?
        return text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") { section = String(trimmed.dropFirst().dropLast()) }
            let name = trimmed.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
            return !(trimmed.contains("=") && name == key.key && section == key.section)
        }.joined(separator: "\n")
    }

    // MARK: Stored choices

    static var file: URL { Paths.root.appendingPathComponent("advanced.json") }
    /// Originals still to put back, in case Cartridge quits while a game is running.
    static var pendingFile: URL { Paths.root.appendingPathComponent("advanced-restore.json") }

    static func loadEmulators() -> [EmulatorID: DisplayTweaks] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([EmulatorID: DisplayTweaks].self, from: data)) ?? [:]
    }

    static func save(_ emulators: [EmulatorID: DisplayTweaks]) {
        try? JSONEncoder().encode(emulators).write(to: file, options: .atomic)
    }

    static func savePending(_ pending: [[ConfigKey: String?]]) {
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: pendingFile)
        } else {
            try? JSONEncoder().encode(pending.map { Array($0) .map(PendingValue.init) }).write(to: pendingFile, options: .atomic)
        }
    }

    /// Puts back whatever a previous run left changed.
    static func restoreLeftovers() {
        guard let data = try? Data(contentsOf: pendingFile),
              let pending = try? JSONDecoder().decode([[PendingValue]].self, from: data) else { return }
        for originals in pending { restore(Dictionary(originals.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })) }
        try? FileManager.default.removeItem(at: pendingFile)
    }

    private struct PendingValue: Codable {
        let key: ConfigKey
        let value: String?
        init(_ entry: (key: ConfigKey, value: String?)) { key = entry.key; value = entry.value }
    }
}

private extension DisplayTweaks.Aspect {
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

// MARK: - Views

extension Library {
    func emulatorTweaks(_ id: EmulatorID) -> Binding<DisplayTweaks> {
        Binding(get: { self.emulatorSettings[id] ?? DisplayTweaks() },
                set: { self.emulatorSettings[id] = $0.isEmpty ? nil : $0 })
    }

    func gameTweaks(_ id: UUID) -> Binding<DisplayTweaks> {
        Binding(get: { self.games.first { $0.id == id }?.tweaks ?? DisplayTweaks() },
                set: { self.setTweaks($0, forGame: id) })
    }
}

/// The pickers for one emulator's settings, or one game's overrides of them.
struct DisplayTweaksEditor: View {
    let emulator: EmulatorID
    @Binding var tweaks: DisplayTweaks
    /// The label for "don't set this here".
    let unset: String

    var body: some View {
        let options = emulator.displayOptions
        if options.contains(.resolution) {
            Picker("Resolution", selection: $tweaks.resolution) {
                Text(unset).tag(DisplayTweaks.Resolution?.none)
                ForEach(DisplayTweaks.Resolution.allCases) { Text($0.name).tag(Optional($0)) }
            }
        }
        if options.contains(.widescreen) {
            Picker("Widescreen hack", selection: $tweaks.widescreen) {
                Text(unset).tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
        }
        if options.contains(.aspect) {
            Picker("Aspect ratio", selection: $tweaks.aspect) {
                Text(unset).tag(DisplayTweaks.Aspect?.none)
                ForEach(DisplayTweaks.Aspect.allCases) { Text($0.name).tag(Optional($0)) }
            }
        }
        if options.contains(.fullscreen) {
            Picker("Start fullscreen", selection: $tweaks.fullscreen) {
                Text(unset).tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
        }
    }
}

struct AdvancedSettings: View {
    @Environment(Library.self) private var library
    @AppStorage(Advanced.enabledKey) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Advanced Mode", isOn: $enabled)
                Text("Set resolution, widescreen, aspect ratio and fullscreen for each emulator here, and override them for a single game in its details. Cartridge writes them into the emulator's settings when it starts a game and puts the old ones back when the emulator quits, so opening an emulator by itself is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                ForEach(EmulatorID.allCases.filter { !$0.displayOptions.isEmpty }) { emulator in
                    Section(emulator.name) {
                        DisplayTweaksEditor(emulator: emulator, tweaks: library.emulatorTweaks(emulator), unset: "Emulator's setting")
                    }
                }
                Section {
                    Text("RPCS3, shadPS4, Azahar and xemu keep these settings where Cartridge can't safely change them - set them inside the emulator.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A game's own display overrides, in its details.
struct GameTweaksSection: View {
    let game: Game
    @Environment(Library.self) private var library
    @AppStorage(Advanced.enabledKey) private var enabled = false

    var body: some View {
        let emulator = game.system.emulator
        if enabled, !emulator.displayOptions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display for This Game").font(.headline)
                Form {
                    DisplayTweaksEditor(emulator: emulator, tweaks: library.gameTweaks(game.id), unset: "Same as \(emulator.name)")
                }
                .formStyle(.columns)
                Text("Only this game. Settings left as “Same as \(emulator.name)” follow Settings → Advanced.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
