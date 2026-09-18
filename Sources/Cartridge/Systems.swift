import SwiftUI

enum System: String, Codable, CaseIterable, Identifiable {
    case nes, snes, n64, gb, gbc, gba, nds, n3ds, gamecube, wii
    case mastersystem, genesis, gamegear, saturn, dreamcast
    case ps1, ps2, ps3, ps4, psp
    case xbox, atari2600, pce

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nes: "NES"
        case .snes: "Super Nintendo"
        case .n64: "Nintendo 64"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        case .gba: "Game Boy Advance"
        case .nds: "Nintendo DS"
        case .n3ds: "Nintendo 3DS"
        case .gamecube: "GameCube"
        case .wii: "Wii"
        case .mastersystem: "Master System"
        case .genesis: "Genesis / Mega Drive"
        case .gamegear: "Game Gear"
        case .saturn: "Saturn"
        case .dreamcast: "Dreamcast"
        case .ps1: "PlayStation"
        case .ps2: "PlayStation 2"
        case .ps3: "PlayStation 3"
        case .ps4: "PlayStation 4"
        case .psp: "PSP"
        case .xbox: "Xbox"
        case .atari2600: "Atari 2600"
        case .pce: "TurboGrafx-16"
        }
    }

    var short: String {
        switch self {
        case .nes: "NES"
        case .snes: "SNES"
        case .n64: "N64"
        case .gb: "GB"
        case .gbc: "GBC"
        case .gba: "GBA"
        case .nds: "DS"
        case .n3ds: "3DS"
        case .gamecube: "GCN"
        case .wii: "Wii"
        case .mastersystem: "SMS"
        case .genesis: "GEN"
        case .gamegear: "GG"
        case .saturn: "SAT"
        case .dreamcast: "DC"
        case .ps1: "PS1"
        case .ps2: "PS2"
        case .ps3: "PS3"
        case .ps4: "PS4"
        case .psp: "PSP"
        case .xbox: "XBOX"
        case .atari2600: "2600"
        case .pce: "TG16"
        }
    }

    var maker: String {
        switch self {
        case .nes, .snes, .n64, .gb, .gbc, .gba, .nds, .n3ds, .gamecube, .wii: "Nintendo"
        case .mastersystem, .genesis, .gamegear, .saturn, .dreamcast: "Sega"
        case .ps1, .ps2, .ps3, .ps4, .psp: "Sony"
        case .xbox: "Microsoft"
        case .atari2600: "Atari"
        case .pce: "NEC"
        }
    }

    var emulator: EmulatorID {
        switch self {
        case .ps1: .duckstation
        case .ps2: .pcsx2
        case .ps3: .rpcs3
        case .ps4: .shadps4
        case .psp: .ppsspp
        case .gamecube, .wii: .dolphin
        case .dreamcast: .flycast
        case .n3ds: .azahar
        case .xbox: .xemu
        default: .retroarch
        }
    }

    /// The libretro core RetroArch runs this system with.
    var core: String? {
        switch self {
        case .nes: "fceumm"
        case .snes: "snes9x"
        case .n64: "mupen64plus_next"
        case .gb, .gbc: "gambatte"
        case .gba: "mgba"
        case .nds: "melondsds"
        case .mastersystem, .genesis, .gamegear: "genesis_plus_gx"
        case .saturn: "mednafen_saturn"
        case .atari2600: "stella"
        case .pce: "mednafen_pce_fast"
        default: nil
        }
    }

    /// PS3 and PS4 games are dumped as folders, not single files.
    var isFolderBased: Bool { self == .ps3 || self == .ps4 }

    var extensions: Set<String> {
        switch self {
        case .nes: ["nes", "fds", "unf", "unif"]
        case .snes: ["sfc", "smc", "fig", "swc"]
        case .n64: ["n64", "z64", "v64"]
        case .gb: ["gb"]
        case .gbc: ["gbc", "cgb"]
        case .gba: ["gba"]
        case .nds: ["nds"]
        case .n3ds: ["3ds", "cci", "cxi", "3dsx"]
        case .gamecube: ["iso", "gcm", "rvz", "ciso", "gcz", "wia", "dol"]
        case .wii: ["iso", "wbfs", "rvz", "gcz", "wia", "wad"]
        case .mastersystem: ["sms"]
        case .genesis: ["md", "gen", "smd", "bin"]
        case .gamegear: ["gg"]
        case .saturn: ["cue", "chd", "ccd"]
        case .dreamcast: ["gdi", "cdi", "chd"]
        case .ps1: ["cue", "bin", "chd", "pbp", "m3u", "ecm"]
        case .ps2: ["iso", "chd", "cso"]
        case .ps3, .ps4: []
        case .psp: ["iso", "cso", "pbp", "chd"]
        case .xbox: ["iso", "xiso"]
        case .atari2600: ["a26", "bin"]
        case .pce: ["pce", "sgx"]
        }
    }

    /// Folder name on thumbnails.libretro.com, where RetroArch gets its box art.
    var thumbnailSet: String? {
        switch self {
        case .nes: "Nintendo - Nintendo Entertainment System"
        case .snes: "Nintendo - Super Nintendo Entertainment System"
        case .n64: "Nintendo - Nintendo 64"
        case .gb: "Nintendo - Game Boy"
        case .gbc: "Nintendo - Game Boy Color"
        case .gba: "Nintendo - Game Boy Advance"
        case .nds: "Nintendo - Nintendo DS"
        case .n3ds: "Nintendo - Nintendo 3DS"
        case .gamecube: "Nintendo - GameCube"
        case .wii: "Nintendo - Wii"
        case .mastersystem: "Sega - Master System - Mark III"
        case .genesis: "Sega - Mega Drive - Genesis"
        case .gamegear: "Sega - Game Gear"
        case .saturn: "Sega - Saturn"
        case .dreamcast: "Sega - Dreamcast"
        case .ps1: "Sony - PlayStation"
        case .ps2: "Sony - PlayStation 2"
        case .ps3: "Sony - PlayStation 3"
        case .psp: "Sony - PlayStation Portable"
        case .xbox: "Microsoft - Xbox"
        case .atari2600: "Atari - 2600"
        case .pce: "NEC - PC Engine - TurboGrafx 16"
        case .ps4: nil
        }
    }

    /// What the player has to supply before games boot. Cartridge never downloads BIOS or firmware dumps.
    var setupNote: String? {
        switch self {
        case .ps1: "DuckStation needs a PlayStation BIOS dumped from your own console. It asks for it on first launch."
        case .ps2: "PCSX2 needs a PS2 BIOS dumped from your own console. Its setup wizard runs on first launch."
        case .ps3: "RPCS3 needs the PS3 system software (PS3UPDAT.PUP), a free download from playstation.com. Install it from Emulators → RPCS3."
        case .ps4: "shadPS4 is experimental and many games don't boot yet. Import a dumped game folder (the one containing eboot.bin)."
        case .saturn: "Beetle Saturn needs Saturn BIOS files (sega_101.bin, mpr-17933.bin) in RetroArch's system folder. Open it from Emulators → RetroArch."
        case .xbox: "xemu needs an MCPX boot ROM, a flash BIOS and a hard disk image, set in xemu's own settings. Open xemu from Emulators."
        case .n3ds: "Azahar only runs decrypted games."
        default: nil
        }
    }

    var color: Color {
        switch maker {
        case "Nintendo": Color(red: 0.86, green: 0.16, blue: 0.20)
        case "Sega": Color(red: 0.10, green: 0.38, blue: 0.85)
        case "Sony": Color(red: 0.20, green: 0.24, blue: 0.62)
        case "Microsoft": Color(red: 0.12, green: 0.55, blue: 0.20)
        case "Atari": Color(red: 0.78, green: 0.42, blue: 0.10)
        default: Color(red: 0.45, green: 0.30, blue: 0.65)
        }
    }

    static let makers = ["Nintendo", "Sega", "Sony", "Microsoft", "Atari", "NEC"]
}
