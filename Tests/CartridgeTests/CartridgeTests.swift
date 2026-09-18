import AppKit
import CryptoKit
import SceneKit
import Testing
import WebKit
@testable import Cartridge

/// A scratch directory per test. Cartridge's own data goes under a separate throwaway home.
struct Scratch {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cartridge-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func file(_ name: String, size: Int = 0x400, patches: [(Int, [UInt8])] = []) throws -> URL {
        var bytes = [UInt8](repeating: 0, count: size)
        for (offset, patch) in patches { bytes.replaceSubrange(offset..<(offset + patch.count), with: patch) }
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }

    func text(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

enum TestHome {
    /// Paths.root reads CARTRIDGE_HOME once, so set it before anything touches Paths.
    static let url: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cartridge-home-\(UUID().uuidString)", isDirectory: true)
        setenv("CARTRIDGE_HOME", url.path, 1)
        return url
    }()
}

func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
func be64(_ v: UInt64) -> [UInt8] { (0..<8).reversed().map { UInt8(v >> (UInt64($0) * 8) & 0xFF) } }
func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }

@Suite struct DetectionTests {
    @Test func uniqueExtensions() throws {
        let s = try Scratch()
        #expect(Detect.system(for: try s.file("a.nes")) == .nes)
        #expect(Detect.system(for: try s.file("a.SFC")) == .snes)
        #expect(Detect.system(for: try s.file("a.z64")) == .n64)
        #expect(Detect.system(for: try s.file("a.gdi")) == .dreamcast)
        #expect(Detect.system(for: try s.file("a.wbfs")) == .wii)
        #expect(Detect.system(for: try s.file("a.3ds")) == .n3ds)
        #expect(Detect.system(for: try s.file("a.txt")) == nil)
    }

    @Test func discImagesByHeader() throws {
        let s = try Scratch()
        #expect(Detect.system(for: try s.file("gc.iso", patches: [(0x1C, be32(0xC233_9F3D))])) == .gamecube)
        #expect(Detect.system(for: try s.file("wii.iso", patches: [(0x18, be32(0x5D1C_9EA3))])) == .wii)
        #expect(Detect.system(for: try s.file("ps2.iso", size: 0x9000, patches: [(0x8001, ascii("CD001")), (0x8008, ascii("PLAYSTATION"))])) == .ps2)
        #expect(Detect.system(for: try s.file("psp.iso", size: 0x9000, patches: [(0x8001, ascii("CD001")), (0x8008, ascii("PSP GAME"))])) == .psp)
        #expect(Detect.system(for: try s.file("xbox.iso", size: 0x10100, patches: [(0x10000, ascii("MICROSOFT*XBOX*MEDIA"))])) == .xbox)
        #expect(Detect.system(for: try s.file("blank.iso", size: 0x9000)) == nil)
        #expect(Detect.system(for: try s.file("gc.rvz", patches: [(0, ascii("RVZ\u{1}")), (0x48, be32(1))])) == .gamecube)
        #expect(Detect.system(for: try s.file("wii.wia", patches: [(0x48, be32(2))])) == .wii)
    }

    @Test func binCueAndPlaylists() throws {
        let s = try Scratch()
        #expect(Detect.system(for: try s.file("sonic.bin", patches: [(0x100, ascii("SEGA GENESIS"))])) == .genesis)
        let ps1 = try s.file("crash.bin", size: 0x9400, patches: [(0x9320, ascii("PLAYSTATION"))])
        #expect(Detect.system(for: ps1) == .ps1)
        #expect(Detect.system(for: try s.file("atari.bin")) == nil)

        let cue = try s.text("crash.cue", "FILE \"crash.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n")
        #expect(Detect.system(for: cue) == .ps1)
        _ = try s.file("nights.bin", size: 0x100, patches: [(0x10, ascii("SEGA SEGASATURN "))])
        #expect(Detect.system(for: try s.text("nights.cue", "FILE nights.bin BINARY\n")) == .saturn)
        #expect(Detect.system(for: try s.text("crash.m3u", "# discs\ncrash.cue\n")) == .ps1)
    }

    @Test func chdMetadata() throws {
        let s = try Scratch()
        func chd(_ name: String, tag: String) throws -> URL {
            try s.file(name, size: 0x200, patches: [
                (0, ascii("MComprHD")), (12, be32(5)), (0x30, be64(0x100)),
                (0x100, ascii(tag)), (0x108, be64(0)),
            ])
        }
        #expect(Detect.system(for: try chd("dc.chd", tag: "CHGD")) == .dreamcast)
        #expect(Detect.system(for: try chd("ps2.chd", tag: "DVD ")) == .ps2)
        #expect(Detect.system(for: try chd("ps1.chd", tag: "CHT2")) == .ps1)
        #expect(Detect.system(for: try s.file("junk.chd")) == nil)
    }

    @Test func pbpTellsPS1FromPSP() throws {
        let s = try Scratch()
        let ps1 = try s.file("classic.pbp", size: 0x200, patches: [(0, [0, 0x50, 0x42, 0x50]), (0x24, le32(0x100)), (0x100, ascii("PSISOIMG0000"))])
        let psp = try s.file("homebrew.pbp", size: 0x200, patches: [(0, [0, 0x50, 0x42, 0x50]), (0x24, le32(0x100))])
        #expect(Detect.system(for: ps1) == .ps1)
        #expect(Detect.system(for: psp) == .psp)
    }

    @Test func zippedCartridges() async throws {
        let s = try Scratch()
        let rom = try s.file("zipme/Chrono Trigger (USA).sfc")
        let zip = s.dir.appendingPathComponent("chrono.zip")
        try await Shell.run("/usr/bin/ditto", ["-c", "-k", rom.deletingLastPathComponent().path, zip.path])
        #expect(Detect.system(for: zip) == .snes)
        #expect(Detect.system(for: try s.file("notanarchive.zip")) == nil)
    }

    @Test func playStationFolders() throws {
        let s = try Scratch()
        _ = try s.file("BLUS30001/PS3_GAME/USRDIR/EBOOT.BIN")
        let ps3 = s.dir.appendingPathComponent("BLUS30001")
        #expect(Detect.system(for: ps3) == .ps3)
        #expect(Detect.bootFile(in: ps3, for: .ps3)?.lastPathComponent == "EBOOT.BIN")

        _ = try s.file("CUSA00001/eboot.bin")
        _ = try s.file("CUSA00001/sce_sys/param.sfo")
        #expect(Detect.system(for: s.dir.appendingPathComponent("CUSA00001")) == .ps4)

        _ = try s.file("random/eboot.bin")
        #expect(Detect.system(for: s.dir.appendingPathComponent("random")) == nil)
    }

    @Test func titles() {
        #expect(Detect.title(fromFilename: "Super Mario Bros. (World)") == "Super Mario Bros.")
        #expect(Detect.title(fromFilename: "Final Fantasy VII (USA) (Disc 1) [!]") == "Final Fantasy VII")
        #expect(Detect.title(fromFilename: "tiny_golf") == "tiny golf")
        // Finder's duplicate suffix after the tags isn't part of the title; a sequel number before them is.
        #expect(Detect.title(fromFilename: "LEGO Star Wars - The Video Game (USA) (v2.00) 2") == "LEGO Star Wars - The Video Game")
        #expect(Detect.title(fromFilename: "Tekken 3 (USA) copy") == "Tekken 3")
        #expect(Detect.title(fromFilename: "Tekken 3 (USA)") == "Tekken 3")
        #expect(Detect.title(fromFilename: "(Beta)") == "(Beta)")
    }

    @Test func paramSFO() throws {
        // One TITLE entry: 20-byte header, one 16-byte index entry, key table, data table.
        let key = ascii("TITLE") + [0, 0, 0]
        let value = ascii("Demon's Souls") + [0]
        var sfo: [UInt8] = [0, 0x50, 0x53, 0x46, 1, 1, 0, 0]
        sfo += le32(20 + 16) + le32(20 + 16 + key.count) + le32(1)
        sfo += [0, 0, 4, 2] + le32(value.count) + le32(value.count) + le32(0)
        sfo += key + value
        #expect(Detect.sfoTitle(Data(sfo)) == "Demon's Souls")
        #expect(Detect.sfoTitle(Data([1, 2, 3])) == nil)
    }
}

@Suite struct LibraryFileTests {
    @Test func companionsOfMultiFileDiscs() throws {
        let s = try Scratch()
        _ = try s.file("Track 01.bin")
        _ = try s.file("Track 02.bin")
        let cue = try s.text("game.cue", "FILE \"Track 01.bin\" BINARY\nTRACK 01 MODE2/2352\nFILE \"Track 02.bin\" BINARY\nTRACK 02 AUDIO\n")
        #expect(try Library.companions(of: cue) == ["game.cue", "Track 01.bin", "Track 02.bin"])

        _ = try s.file("track01.bin")
        _ = try s.file("track 02.raw")
        let gdi = try s.text("dc.gdi", "2\n1 0 4 2352 track01.bin 0\n2 600 0 2352 \"track 02.raw\" 0\n")
        #expect(try Library.companions(of: gdi) == ["dc.gdi", "track01.bin", "track 02.raw"])

        let broken = try s.text("broken.cue", "FILE \"missing.bin\" BINARY\n")
        #expect(throws: CartridgeError.self) { try Library.companions(of: broken) }
        let escaping = try s.text("escape.cue", "FILE \"../elsewhere.bin\" BINARY\n")
        #expect(throws: CartridgeError.self) { try Library.companions(of: escaping) }

        // A playlist entry that leaves the folder is rejected for that, not for whatever the file out there says:
        // the escaping .cue must never be opened, and its own missing track must never be the complaint.
        _ = try s.text("outside.cue", "FILE \"gone.bin\" BINARY\n")
        let playlist = try s.text("inner/discs.m3u", "../outside.cue\n")
        let error = #expect(throws: CartridgeError.self) { try Library.companions(of: playlist) }
        #expect(error?.message.contains("points outside its folder") == true, "\(error?.message ?? "no error")")
    }

    @Test func copyKeepsTracksTogether() throws {
        _ = TestHome.url
        let s = try Scratch()
        _ = try s.file("Crash (USA).bin")
        let cue = try s.text("Crash (USA).cue", "FILE \"Crash (USA).bin\" BINARY\n")
        let first = try Library.copyIntoLibrary(cue, system: .ps1)
        let second = try Library.copyIntoLibrary(cue, system: .ps1)
        #expect(first.lastPathComponent == "Crash (USA).cue")
        #expect(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().appendingPathComponent("Crash (USA).bin").path))
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(first.path.hasPrefix(TestHome.url.path))
    }

    @Test func zippedDiscIsUnpackedAndMovedIn() throws {
        _ = TestHome.url
        let s = try Scratch()
        // Raw PS1 sectors: "PLAYSTATION" where sector 16's system identifier lands.
        _ = try s.file("disc/Crash (USA).bin", size: 0xA000, patches: [(0x9320, ascii("PLAYSTATION"))])
        _ = try s.text("disc/Crash (USA).cue", "FILE \"Crash (USA).bin\" BINARY\n")
        _ = try s.text("disc/readme.txt", "hi")
        let zip = s.dir.appendingPathComponent("Crash.zip")
        _ = try Shell.runSync("/usr/bin/ditto", ["-c", "-k", s.dir.appendingPathComponent("disc").path, zip.path])
        let cartridgeZip = s.dir.appendingPathComponent("Mario.zip")
        _ = try s.file("rom/Mario (USA).nes")
        _ = try Shell.runSync("/usr/bin/ditto", ["-c", "-k", s.dir.appendingPathComponent("rom").path, cartridgeZip.path])

        #expect(Detect.needsUnpacking(zip))
        // RetroArch boots zipped cartridge ROMs as they are.
        #expect(!Detect.needsUnpacking(cartridgeZip))

        let items = try Library.unpack(zip)
        #expect(items.map(\.url.lastPathComponent) == ["Crash (USA).cue"])
        #expect(items.first?.system == .ps1)
        let folder = try #require(items.first?.unpackedFolder)
        #expect(folder.path.hasPrefix(Paths.unpacking.path))

        let added = try Library.copyIntoLibrary(items[0].url, system: .ps1)
        #expect(FileManager.default.fileExists(atPath: added.deletingLastPathComponent().appendingPathComponent("Crash (USA).bin").path))
        // Moved, not copied.
        #expect(!FileManager.default.fileExists(atPath: items[0].url.path))
    }

    @Test func managedFolderIgnoresTheGamesCurrentSystem() {
        let games = URL(fileURLWithPath: "/Lib/Games")
        #expect(Library.managedFolder(of: URL(fileURLWithPath: "/Lib/Games/ps1/Crash/Crash.cue"), games: games)?.path == "/Lib/Games/ps1/Crash")
        #expect(Library.managedFolder(of: URL(fileURLWithPath: "/Lib/Games/ps3/BLUS30001"), games: games)?.path == "/Lib/Games/ps3/BLUS30001")
        #expect(Library.managedFolder(of: URL(fileURLWithPath: "/Lib/Games/ps3"), games: games) == nil)
        #expect(Library.managedFolder(of: URL(fileURLWithPath: "/Elsewhere/ps1/Crash/Crash.cue"), games: games) == nil)
        #expect(Library.managedFolder(of: URL(fileURLWithPath: "/Lib/Games/../Games2/x/y"), games: games) == nil)
    }

    @Test func thumbnailNames() {
        let url = Library.thumbnailURL(.nes, name: "Mario & Luigi: Test?")
        #expect(url?.absoluteString == "https://thumbnails.libretro.com/Nintendo%20-%20Nintendo%20Entertainment%20System/Named_Boxarts/Mario%20_%20Luigi_%20Test_.png")
        #expect(Library.thumbnailURL(.ps4, name: "x") == nil)
    }
}

@Suite struct ReleaseTests {
    func release(_ tag: String, _ names: [String], repo: String? = nil, host: String = "github.com") -> Data {
        let assets = names.map { name -> String in
            let base = "https://\(host)/\(repo ?? "OWNER/REPO")/releases/download/\(tag)"
            return #"{"name":"\#(name)","browser_download_url":"\#(base)/\#(name)","updated_at":"2026-09-01T10:00:00Z"}"#
        }
        return Data(#"{"tag_name":"\#(tag)","assets":[\#(assets.joined(separator: ","))]}"#.utf8)
    }

    @Test func picksTheMacBuild() throws {
        let cases: [(EmulatorID, String, [String], String, String)] = [
            (.duckstation, "latest", ["DuckStation-arm64.AppImage", "duckstation-mac-release.zip", "duckstation-windows-arm64-release.zip"], "duckstation-mac-release.zip", "2026-09-01"),
            (.pcsx2, "v2.8.2", ["pcsx2-v2.8.2-linux-appimage-x64-Qt.AppImage", "pcsx2-v2.8.2-macos-Qt.tar.xz"], "pcsx2-v2.8.2-macos-Qt.tar.xz", "2.8.2"),
            (.rpcs3, "build-6c0e", ["rpcs3-v0.0.42-20018-6c0e2823_macos_aarch64.7z"], "rpcs3-v0.0.42-20018-6c0e2823_macos_aarch64.7z", "0.0.42-20018"),
            (.shadps4, "v.0.18.0", ["shadps4-linux-sdl-0.18.0.zip", "shadps4-macos-sdl-0.18.0.zip"], "shadps4-macos-sdl-0.18.0.zip", "0.18.0"),
            (.ppsspp, "v1.20.4", ["PPSSPP-v1.20.4-Windows-ARM64.zip", "PPSSPPSDL-macOS-v1.20.4.zip"], "PPSSPPSDL-macOS-v1.20.4.zip", "1.20.4"),
            (.flycast, "v2.7", ["flycast-win64-2.7.zip", "flycast-macOS-2.7.zip"], "flycast-macOS-2.7.zip", "2.7"),
            (.azahar, "2126.1.1", ["azahar-libretro-macos-arm64-2126.1.1.zip", "azahar-macos-arm64-2126.1.1.zip", "azahar-macos-universal-2126.1.1.zip"], "azahar-macos-universal-2126.1.1.zip", "2126.1.1"),
            (.xemu, "v0.8.136", ["xemu-0.8.136-dbg-macos-universal-unsigned.zip", "xemu-0.8.136-macos-universal-unsigned.zip", "xemu-0.8.136-macos-universal.zip"], "xemu-0.8.136-macos-universal.zip", "0.8.136"),
        ]
        for (id, tag, names, expected, version) in cases {
            let picked = try Releases.pick(id, fromGitHub: release(tag, names, repo: id.githubRepo))
            #expect(picked.url.lastPathComponent == expected, "\(id)")
            #expect(picked.version == version, "\(id)")
        }
        #expect(throws: CartridgeError.self) { try Releases.pick(.pcsx2, fromGitHub: release("v1", ["pcsx2-windows.7z"])) }
    }

    /// The download link arrives inside an API response, so it has to point back at the release it claims to be.
    @Test func refusesDownloadLinksThatLeaveTheProject() throws {
        let assets = ["flycast-macOS-2.7.zip"]
        #expect(throws: CartridgeError.self) {
            try Releases.pick(.flycast, fromGitHub: release("v2.7", assets, repo: "flyinghead/flycast", host: "githu8.com"))
        }
        #expect(throws: CartridgeError.self) {
            try Releases.pick(.flycast, fromGitHub: release("v2.7", assets, repo: "attacker/flycast"))
        }
        // GitHub is case-insensitive about owner and repository, so the same link in another case is still fine.
        #expect(try Releases.pick(.flycast, fromGitHub: release("v2.7", assets, repo: "FlyingHead/Flycast")).version == "2.7")
    }

    @Test func dolphinBuildsMustComeFromDolphin() throws {
        func update(_ url: String) -> Data {
            Data(#"{"shortrev":"2606a","artifacts":[{"system":"macOS Universal","url":"\#(url)"}]}"#.utf8)
        }
        let release = try Releases.pick(fromDolphin: update("https://dl.dolphin-emu.org/releases/2606a/dolphin-2606a-universal.dmg"))
        #expect(release == Release(version: "2606a", url: URL(string: "https://dl.dolphin-emu.org/releases/2606a/dolphin-2606a-universal.dmg")!))
        #expect(throws: CartridgeError.self) { try Releases.pick(fromDolphin: update("https://dl.dolphin-emu.org.evil.test/x.dmg")) }
        #expect(throws: CartridgeError.self) { try Releases.pick(fromDolphin: update("http://dl.dolphin-emu.org/x.dmg")) }
        #expect(throws: CartridgeError.self) { try Releases.pick(fromDolphin: update("https://dl.dolphin-emu.org/x.zip")) }
    }

    @Test func retroArchListing() {
        let html = #"<a href="/stable/1.9.9/">1.9.9</a><a href="/stable/1.22.2/">x</a><a href="/stable/1.22.10/">x</a><a href="/stable/1.10.0/">x</a>"#
        #expect(Releases.retroArchVersions(in: html) == ["1.22.10", "1.22.2", "1.10.0", "1.9.9"])
    }

    @Test func launchArguments() {
        let game = URL(fileURLWithPath: "/Games/Some Game.iso")
        let core = URL(fileURLWithPath: "/cores/snes9x_libretro.dylib")
        #expect(EmulatorID.retroarch.arguments(game: game, core: core) == ["-L", core.path, game.path])
        #expect(EmulatorID.dolphin.arguments(game: game, core: nil) == ["-e", game.path])
        #expect(EmulatorID.pcsx2.arguments(game: game, core: nil) == ["--", game.path])
        #expect(EmulatorID.xemu.arguments(game: game, core: nil) == ["-dvd_path", game.path])
        for system in System.allCases {
            #expect((system.core != nil) == (system.emulator == .retroarch), "\(system)")
        }
    }
}

@Suite struct InstallTests {
    func makeApp(_ root: URL, _ name: String) throws {
        let macOS = root.appendingPathComponent("\(name).app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: macOS.appendingPathComponent(name))
    }

    @Test func locatesAppsAndBinaries() throws {
        let s = try Scratch()
        try makeApp(s.dir.appendingPathComponent("azahar-macos-universal/"), "Azahar")
        #expect(Installer.locate(.azahar, in: s.dir)?.lastPathComponent == "Azahar.app")

        let bin = try Scratch()
        let exe = try bin.file("shadps4")
        #expect(Installer.locate(.shadps4, in: bin.dir) == nil, "not executable yet")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        #expect(Installer.locate(.shadps4, in: bin.dir)?.lastPathComponent == "shadps4")
    }

    /// Cartridge downloads emulators itself, so macOS never quarantines them and Gatekeeper never sees them.
    /// What is left is the signature on the build and the signer of the copy already installed.
    @Test func readsSignersAndRefusesAChangeOfSigner() async throws {
        let s = try Scratch()
        try makeApp(s.dir, "Flycast")
        let app = s.dir.appendingPathComponent("Flycast.app")
        try await Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])

        // Ad-hoc signed, like several emulator builds: no team to pin, and nothing to refuse it over.
        #expect(CodeSignature.team(of: app) == nil)
        #expect(try CodeSignature.verifiedTeam(of: app, name: "Flycast") == nil)
        #expect(CodeSignature.team(of: s.dir.appendingPathComponent("nothing-here.app")) == nil)

        #expect(CodeSignature.changedSigner(installed: nil, replacement: "ABCDE12345") == nil, "first install pins nothing")
        #expect(CodeSignature.changedSigner(installed: "ABCDE12345", replacement: "ABCDE12345") == nil)
        #expect(CodeSignature.changedSigner(installed: "ABCDE12345", replacement: "99999ZZZZZ") != nil, "signed by someone else")
        #expect(CodeSignature.changedSigner(installed: "ABCDE12345", replacement: nil) != nil, "signature dropped")
    }

    @Test func extractsZipTarAndDmg() async throws {
        let s = try Scratch()
        let src = s.dir.appendingPathComponent("src", isDirectory: true)
        try makeApp(src, "Flycast")

        let zip = s.dir.appendingPathComponent("flycast.zip")
        try await Shell.run("/usr/bin/ditto", ["-c", "-k", src.path, zip.path])
        let tar = s.dir.appendingPathComponent("pcsx2.tar.xz")
        try await Shell.run("/usr/bin/tar", ["-cJf", tar.path, "-C", src.path, "Flycast.app"])
        let dmg = s.dir.appendingPathComponent("dolphin.dmg")
        try await Shell.run("/usr/bin/hdiutil", ["create", "-quiet", "-fs", "HFS+", "-srcfolder", src.path, "-volname", "Test", dmg.path])

        for archive in [zip, tar, dmg] {
            let out = s.dir.appendingPathComponent("out-\(archive.lastPathComponent)", isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try await Archive.extract(archive, into: out)
            #expect(Installer.locate(.flycast, in: out)?.lastPathComponent == "Flycast.app", "\(archive.lastPathComponent)")
        }
    }
}

@Suite struct DemoModeTests {
    /// The demo set is empty files laid out like copied games, one folder each, under the games folder it's given.
    @Test func createsPlaceholderGames() throws {
        let s = try Scratch()
        let games = Library.demoGames(in: s.dir)
        #expect(games.count == Library.demoTitles.count)
        for game in games {
            #expect(game.managed)
            #expect(game.path.hasPrefix(s.dir.appendingPathComponent(game.system.rawValue).path + "/"))
            #expect((try FileManager.default.attributesOfItem(atPath: game.path)[.size] as? Int) == 0)
            #expect(Library.managedFolder(of: game.url, games: s.dir) == game.url.deletingLastPathComponent())
        }
    }
}

@Suite struct HomebrewTests {
    @Test func decodesTheShapesTheDatabaseUses() throws {
        let json = #"""
        {"results": 3, "page_total": 1, "page_current": 1, "entries": [
          {"slug": "a", "title": "A", "platform": "GBC", "basepath": "database-gb", "developer": ["X", "Y"],
           "files": [{"filename": "a_df.zip"}, {"filename": "a.cgb", "default": true, "playable": true}], "screenshots": ["1.png"]},
          {"slug": "wrymouth_dvd", "title": "DVD", "platform": "NES", "basepath": "database-nes", "developer": {"name": "W"},
           "files": [{"filename": "files/dvd logo.nes", "default": true, "playable": true}], "screenshots": []},
          {"title": "broken, no slug"}
        ]}
        """#
        let page = try JSONDecoder().decode(HomebrewPage.self, from: Data(json.utf8))
        let entries = page.entries.compactMap(\.value)
        #expect(entries.count == 2)
        #expect(entries[0].developer == "X, Y")
        #expect(entries[0].system == .gbc)
        #expect(entries[0].romFile?.filename == "a.cgb")
        #expect(entries[1].developer == nil)
        #expect(entries[1].fileURL(entries[1].romFile!.filename)?.absoluteString == "https://hh3.gbdev.io/static/database-nes/entries/wrymouth_dvd/files/dvd%20logo.nes")
    }

    /// The slug becomes a folder under Games and the website is a clickable link, so both come from the server
    /// untrusted: a slug that leads out of the folder drops the entry, and a non-web link is dropped.
    @Test func refusesUnsafeSlugsAndLinks() throws {
        let json = #"""
        {"results": 4, "page_total": 1, "page_current": 1, "entries": [
          {"slug": "../../../outside", "title": "A", "platform": "GB", "basepath": "database-gb"},
          {"slug": "..", "title": "B", "platform": "GB", "basepath": "database-gb"},
          {"slug": "ok", "title": "C", "platform": "GB", "basepath": "database-gb", "gameWebsite": "file:///Applications/Calculator.app"},
          {"slug": "fine", "title": "D", "platform": "GB", "basepath": "database-gb", "gameWebsite": "https://example.com"}
        ]}
        """#
        let entries = try JSONDecoder().decode(HomebrewPage.self, from: Data(json.utf8)).entries.compactMap(\.value)
        #expect(entries.map(\.slug) == ["ok", "fine"])
        #expect(entries[0].website == nil)
        #expect(entries[1].website?.absoluteString == "https://example.com")
    }

    @Test func searchSpellings() {
        #expect(HomebrewStore.spellings(of: "golf") == ["golf", "Golf", "GOLF"])
    }
}

/// Checks the emulator signature rules against a real Developer ID signed app, which no test can produce on its own.
/// Run with CARTRIDGE_SIGNED_APP="/Applications/Some App.app" swift test --filter SignatureTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_SIGNED_APP"] != nil))
struct SignatureTests {
    @Test func aTamperedBuildIsRefused() async throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CARTRIDGE_SIGNED_APP"]!)
        let s = try Scratch()
        let app = s.dir.appendingPathComponent(source.lastPathComponent)
        try await Shell.run("/usr/bin/ditto", [source.path, app.path])

        let team = try #require(CodeSignature.team(of: app), "\(source.lastPathComponent) has no Team ID to check")
        #expect(try CodeSignature.verifiedTeam(of: app, name: "Test") == team, "an untouched build verifies")

        // What a hijacked release would have to do: change the code and keep the signature that was already there.
        let binary = try #require(Bundle(url: app)?.executableURL)
        let handle = try FileHandle(forWritingTo: binary)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        #expect(CodeSignature.team(of: app) == team, "the claimed team is still readable")
        #expect(throws: CartridgeError.self) { try CodeSignature.verifiedTeam(of: app, name: "Test") }
        #expect(CodeSignature.changedSigner(installed: team, replacement: nil) != nil, "and an unsigned replacement is refused")
    }
}

/// Hits the real download servers. Run with CARTRIDGE_LIVE=1 swift test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_LIVE"] == "1"))
struct LiveTests {
    @Test(arguments: EmulatorID.allCases)
    func latestReleaseDownloadExists(_ id: EmulatorID) async throws {
        let release = try await Releases.latest(id)
        #expect(await Net.exists(release.url), "\(id): \(release.url)")
    }

    @Test func coresExist() async {
        for core in Set(System.allCases.compactMap(\.core)) {
            #expect(await Net.exists(Releases.coreURL(core)), "\(core)")
        }
    }

    @Test func launchBoxImagesAndDump() async throws {
        #expect(await Net.exists(URL(string: "https://images.launchbox-app.com/948416f7-a97e-44a5-9629-c054dc9f83c5.jpg")!))
        #expect(await Net.exists(LaunchBox.dumpURL))
    }

    @Test func homebrewAndBoxArt() async throws {
        let page = try await HomebrewStore.fetch(platform: "NES", title: nil, page: 1)
        let entry = try #require(page.entries.compactMap(\.value).first)
        let rom = try #require(entry.romFile)
        #expect(await Net.exists(try #require(entry.fileURL(rom.filename))))
        #expect(await Net.exists(try #require(Library.thumbnailURL(.nes, name: "Super Mario Bros. (World)"))))
    }
}

/// Serves canned HTTP responses to URLSession.shared so downloads can be tested without a network.
final class StubProtocol: URLProtocol {
    /// Keyed by host + path, e.g. "api.igdb.com/v4/games". Anything on stub.cartridge.test is always intercepted.
    nonisolated(unsafe) static var routes: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func key(_ url: URL?) -> String { (url?.host ?? "") + (url?.path ?? "") }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.cartridge.test" || routes[key(request.url)] != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let route = Self.routes[Self.key(request.url)] ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": String(route.body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliver in chunks so progress reporting has something to report.
        stride(from: 0, to: route.body.count, by: 64_000).forEach { start in
            client?.urlProtocol(self, didLoad: route.body.subdata(in: start..<min(start + 64_000, route.body.count)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Both suites swap URLSession's protocol handlers, so they must never overlap.
@Suite(.serialized) struct StubbedNetworkTests {
@Suite struct DownloadTests {
    @Test func downloadsExtractsAndLocatesAnApp() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let s = try Scratch()
        try InstallTests().makeApp(s.dir.appendingPathComponent("src"), "PPSSPPSDL")
        _ = try s.file("src/padding.bin", size: 600_000)
        let zip = s.dir.appendingPathComponent("ppsspp.zip")
        try await Shell.run("/usr/bin/ditto", ["-c", "-k", s.dir.appendingPathComponent("src").path, zip.path])
        StubProtocol.routes["stub.cartridge.test/ppsspp.zip"] = (200, try Data(contentsOf: zip))

        let destination = s.dir.appendingPathComponent("downloaded.zip")
        let reports = Reports()
        try await Net.download(URL(string: "https://stub.cartridge.test/ppsspp.zip")!, to: destination) { reports.add($0) }
        #expect(try Data(contentsOf: destination) == Data(contentsOf: zip))
        #expect(reports.last == 1)

        let out = s.dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try await Archive.extract(destination, into: out)
        #expect(Installer.locate(.ppsspp, in: out)?.lastPathComponent == "PPSSPPSDL.app")
    }

    /// A Homebrew Hub entry whose file is named ".." used to aim the download at the console's whole games folder,
    /// which is deleted before the file is moved into place.
    @Test func refusesNamesThatEscapeTheirFolder() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let s = try Scratch()
        let keep = try s.file("gb/other-game.gb")
        let folder = s.dir.appendingPathComponent("gb/new-game", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StubProtocol.routes["stub.cartridge.test/rom.gb"] = (200, Data("rom".utf8))
        let url = URL(string: "https://stub.cartridge.test/rom.gb")!

        for name in ["..", "files/..", "."] {
            let destination = folder.appendingPathComponent((name as NSString).lastPathComponent)
            await #expect(throws: CartridgeError.self, "\(name)") { try await Net.download(url, to: destination) { _ in } }
        }
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func httpErrorsThrowAndLeaveNoFile() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let s = try Scratch()
        let destination = s.dir.appendingPathComponent("missing.zip")
        await #expect(throws: CartridgeError.self) {
            try await Net.download(URL(string: "https://stub.cartridge.test/nope.zip")!, to: destination) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

@Suite struct IGDBTests {
    @Test func authenticatesThenSearches() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer {
            URLProtocol.unregisterClass(StubProtocol.self)
            StubProtocol.routes = [:]
            StubProtocol.requests = []
        }
        StubProtocol.routes["id.twitch.tv/oauth2/token"] = (200, Data(#"{"access_token":"tok123","expires_in":5000,"token_type":"bearer"}"#.utf8))
        StubProtocol.routes["api.igdb.com/v4/games"] = (200, Data("""
        [{"id": 7334, "name": "Shadow of the Colossus", "first_release_date": 1129593600, "summary": "Ride.",
          "cover": {"id": 1, "image_id": "co1abc"}, "screenshots": [{"id": 2, "image_id": "sc1"}],
          "genres": [{"id": 31, "name": "Adventure"}],
          "involved_companies": [{"id": 9, "company": {"id": 5, "name": "Team Ico"}, "developer": true, "publisher": false},
                                 {"id": 10, "company": {"id": 6, "name": "Sony"}, "developer": false, "publisher": true}]}]
        """.utf8))

        let igdb = IGDB(clientID: "client-1", secret: "secret-1")
        let results = try await igdb.search("Shadow of the Colossus", system: .ps2)
        let game = try #require(results.first)
        #expect(game.year == 2005)
        #expect(game.cover?.image_id == "co1abc")
        #expect(game.companies(developer: true) == "Team Ico")
        #expect(game.companies(developer: false) == "Sony")

        let token = try #require(StubProtocol.requests.first { $0.url?.host == "id.twitch.tv" })
        #expect(token.httpMethod == "POST")
        #expect(token.url?.query == nil, "the secret belongs in the body, not the URL")
        let search = try #require(StubProtocol.requests.first { $0.url?.host == "api.igdb.com" })
        #expect(search.value(forHTTPHeaderField: "Client-ID") == "client-1")
        #expect(search.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")

        // A second search reuses the cached token.
        _ = try await igdb.search("Ico", system: .ps2)
        #expect(StubProtocol.requests.filter { $0.url?.host == "id.twitch.tv" }.count == 1)
    }

    @Test func theSecretTravelsInTheBody() throws {
        let request = IGDB.tokenRequest(clientID: "client 1", secret: "se+cret/1")
        #expect(request.url?.absoluteString == "https://id.twitch.tv/oauth2/token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "client_id=client%201&client_secret=se%2Bcret/1&grant_type=client_credentials")
    }

    @Test func badCredentialsExplainThemselves() async throws {
        URLProtocol.registerClass(StubProtocol.self)
        defer {
            URLProtocol.unregisterClass(StubProtocol.self)
            StubProtocol.routes = [:]
            StubProtocol.requests = []
        }
        StubProtocol.routes["id.twitch.tv/oauth2/token"] = (400, Data(#"{"status":400,"message":"invalid client"}"#.utf8))
        let igdb = IGDB(clientID: "wrong", secret: "wrong")
        await #expect(throws: CartridgeError.self) { _ = try await igdb.search("Halo", system: .xbox) }
    }
}
}

final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}


@Suite struct ArtworkTests {
    @Test func titleKeysSurviveNamingDifferences() {
        #expect(TitleKey.make("The Legend of Zelda: Ocarina of Time (USA)") == TitleKey.make("Legend of Zelda, The - Ocarina of Time"))
        #expect(TitleKey.make("Ratchet & Clank") == TitleKey.make("Ratchet and Clank"))
        #expect(TitleKey.make("Pokémon Snap") == TitleKey.make("Pokemon Snap"))
        #expect(TitleKey.make("Halo 2") != TitleKey.make("Halo 3"))
        #expect(TitleKey.make("(Beta)") == "beta")
    }

    static let fixture = """
    <?xml version="1.0" standalone="yes"?>
    <LaunchBox>
      <Game>
        <Name>Shadow of the Colossus</Name>
        <ReleaseDate>2005-10-18T00:00:00-07:00</ReleaseDate>
        <Overview>A boy &amp; his horse.</Overview>
        <DatabaseID>100</DatabaseID>
        <Platform>Sony Playstation 2</Platform>
        <Genres>Action;Adventure</Genres>
        <Developer>Team Ico</Developer>
        <Publisher>Sony</Publisher>
      </Game>
      <Game>
        <Name>Halo: Combat Evolved</Name>
        <ReleaseYear>2001</ReleaseYear>
        <DatabaseID>200</DatabaseID>
        <Platform>Microsoft Xbox</Platform>
      </Game>
      <Game>
        <Name>Shadow of the Colossus</Name>
        <DatabaseID>300</DatabaseID>
        <Platform>Sony Playstation 4</Platform>
      </Game>
      <Game>
        <Name>Doom</Name>
        <DatabaseID>400</DatabaseID>
        <Platform>Windows</Platform>
      </Game>
      <Platform>
        <Name>Sony Playstation 2</Name>
      </Platform>
      <GameAlternateName>
        <AlternateName>Wander to Kyozou</AlternateName>
        <DatabaseID>100</DatabaseID>
        <Region>Japan</Region>
      </GameAlternateName>
      <GameAlternateName>
        <AlternateName>Doom 1993</AlternateName>
        <DatabaseID>400</DatabaseID>
      </GameAlternateName>
      <GameImage><DatabaseID>100</DatabaseID><FileName>front-eu.jpg</FileName><Type>Box - Front</Type><Region>Europe</Region></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>front-na.jpg</FileName><Type>Box - Front</Type><Region>North America</Region></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>back-eu.jpg</FileName><Type>Box - Back</Type><Region>Europe</Region></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>back-na.jpg</FileName><Type>Box - Back</Type><Region>North America</Region></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>disc-jp.png</FileName><Type>Disc</Type><Region>Japan</Region></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>shot1.png</FileName><Type>Screenshot - Gameplay</Type></GameImage>
      <GameImage><DatabaseID>100</DatabaseID><FileName>flyer.jpg</FileName><Type>Advertisement Flyer - Front</Type></GameImage>
      <GameImage><DatabaseID>400</DatabaseID><FileName>doom.jpg</FileName><Type>Box - Front</Type></GameImage>
    </LaunchBox>
    """

    @Test func buildsASearchableIndex() throws {
        let s = try Scratch()
        let xml = try s.text("Metadata.xml", Self.fixture)
        let file = s.dir.appendingPathComponent("launchbox.sqlite")
        #expect(try LaunchBox.buildIndex(xml: xml, into: file) == 3)
        let db = try LaunchBoxDB(file: file)

        let ps2 = try #require(db.match("Shadow of the Colossus (USA)", system: .ps2))
        #expect(ps2.id == 100)
        #expect(ps2.year == 2005)
        #expect(ps2.overview == "A boy & his horse.")
        #expect(ps2.genres == "Action;Adventure")
        #expect(db.match("Shadow of the Colossus", system: .ps4)?.id == 300)
        #expect(db.match("Wander to Kyozou", system: .ps2)?.id == 100)
        #expect(db.match("Halo - Combat Evolved", system: .xbox)?.year == 2001)
        #expect(db.match("Doom", system: .ps1) == nil)
        #expect(db.search("colossus", system: nil).map(\.id).sorted() == [100, 300])
        #expect(db.search("colossus", system: .ps4).map(\.id) == [300])

        let images = db.images(100)
        #expect(images.count == 6, "the flyer type isn't indexed")
        let picked = LaunchBox.pick(images)
        #expect(picked.art[.front]?.file == "front-na.jpg")
        #expect(picked.art[.back]?.file == "back-na.jpg")
        #expect(picked.art[.disc]?.file == "disc-jp.png")
        #expect(picked.art[.spine] == nil)
        #expect(picked.screenshots.map(\.file) == ["shot1.png"])
        #expect(picked.art[.front]?.url.absoluteString == "https://images.launchbox-app.com/front-na.jpg")
    }

    @Test func igdbQueriesCannotBreakOutOfTheSearchString() {
        #expect(IGDB.searchQuery("Halo \"2\"; fields *", system: .xbox)
                == "search \"Halo 2 fields *\"; fields \(IGDB.fields); where platforms = (11); limit 20;")
        #expect(!IGDB.searchQuery("Ico", system: nil).contains("where"))
        #expect(IGDB.imageURL("abc123", size: "1080p").absoluteString == "https://images.igdb.com/igdb/image/upload/t_1080p/abc123.jpg")
    }
}



/// Downloads LaunchBox's real 100 MB dump and indexes it. Run with
/// CARTRIDGE_HOME=<scratch> CARTRIDGE_LIVE_LAUNCHBOX=1 swift test --filter LaunchBoxLiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_LIVE_LAUNCHBOX"] == "1"))
@MainActor
struct LaunchBoxLiveTests {
    @Test func installsMatchesAndPicksArt() async throws {
        let sources = ArtworkSources()
        let start = Date()
        await sources.installLaunchBox()
        #expect(sources.launchBoxError == nil, "\(sources.launchBoxError ?? "")")
        guard case .ready(let games, _) = sources.launchBox, let db = sources.launchBoxDB else {
            Issue.record("not ready: \(sources.launchBox)")
            return
        }
        print("LaunchBox index: \(games) games in \(Int(Date().timeIntervalSince(start)))s")
        for (title, system) in [("Shadow of the Colossus (USA)", System.ps2), ("Metroid Prime", .gamecube), ("Crash Bandicoot", .ps1),
                                ("Halo - Combat Evolved", .xbox), ("Super Mario Galaxy", .wii), ("Sonic Adventure", .dreamcast)] {
            let match = try #require(db.match(title, system: system), "\(title)")
            let picked = LaunchBox.pick(db.images(match.id))
            print(title, "→", match.name, match.year ?? 0, picked.art.keys.map(\.rawValue).sorted(), "shots:", picked.screenshots.count)
            let front = try #require(picked.art[.front], "\(title) front")
            #expect(await Net.exists(front.url))
            if let disc = picked.art[.disc] { #expect(await Net.exists(disc.url)) }
        }
    }
}

@Suite struct CaseArtTests {
    /// A wrap scan in three solid bands: red back, green spine, blue front.
    func wrap(face: Int, spine: Int, height: Int) -> CGImage {
        ShelfArt.canvas(CGFloat(face * 2 + spine), CGFloat(height)) { ctx, rect in
            for (x, w, color) in [(0, face, NSColor.red), (face, spine, NSColor.green), (face + spine, face, NSColor.blue)] {
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: x, y: 0, width: w, height: height))
            }
        }
    }

    func centreColour(_ image: CGImage) -> NSColor {
        ShelfArt.averageColor(image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1))!)
    }

    @Test func splitsAFullCoverIntoBackSpineAndFront() throws {
        let spec = CaseSpec.of(.ps2)
        let height = 1900, face = Int(1900 * spec.width / spec.height), spine = 140
        let parts = try #require(ShelfArt.splitFullCover(wrap(face: face, spine: spine, height: height), spec: spec))
        #expect(parts.spine.width == spine)
        #expect(parts.back.width == face && parts.front.width == face)
        #expect(centreColour(parts.back).redComponent > 0.9)
        #expect(centreColour(parts.spine).greenComponent > 0.9)
        #expect(centreColour(parts.front).blueComponent > 0.9)
        #expect(ShelfArt.splitFullCover(wrap(face: 10, spine: 5, height: 400), spec: spec) == nil, "taller than wide isn't a wrap")
    }
}

@Suite struct TrailerTests {
    @Test func youTubeIDsFromEveryLinkShape() {
        for link in ["https://www.youtube.com/watch?v=8Mng-r3D20Y", "http://www.youtube.com/watch?v=8Mng-r3D20Y&t=30s",
                     "https://youtu.be/8Mng-r3D20Y", "https://youtu.be/8Mng-r3D20Y?si=abc", "https://m.youtube.com/watch?v=8Mng-r3D20Y",
                     "https://www.youtube.com/embed/8Mng-r3D20Y", "https://www.youtube-nocookie.com/embed/8Mng-r3D20Y?autoplay=1",
                     "https://youtube.com/shorts/8Mng-r3D20Y", " 8Mng-r3D20Y "] {
            #expect(YouTube.videoID(from: link) == "8Mng-r3D20Y", "\(link)")
        }
        for bad in ["http://www.dailymotion.com/video/x2abc", "https://evil.example/watch?v=8Mng-r3D20Y",
                    "https://www.youtube.com/watch?v=short", "8Mng-r3D20Y');alert(1);//", ""] {
            #expect(YouTube.videoID(from: bad) == nil, "\(bad)")
        }
    }

    @Test func pageOnlyEverEmbedsAValidatedID() {
        let html = TrailerWebView.html(videoID: "8Mng-r3D20Y", muted: true)
        #expect(html.contains("videoId: '8Mng-r3D20Y'"))
        #expect(html.contains("e.target.mute();"))
        #expect(!TrailerWebView.html(videoID: "8Mng-r3D20Y", muted: false).contains("mute();"))
    }
}

/// Loads real trailers in a WKWebView. Run with CARTRIDGE_LIVE_TRAILERS=1 swift test --filter TrailerLiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_LIVE_TRAILERS"] == "1"))
@MainActor
struct TrailerLiveTests {
    nonisolated static let ids = ProcessInfo.processInfo.environment["CARTRIDGE_TRAILER_IDS"]?.split(separator: ",").map(String.init)
        ?? ["8Mng-r3D20Y", "o_erwihybUQ", "1Y1_lQ-go2o"]

    @Test(arguments: ids)
    func trailerStartsPlaying(_ id: String) async throws {
        // Offscreen, but a real window: WebKit won't run media in a view that isn't in one.
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 480, height: 270), styleMask: .borderless, backing: .buffered, defer: false)
        let player = TrailerWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
        window.contentView = player
        window.orderFrontRegardless()
        defer { player.stop(); window.orderOut(nil) }

        var events: [TrailerWebView.Event] = []
        player.onEvent = { events.append($0) }
        player.load(videoID: id, muted: true)
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline, !events.contains(.playing), !events.contains(where: { if case .failed = $0 { true } else { false } }) {
            try await Task.sleep(for: .milliseconds(200))
        }
        print("trailer \(id):", events)
        #expect(events.contains(.playing), "\(id): \(events)")
    }
}

/// Searches the real Internet Archive for the demo library's manuals. Run with CARTRIDGE_LIVE_MANUALS=1
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_LIVE_MANUALS"] == "1"))
struct ManualLiveTests {
    @Test func demoGamesFindTheirManuals() async throws {
        let games: [(String, System)] = [
            ("Crash Bandicoot", .ps1), ("Final Fantasy VII", .ps1), ("Shadow of the Colossus", .ps2), ("Ico", .ps2),
            ("Metal Gear Solid 3 - Snake Eater", .ps2), ("Metroid Prime", .gamecube), ("The Legend of Zelda - The Wind Waker", .gamecube),
            ("Super Mario Galaxy", .wii), ("Halo - Combat Evolved", .xbox), ("Sonic Adventure", .dreamcast), ("Jet Set Radio", .dreamcast),
            ("NiGHTS into Dreams", .saturn), ("Daxter", .psp), ("Super Mario 64", .n64), ("Super Metroid", .snes),
            ("Sonic the Hedgehog 2", .genesis), ("Demon's Souls", .ps3), ("Bloodborne", .ps4),
        ]
        for (title, system) in games {
            let found = await Manuals.find(title: title, system: system)
            let pick = found.first.flatMap { $0.score >= Manuals.confidentScore ? $0 : nil }
            print("MANUAL", title, "→", pick.map { "\($0.score) \($0.title) [\($0.source.rawValue)]" } ?? "none",
                  "| next:", found.dropFirst().prefix(3).map { "\($0.score) \($0.title) [\($0.source.rawValue)]" })
        }
    }
}

/// Writes a PDF whose pages are solid colours, each with its number in the middle.
func makeTestPDF(_ url: URL, pages: [(size: CGSize, colors: [NSColor])]) {
    var first = CGRect(origin: .zero, size: pages[0].size)
    let ctx = CGContext(url as CFURL, mediaBox: &first, nil)!
    for (number, page) in pages.enumerated() {
        var media = CGRect(origin: .zero, size: page.size)
        let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
        ctx.beginPDFPage(info)
        let band = page.size.width / CGFloat(page.colors.count)
        for (i, color) in page.colors.enumerated() {
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: CGFloat(i) * band, y: 0, width: band, height: page.size.height))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("\(number + 1)" as NSString).draw(at: CGPoint(x: page.size.width / 2 - 40, y: page.size.height / 2 - 60),
                                          withAttributes: [.font: NSFont.boldSystemFont(ofSize: 120), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

@Suite struct ManualTests {
    @Test func scoresTheRightManualAboveTheNearMisses() {
        func score(_ item: String, language: String? = nil, collections: [String] = [], game: String, _ system: System) -> Int {
            Manuals.score(itemTitle: item, language: language, collections: collections, gameTitle: game, system: system)
        }
        let colossus = score("Shadow of the Colossus (USA)", language: "eng", collections: ["ps2-kirklands-manual-labor", "manuals"], game: "Shadow of the Colossus (USA)", .ps2)
        #expect(colossus >= Manuals.confidentScore)
        #expect(score("The ICO And Shadow Of The Colossus Collection Manual PS3", game: "Shadow of the Colossus", .ps2) < Manuals.confidentScore)
        #expect(score("Metroid Prime Hunters manual (USA)", language: "eng", game: "Metroid Prime", .gamecube) < Manuals.confidentScore)
        #expect(score("Metroid Prime - Nintendo GameCube - Spielanleitung", language: "ger", game: "Metroid Prime", .gamecube) < Manuals.confidentScore)
        #expect(score("Crash Bandicoot 2 Cortex Strikes Back PlayStation Manual", collections: ["playstationmanuals"], game: "Crash Bandicoot", .ps1) < 0)
        #expect(score("Crash Bandicoot PlayStation Manual", collections: ["playstationmanuals"], game: "Crash Bandicoot", .ps1) >= Manuals.confidentScore)
        #expect(score("Sega Saturn Manual: Nights Into Dreams... (1995)(Sega)(US)", game: "NiGHTS into Dreams", .saturn) >= Manuals.confidentScore,
                "a release year isn't a sequel number")
        #expect(score("Sonic The Hedgehog 2 Sega Game Gear Manual", game: "Sonic the Hedgehog 2", .genesis) < Manuals.confidentScore)
        #expect(score("Super Mario 64 Official Players Guide", game: "Super Mario 64", .n64) < 0, "guides aren't manuals")
        #expect(score("Final Fantasy VII (USA) (Disc 1)", collections: ["playstationmanuals"], game: "Final Fantasy VII", .ps1) >= Manuals.confidentScore)
        #expect(score("Gran Turismo 3 A-Spec (USA) (Greatest Hits)", game: "Gran Turismo 3 - A-Spec", .ps2) >= Manuals.confidentScore - 20)
        #expect(score("Halo 2 Manual", game: "Halo - Combat Evolved", .xbox) < 0)
    }

    @Test func matchesSquashedFileNames() {
        #expect(Manuals.score(itemTitle: "Halo-CombatEvolvedusa", language: nil, collections: ["xbox"], gameTitle: "Halo - Combat Evolved", system: .xbox) >= Manuals.confidentScore)
        #expect(Manuals.score(itemTitle: "Halo2usa", language: nil, collections: ["xbox"], gameTitle: "Halo - Combat Evolved", system: .xbox) < 0)
        #expect(Manuals.score(itemTitle: "Halo2guideusa", language: nil, collections: ["xbox"], gameTitle: "Halo 2", system: .xbox) < Manuals.confidentScore)
        // The title a "Game (USA) (v2.00) 2" Finder copy gets must still find the archive's ps2_ manual item.
        let lego = Detect.title(fromFilename: "LEGO Star Wars - The Video Game (USA) (v2.00) 2")
        #expect(Manuals.score(itemTitle: " LEGO Star Wars  The Video Game (USA)", language: "eng", collections: ["ps2-kirklands-manual-labor", "manuals", "consolemanuals"], gameTitle: lego, system: .ps2) >= Manuals.confidentScore)
    }

    @Test func collectionFilesSkipTextCopiesAndOtherGames() {
        let files = ["Crash Bandicoot (USA).pdf", "Crash Bandicoot (USA)_text.pdf", "Crash Bandicoot (USA).PDF", "Crash Bandicoot - Warped (USA).pdf", "readme.txt"]
        let found = Manuals.collectionCandidates(files: files, identifier: "SonyPlaystationManuals", gameTitle: "Crash Bandicoot (USA)", system: .ps1)
            .sorted { $0.score > $1.score }
        #expect(found.first?.title == "Crash Bandicoot (USA)")
        #expect(found.first.map { $0.score >= Manuals.confidentScore } == true)
        #expect(!found.contains { $0.id.contains("_text") })
        #expect(found.filter { $0.title.contains("Warped") }.allSatisfy { $0.score < Manuals.confidentScore })
        #expect(found.first?.page == "https://archive.org/download/SonyPlaystationManuals/Crash%20Bandicoot%20(USA).pdf")
    }

    @Test func parsesMuseumPages() {
        let search = """
        <a href="/fr/game/Legend-of-Zelda-The-The-Wind-Waker/62/2/28807" title="Image in-game du jeu Legend of Zelda, The - The Wind Waker sur Nintendo GameCube"><img></a>
        <a href="/fr/game/ICO-%26-Shadow-of-the-Colossus-Collection-The/121/2/60849" title="Image in-game du jeu ICO &amp; Shadow of the Colossus Collection, The sur Sony Playstation 3">
        """
        let games = Manuals.parseMuseumSearch(search)
        #expect(games == [
            .init(path: "/fr/game/Legend-of-Zelda-The-The-Wind-Waker/62/2/28807", system: 62, title: "Legend of Zelda, The - The Wind Waker"),
            .init(path: "/fr/game/ICO-%26-Shadow-of-the-Colossus-Collection-The/121/2/60849", system: 121, title: "ICO & Shadow of the Colossus Collection, The"),
        ])
        let page = """
        <a href="https://www.musee-des-jeux-video.com/fr/manual/Dreamcast/20134_us-Jet-Grind-Radio.pdf">US</a>
        <a href="https://www.musee-des-jeux-video.com/fr/manual/Dreamcast/20134_us-Jet-Grind-Radio.pdf">again</a>
        <a href="https://www.musee-des-jeux-video.com/fr/manual/Playstation%202/55400_jp-Shadow-of-the-Colossus.pdf">JP</a>
        """
        let manuals = Manuals.parseMuseumManuals(page)
        #expect(manuals.count == 2)
        #expect(manuals[0].region == "us" && manuals[0].title == "Jet Grind Radio")
        #expect(manuals[1].url.absoluteString.hasSuffix("Playstation%202/55400_jp-Shadow-of-the-Colossus.pdf"))
        #expect(Manuals.score(itemTitle: "Legend of Zelda The The Wind Waker (USA)", language: nil, collections: ["gamecube"], gameTitle: "The Legend of Zelda - The Wind Waker", system: .gamecube) >= Manuals.confidentScore)
        #expect(Manuals.score(itemTitle: "Shadow of the Colossus (Japan)", language: nil, collections: ["playstation 2"], gameTitle: "Shadow of the Colossus", system: .ps2) < Manuals.confidentScore)
    }

    @Test func parsesDigitalPressIndexes() {
        let html = #"<a href="18_wheeler.pdf" style="text-decoration: none">18 Wheeler</a> <A HREF="jet_grind_radio.pdf">Jet Grind Radio</A> <a href="../index.html">Back</a>"#
        let entries = Manuals.parseDigitalPress(html)
        #expect(entries.map(\.file) == ["18_wheeler.pdf", "jet_grind_radio.pdf"])
        #expect(entries.map(\.name) == ["18 Wheeler", "Jet Grind Radio"])
    }

    @Test func picksTheOriginalPDFUnlessItIsHuge() throws {
        func metadata(_ files: [(String, String, Int)]) -> Data {
            let list = files.map { #"{"name": "\#($0.0)", "source": "\#($0.1)", "format": "PDF", "size": "\#($0.2)"}"# }
            return Data(#"{"files": [\#(list.joined(separator: ","))]}"#.utf8)
        }
        let normal = try Manuals.pickPDF(metadata([("scan.pdf", "original", 15_000_000), ("scan_text.pdf", "derivative", 3_000_000), ("scan_jp2.zip", "derivative", 8_000_000)]))
        #expect(normal?.name == "scan.pdf")
        let huge = try Manuals.pickPDF(metadata([("scan.pdf", "original", 200_000_000), ("scan_text.pdf", "derivative", 9_000_000)]))
        #expect(huge?.name == "scan_text.pdf")
        #expect(try Manuals.pickPDF(metadata([("scan_jp2.zip", "derivative", 8_000_000)])) == nil)
        #expect(Manuals.downloadURL(identifier: "ps2_ICO_USA", file: "ICO (USA).pdf").absoluteString == "https://archive.org/download/ps2_ICO_USA/ICO%20(USA).pdf")
    }

    @Test func splitsScannedSpreadsIntoPages() {
        let portrait = CGSize(width: 500, height: 700), landscape = CGSize(width: 1000, height: 700)
        let spreads = BookletPages(pageSizes: [portrait, landscape, landscape, portrait])
        #expect(spreads.pages == [.init(pdfIndex: 0, half: .whole), .init(pdfIndex: 1, half: .left), .init(pdfIndex: 1, half: .right),
                                  .init(pdfIndex: 2, half: .left), .init(pdfIndex: 2, half: .right), .init(pdfIndex: 3, half: .whole)])
        #expect(abs(spreads.aspect - 500.0 / 700) < 0.001)

        let wrap = BookletPages(pageSizes: [landscape, portrait, portrait])
        #expect(wrap.pages == [.init(pdfIndex: 0, half: .right), .init(pdfIndex: 1, half: .whole),
                               .init(pdfIndex: 2, half: .whole), .init(pdfIndex: 0, half: .left)], "front cover first, back cover last")
    }

    @Test func rendersPagesAndHalves() throws {
        let s = try Scratch()
        let url = s.dir.appendingPathComponent("manual.pdf")
        // Small in PDF units, like many scans: rendering must scale pages up, not leave them in a corner.
        makeTestPDF(url, pages: [(CGSize(width: 200, height: 140), [.red, .blue]), (CGSize(width: 100, height: 140), [.green])])
        let sizes = try #require(BookletPages.pageSizes(of: url))
        #expect(sizes.count == 2)
        let pages = BookletPages(pageSizes: sizes)
        func corner(_ image: CGImage) -> NSColor { ShelfArt.averageColor(image.cropping(to: CGRect(x: 4, y: 4, width: 20, height: 20))!) }
        let front = try #require(BookletPages.render(pages.pages[0], of: url, height: 400))
        #expect(front.height == 400)
        #expect(corner(front).blueComponent > 0.8, "right half of the wrap is the front cover")
        let back = try #require(BookletPages.render(pages.pages.last!, of: url, height: 400))
        #expect(corner(back).redComponent > 0.8)
        let farCorner = ShelfArt.averageColor(front.cropping(to: CGRect(x: front.width - 24, y: front.height - 24, width: 20, height: 20))!)
        #expect(farCorner.blueComponent > 0.8, "the page fills the whole image")
        #expect(BookletPages.pageSizes(of: s.dir.appendingPathComponent("missing.pdf")) == nil)
    }

    @MainActor @Test func turningShowsTheRightPages() {
        let book = BookletNode(size: CGSize(width: 0.12, height: 0.17), cover: nil)
        let url = URL(fileURLWithPath: "/nonexistent.pdf")
        book.load(pdf: url, pages: BookletPages(pageSizes: Array(repeating: CGSize(width: 5, height: 7), count: 5)))
        #expect(book.leafCount == 3)
        #expect(book.visiblePages == (nil, 1))
        #expect(book.turn(forward: true, duration: 0))
        #expect(book.visiblePages == (2, 3))
        book.turn(forward: true, duration: 0)
        #expect(book.visiblePages == (4, 5))
        book.turn(forward: true, duration: 0)
        #expect(book.visiblePages.left == nil && book.visiblePages.right == nil, "page 6 doesn't exist, so the back is blank")
        #expect(!book.turn(forward: true, duration: 0))
        book.closeAll(duration: 0)
        #expect(book.turned == 0)
        #expect(!book.turn(forward: false, duration: 0))
    }
}

@Suite struct BiosTests {
    /// A 512 KB image carrying Sony's copyright and a version line, like a real PS1 BIOS.
    func ps1(version: String? = "System ROM Version 4.5 05/25/00 A", copyright: Bool = true, size: Int = 512 << 10) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        func put(_ text: String, at offset: Int) {
            bytes.replaceSubrange(offset..<(offset + text.utf8.count), with: Array(text.utf8))
        }
        if copyright { put("Sony Computer Entertainment Inc.", at: 0x100) }
        if let version { put(version, at: 0x200) }
        return Data(bytes)
    }

    @Test func readsAPlayStationBios() throws {
        let summary = try BiosCheck.ps1.identify(ps1())
        #expect(summary.contains("System ROM 4.5"))
        #expect(summary.contains("05/25/00"))
        #expect(summary.contains("America"))
        #expect(try BiosCheck.ps1.identify(ps1(version: "System ROM Version 2.1 07/17/95 E")).contains("Europe"))
        // No version string is odd but not disqualifying; the copyright is what makes it a BIOS.
        #expect(try BiosCheck.ps1.identify(ps1(version: nil)).contains("PlayStation BIOS"))
    }

    @Test func refusesThingsThatArentAPlayStationBios() {
        #expect(throws: CartridgeError.self) { try BiosCheck.ps1.identify(ps1(size: 256 << 10)) }
        #expect(throws: CartridgeError.self) { try BiosCheck.ps1.identify(ps1(copyright: false)) }
    }

    /// A ROM image laid out like a retail dump: boot code, then the directory (RESET, ROMDIR, ROMVER) at 0x2740,
    /// with ROMVER's text where the offsets say.
    func ps2(romver: String = "0160EC20010704", size: Int = 4 << 20, table: Int = 0x2740) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        // RESET's file is everything before the directory, so the directory's own entry lands right on it.
        let entries: [(String, Int)] = [("RESET", table), ("ROMDIR", 48), ("ROMVER", 16)]
        var offset = 0
        for (index, (name, length)) in entries.enumerated() {
            let entry = table + index * 16
            bytes.replaceSubrange(entry..<(entry + name.utf8.count), with: Array(name.utf8))
            for byte in 0..<4 { bytes[entry + 12 + byte] = UInt8((length >> (8 * byte)) & 0xff) }
            if name == "ROMVER" {
                bytes.replaceSubrange(offset..<(offset + romver.utf8.count), with: Array(romver.utf8))
            }
            offset += (length + 15) & ~15
        }
        return Data(bytes)
    }

    @Test func readsAPS2BiosVersionOutOfItsRomDirectory() throws {
        let summary = try BiosCheck.ps2.identify(ps2())
        #expect(summary == "PS2 BIOS v1.60 · Europe retail · 2001-07-04")
        #expect(try BiosCheck.ps2.identify(ps2(romver: "0250JC20060213")).contains("Japan retail"))
        #expect(try BiosCheck.ps2.identify(ps2(romver: "0110AD19991216")).contains("USA devkit"))
    }

    @Test func refusesThingsThatArentAPS2Bios() {
        // Right size, no ROM directory.
        #expect(throws: CartridgeError.self) { try BiosCheck.ps2.identify(Data(count: 4 << 20)) }
        // A real directory, but the file is a PS1 BIOS's size.
        #expect(throws: CartridgeError.self) { try BiosCheck.ps2.identify(ps2(size: 512 << 10)) }
    }

    @Test func checksSizesAndMagicNumbers() throws {
        let mcpx = BiosCheck.fixedSize([512], describing: "MCPX boot ROM")
        #expect(try mcpx.identify(Data(count: 512)).contains("MCPX"))
        #expect(throws: CartridgeError.self) { try mcpx.identify(Data(count: 511)) }

        var pup = Data("SCEUF".utf8)
        pup.append(Data(count: 250 << 20))
        #expect(try BiosCheck.pup.identify(pup).contains("PS3 system software"))
        // A complete PUP is hundreds of megabytes; a small one is a failed download.
        #expect(throws: CartridgeError.self) { try BiosCheck.pup.identify(Data("SCEUF".utf8) + Data(count: 4096)) }
        #expect(throws: CartridgeError.self) { try BiosCheck.pup.identify(Data(count: 250 << 20)) }
    }

    @Test func saturnBiosNeedsSegasName() throws {
        var bytes = [UInt8](repeating: 0, count: 512 << 10)
        bytes.replaceSubrange(0..<4, with: Array("SEGA".utf8))
        #expect(try BiosCheck.saturn.identify(Data(bytes)).contains("Saturn BIOS"))
        #expect(throws: CartridgeError.self) { try BiosCheck.saturn.identify(Data(count: 512 << 10)) }
    }

    @Test func fingerprintsAreStable() {
        #expect(Bios.sha256(Data("cartridge".utf8)).count == 64)
        #expect(Bios.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}

@MainActor @Suite struct SetupTests {
    func setup() -> (AppSetup, UserDefaults) {
        let suite = "cartridge-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSetup(defaults: defaults), defaults)
    }

    @Test func remembersTheConsolesTheyPicked() {
        let (first, defaults) = setup()
        #expect(first.isShowing, "a first run opens setup by itself")
        first.consoles = [.ps2, .snes]
        first.finish()
        #expect(!first.isShowing)

        let again = AppSetup(defaults: defaults)
        #expect(!again.isShowing, "setup doesn't reappear once it is done")
        #expect(again.consoles == [.ps2, .snes])
        #expect(again.chosen == [.snes, .ps2], "listed in the app's own order, not the order they were picked")
    }

    @Test func showsOnlyWhatTheChosenConsolesNeed() {
        let (setup, _) = setup()
        setup.consoles = [.ps2, .snes, .gamecube]
        #expect(setup.emulators == [.retroarch, .pcsx2, .dolphin])
        #expect(setup.biosNeeded.map(\.id) == ["ps2"])
        #expect(setup.runs(.ps2) && !setup.runs(.ps1))

        // Nobody having chosen yet means everything is on show, rather than nothing.
        let (fresh, _) = self.setup()
        #expect(fresh.chosen == System.allCases)
        #expect(fresh.emulators == EmulatorID.allCases)
        #expect(fresh.runs(.ps1))
    }

    @Test func refusesAGamesFolderItCantUse() {
        #expect(AppSetup.rejection(for: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) != nil)
        #expect(AppSetup.rejection(for: FileManager.default.homeDirectoryForCurrentUser) != nil)
        #expect(AppSetup.rejection(for: FileManager.default.temporaryDirectory) == nil)
    }

    @Test func gamesFolderFallsBackToCartridgesOwn() {
        // Tests run under CARTRIDGE_HOME, so Paths ignores any folder chosen in the real app.
        #expect(Paths.games == Paths.defaultGames)
        #expect(Paths.gamesRoots == [Paths.defaultGames])
    }
}

@Suite struct ImprovementTests {
    @Test func seesABiosAlreadyInAnEmulatorsFolder() throws {
        let s = try Scratch()
        let ps1 = try #require(BiosRequirement.all.first { $0.id == "ps1" })
        #expect(!ps1.isPresent(in: s.dir), "an empty folder has no BIOS")

        // Kept under its own name, so any file the check accepts counts - and a junk file doesn't.
        _ = try s.file("notes.bin", size: 512 << 10)
        #expect(!ps1.isPresent(in: s.dir))
        var bios = [UInt8](repeating: 0, count: 512 << 10)
        bios.replaceSubrange(0x100..<(0x100 + 32), with: Array("Sony Computer Entertainment Inc.".utf8))
        try Data(bios).write(to: s.dir.appendingPathComponent("SCPH1001.BIN"))
        #expect(ps1.isPresent(in: s.dir))

        // Saved under a fixed name, so that exact file is what counts.
        let saturn = try #require(BiosRequirement.all.first { $0.id == "saturn.us" })
        #expect(!saturn.isPresent(in: s.dir))
        _ = try s.file("mpr-17933.bin", size: 512 << 10)
        #expect(saturn.isPresent(in: s.dir))
    }

    @Test func checksTheFolderOfTheEmulatorThatRunsTheGame() {
        // PS1 BIOS files go to DuckStation and RetroArch, but DuckStation is what plays PS1 games.
        #expect(BiosTarget.duckStation.emulator == System.ps1.emulator)
        #expect(BiosTarget.pcsx2.emulator == System.ps2.emulator)
        // Where Cartridge can't see the emulator's own setup, it doesn't claim anything is missing.
        #expect(BiosRequirement.missing(for: .ps3) == nil)
        #expect(BiosRequirement.missing(for: .xbox) == nil)
        #expect(BiosRequirement.missing(for: .snes) == nil)
    }

    @Test func namesADriveThatIsntPluggedIn() {
        #expect(Paths.disconnectedVolume(of: URL(fileURLWithPath: "/Volumes/NoSuchDrive-\(UUID().uuidString)/Games/ps2/Okami.iso"))?.hasPrefix("NoSuchDrive-") == true)
        #expect(Paths.disconnectedVolume(of: URL(fileURLWithPath: NSHomeDirectory())) == nil)
        if let mounted = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes").first {
            #expect(Paths.disconnectedVolume(of: URL(fileURLWithPath: "/Volumes/\(mounted)/x")) == nil)
        }
    }
}

@Suite struct ScanTests {
    @Test func findsEachGameOnceAndLeavesTheRest() throws {
        let s = try Scratch()
        _ = try s.file("Shenmue/track01.bin")
        _ = try s.text("Shenmue/Shenmue.gdi", "1\n1 0 4 2352 track01.bin 0\n")
        _ = try s.file("Metroid Fusion.gba")
        _ = try s.file("Demon's Souls/PS3_GAME/USRDIR/EBOOT.BIN")
        _ = try s.text("readme.txt", "notes")
        _ = try s.file("mystery.xyz")

        let first = Library.discover(in: s.dir, known: [])
        #expect(Set(first.games.map { $0.0.lastPathComponent }) == ["Shenmue.gdi", "Metroid Fusion.gba", "Demon's Souls"],
                "the track file belongs to its .gdi, and the PS3 folder is one game rather than the files inside it")
        #expect(Set(first.games.map(\.1)) == [.dreamcast, .gba, .ps3])
        #expect(first.unrecognised.map(\.lastPathComponent) == ["mystery.xyz"], "notes are never games, unknown files are reported")

        let again = Library.discover(in: s.dir, known: Set(first.games.map { $0.0.path }))
        #expect(again.games.isEmpty, "games already in the library, and their tracks, aren't found twice")
    }
}

@Suite struct EmulatorDataTests {
    @Test func iniEditsTouchOnlyTheirKey() {
        let original = """
        [Main]
        SettingsVersion = 3

        [Pad1]
        Up = Keyboard/Up
        Up = SDL-0/DPadUp
        Type = AnalogController

        [Cheevos]
        Enabled = false
        """
        var text = IniFile.set("Enabled", "true", section: "Cheevos", in: original)
        text = IniFile.set("Username", "player", section: "Cheevos", in: text)
        #expect(IniFile.value("Enabled", section: "Cheevos", in: text) == "true")
        #expect(IniFile.value("Username", section: "Cheevos", in: text) == "player")
        #expect(text.contains("Up = Keyboard/Up\nUp = SDL-0/DPadUp"), "repeated keys elsewhere survive")
        #expect(text.hasPrefix("[Main]\nSettingsVersion = 3\n\n[Pad1]"))

        // A key that repeats collapses to the one new value; a missing section is added at the end.
        let pad = IniFile.set("Up", "SDL-0/DPadUp", section: "Pad1", in: original)
        #expect(pad.components(separatedBy: "Up = ").count == 2)
        let added = IniFile.set("Token", "abc", section: "Achievements", in: original)
        #expect(added.hasSuffix("[Achievements]\nToken = abc\n"))
        #expect(IniFile.value("Token", section: "Cheevos", in: added) == nil, "a key isn't found in the wrong section")
    }

    @Test func retroArchCfgEditsAndFolders() {
        let cfg = "video_fullscreen = \"false\"\nsystem_directory = \"~/Emu/bios\"\nsavefile_directory = \"default\"\n"
        #expect(CfgFile.value("system_directory", in: cfg) == "~/Emu/bios")
        let updated = CfgFile.set("cheevos_enable", "true", in: CfgFile.set("video_fullscreen", "true", in: cfg))
        #expect(updated == "video_fullscreen = \"true\"\nsystem_directory = \"~/Emu/bios\"\nsavefile_directory = \"default\"\ncheevos_enable = \"true\"\n")

        #expect(EmulatorData.retroArchDirectory("system_directory", default: "system", config: cfg).path == NSHomeDirectory() + "/Emu/bios")
        // "default" and a missing key both mean ~/Documents/RetroArch, where RetroArch keeps them on macOS now.
        #expect(EmulatorData.retroArchDirectory("savefile_directory", default: "saves", config: cfg).path == NSHomeDirectory() + "/Documents/RetroArch/saves")
        #expect(EmulatorData.retroArchDirectory("savestate_directory", default: "states", config: cfg).path == NSHomeDirectory() + "/Documents/RetroArch/states")
    }

    @Test func expandsWildcardsToWhatExists() throws {
        let s = try Scratch()
        _ = try s.file("Wii/title/00010000/53414e45/data/banner.bin")
        _ = try s.file("Wii/title/00010000/524d4745/data/save.bin")
        _ = try s.file("Wii/title/00010000/474c5445/content/title.tmd")   // installed game data, not a save
        _ = try s.file("GC/USA/Card A/save.gci")
        #expect(EmulatorData.expand("Wii/title/00010000/*/data", in: s.dir) == ["Wii/title/00010000/524d4745/data", "Wii/title/00010000/53414e45/data"])
        #expect(EmulatorData.expand("GC", in: s.dir) == ["GC"])
        #expect(EmulatorData.expand("StateSaves", in: s.dir).isEmpty)
        #expect(EmulatorData.expand("", in: s.dir) == [""])
    }

    @Test func editingKeepsTheOriginalAndSkipsMissingFiles() throws {
        let s = try Scratch()
        let file = try s.text("settings.ini", "[Cheevos]\nEnabled = false\n")
        #expect(try EmulatorData.edit(file) { IniFile.set("Enabled", "true", section: "Cheevos", in: $0) })
        #expect(try String(contentsOf: file, encoding: .utf8) == "[Cheevos]\nEnabled = true\n")
        try EmulatorData.edit(file) { IniFile.set("Username", "x", section: "Cheevos", in: $0) }
        let backup = file.appendingPathExtension("cartridge-backup")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "[Cheevos]\nEnabled = false\n", "the backup is the file before Cartridge ever touched it")
        #expect(try !EmulatorData.edit(s.dir.appendingPathComponent("missing.ini")) { $0 + "x" }, "an emulator that hasn't made its settings yet is left alone")
    }
}

@Suite struct SaveBackupTests {
    @Test func backsUpOnlySavesAndPutsThemBack() throws {
        let emulator = try Scratch()
        _ = try emulator.text("memcards/Mcd001.mcd", "slot one")
        _ = try emulator.text("Wii/title/00010000/53414e45/data/save.bin", "zelda save")
        _ = try emulator.file("Wii/title/00010000/53414e45/content/00000000.app", size: 4096)   // installed game data
        let sets = [EmulatorData.SaveSet(name: "Memory cards", base: emulator.dir, patterns: ["memcards"]),
                    EmulatorData.SaveSet(name: "Wii saves", base: emulator.dir, patterns: ["Wii/title/00010000/*/data"])]

        let store = try Scratch()
        let backup = store.dir.appendingPathComponent(SaveBackups.stamp(Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(try SaveBackups.copy(sets, into: backup) == 2)
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Memory cards/memcards/Mcd001.mcd").path))
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Wii saves/Wii/title/00010000/53414e45/data/save.bin").path))
        #expect(!FileManager.default.fileExists(atPath: backup.appendingPathComponent("Wii saves/Wii/title/00010000/53414e45/content").path),
                "installed game data stays out of backups")
        #expect(SaveBackups.date(of: backup) == Date(timeIntervalSince1970: 1_800_000_000))

        // Overwrite a save, restore, and the backed-up version is back.
        try "ruined".write(to: emulator.dir.appendingPathComponent("memcards/Mcd001.mcd"), atomically: true, encoding: .utf8)
        var setAside: [String] = []
        // The app moves replaced saves to the Trash; a test mustn't fill the real one.
        try SaveBackups.restore(sets, from: backup) { url in
            setAside.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }
        #expect(setAside == ["memcards", "data"], "what was there is set aside before the backup goes back")
        #expect(try String(contentsOf: emulator.dir.appendingPathComponent("memcards/Mcd001.mcd"), encoding: .utf8) == "slot one")
        #expect(try String(contentsOf: emulator.dir.appendingPathComponent("Wii/title/00010000/53414e45/data/save.bin"), encoding: .utf8) == "zelda save")
        #expect(FileManager.default.fileExists(atPath: emulator.dir.appendingPathComponent("Wii/title/00010000/53414e45/content/00000000.app").path),
                "restoring saves doesn't touch the game data next to them")

        let summary = SaveBackups.summary(sets)
        #expect(summary.files == 2)
        #expect(summary.latest != nil)
    }

    @Test func keepsTheNewestBackups() throws {
        let store = try Scratch()
        for day in 1...12 {
            let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
            try FileManager.default.createDirectory(at: store.dir.appendingPathComponent(SaveBackups.stamp(date)), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: store.dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try SaveBackups.prune(store.dir, keeping: 10)
        let left = SaveBackups.backups(in: store.dir)
        #expect(left.count == 10)
        #expect(left.first.flatMap(SaveBackups.date(of:)) == Date(timeIntervalSince1970: 1_800_000_000 + 12 * 86_400), "newest first")
        #expect(FileManager.default.fileExists(atPath: store.dir.appendingPathComponent("notes").path), "only dated backups are pruned")
    }

    @Test func nothingToSaveMeansNoBackup() throws {
        let emulator = try Scratch()
        let store = try Scratch()
        let target = store.dir.appendingPathComponent("empty")
        #expect(try SaveBackups.copy([EmulatorData.SaveSet(name: "Saves", base: emulator.dir, patterns: ["memcards"])], into: target) == 0)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
}

@Suite struct DumpCheckTests {
    /// A list with one cartridge game and one two-track disc, in the format libretro publishes.
    func catalogue(cart: Data, track1: Data, track2: Data) -> DumpCheck.Catalogue {
        let dat = """
        clrmamepro (
        \tname "Test - System"
        \tversion "2026.09.01"
        )

        game (
        \tname "Super Game (USA)"
        \tregion "USA"
        \trom ( name "Super Game (USA).sfc" size \(cart.count) crc 00000000 md5 00 sha1 \(sha1(cart)) )
        )

        game (
        \tname "Disc \\"Quest\\" (Europe)"
        \trom ( name "Disc Quest (Europe) (Track 1).bin" size \(track1.count) crc 00000000 sha1 \(sha1(track1)) serial "SLES-00001" )
        \trom ( name "Disc Quest (Europe) (Track 2).bin" size \(track2.count) crc 00000000 sha1 \(sha1(track2)) )
        )
        """
        return DumpCheck.Catalogue(DumpCheck.parse(dat))
    }

    func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    @Test func parsesGamesAndTheirFiles() {
        let list = DumpCheck.parse("""
        clrmamepro (
        \tname "Nintendo - Game Boy"
        )
        game (
        \tname "Tetris (World)"
        \trom ( name "Tetris (World).gb" size 32768 crc 46DF91AD md5 982ED5D2B12A0377EB14BCDC4123744E sha1 74591CC9501AF93873F9A5D3EB12DA12C0723BBC )
        )
        """)
        #expect(list == [DumpCheck.Entry(game: "Tetris (World)", file: "Tetris (World).gb", size: 32768, sha1: "74591cc9501af93873f9a5d3eb12da12c0723bbc")])
    }

    @Test func tellsGoodBadAndUnknownApart() throws {
        let s = try Scratch()
        let cart = Data((0..<4096).map { UInt8($0 % 251) })
        let catalogue = catalogue(cart: cart, track1: Data(repeating: 1, count: 2352), track2: Data(repeating: 2, count: 2352))

        let good = s.dir.appendingPathComponent("Super Game (USA).sfc")
        try cart.write(to: good)
        #expect(try DumpCheck.verify(good, system: .snes, against: catalogue) == .verified("Super Game (USA)"))

        // The same file behind a 512-byte copier header still counts.
        let headered = s.dir.appendingPathComponent("headered.smc")
        try (Data(count: 512) + cart).write(to: headered)
        #expect(try DumpCheck.verify(headered, system: .snes, against: catalogue) == .verified("Super Game (USA)"))

        let bad = s.dir.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        var damaged = cart
        damaged[100] ^= 0xFF
        try damaged.write(to: bad.appendingPathComponent("Super Game (USA).sfc"))
        #expect(try DumpCheck.verify(bad.appendingPathComponent("Super Game (USA).sfc"), system: .snes, against: catalogue) == .bad("Super Game (USA)"))

        let homebrew = s.dir.appendingPathComponent("My Homebrew.sfc")
        try Data(repeating: 7, count: 1024).write(to: homebrew)
        #expect(try DumpCheck.verify(homebrew, system: .snes, against: catalogue) == .unknown)

        let chd = try s.file("Game.chd")
        if case .unsupported = try DumpCheck.verify(chd, system: .ps1, against: catalogue) {} else { Issue.record("compressed images can't be compared") }
    }

    @Test func checksEveryTrackOfADisc() throws {
        let s = try Scratch()
        let one = Data(repeating: 1, count: 2352), two = Data(repeating: 2, count: 2352)
        let catalogue = catalogue(cart: Data([0]), track1: one, track2: two)
        try one.write(to: s.dir.appendingPathComponent("Disc Quest (Europe) (Track 1).bin"))
        try two.write(to: s.dir.appendingPathComponent("Disc Quest (Europe) (Track 2).bin"))
        let cue = try s.text("Disc Quest (Europe).cue", """
        FILE "Disc Quest (Europe) (Track 1).bin" BINARY
          TRACK 01 MODE2/2352
        FILE "Disc Quest (Europe) (Track 2).bin" BINARY
          TRACK 02 AUDIO
        """)
        #expect(try DumpCheck.verify(cue, system: .ps1, against: catalogue) == .verified("Disc \"Quest\" (Europe)"))

        // One damaged track is enough to call the disc bad.
        try Data(repeating: 9, count: 2352).write(to: s.dir.appendingPathComponent("Disc Quest (Europe) (Track 2).bin"))
        #expect(try DumpCheck.verify(cue, system: .ps1, against: catalogue) == .bad("Disc \"Quest\" (Europe)"))
    }

    @Test func mapsConsolesToTheRightList() {
        #expect(DumpCheck.list(for: .ps2)?.folder == "redump")
        #expect(DumpCheck.list(for: .snes)?.folder == "no-intro")
        #expect(DumpCheck.list(for: .snes)?.name == "Nintendo - Super Nintendo Entertainment System")
        #expect(DumpCheck.list(for: .n3ds) == nil)
        #expect(DumpCheck.remoteURL(for: .atari2600)?.absoluteString == "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/no-intro/Atari%20-%202600.dat")
    }

    /// Downloads one real list and reads it. CARTRIDGE_LIVE=1 swift test --filter DumpCheckTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_LIVE"] == "1"))
    func readsARealList() async throws {
        let text = String(decoding: try await Net.data(try #require(DumpCheck.remoteURL(for: .atari2600))), as: UTF8.self)
        let entries = DumpCheck.parse(text)
        #expect(entries.count > 500)
        #expect(entries.allSatisfy { $0.sha1.count == 40 && $0.size > 0 && !$0.game.isEmpty })
        #expect(entries.contains { $0.game.hasPrefix("Pitfall!") })
    }
}

@Suite struct AppUpdateTests {
    @Test func comparesVersionsNumerically() {
        #expect(AppUpdate.isNewer("1.10.0", than: "1.9.3"))
        #expect(AppUpdate.isNewer("1.1.1", than: "1.1"))
        #expect(AppUpdate.isNewer("2.0", than: "1.99.99"))
        #expect(!AppUpdate.isNewer("1.1.0", than: "1.1.0"))
        #expect(!AppUpdate.isNewer("1.0.9", than: "1.1.0"))
        #expect(!AppUpdate.isNewer("1.1", than: "1.1.0"))
    }

    @Test func readsTheLatestRelease() throws {
        let json = Data(#"{"tag_name":"v1.2.0","assets":[]}"#.utf8)
        let found = try AppUpdate.newer(than: "1.1.0", in: json)
        #expect(found?.version == "1.2.0")
        #expect(found?.page.absoluteString == "https://github.com/nicholaslegit-sys/cartridge/releases/tag/v1.2.0")
        #expect(try AppUpdate.newer(than: "1.2.0", in: json) == nil)
    }
}

@Suite struct AchievementsTests {
    @Test func encryptsTheTokenExactlyAsDuckStationDoes() {
        // Reference values computed separately with Python's hashlib and `openssl enc -aes-128-cbc -nopad`,
        // following DuckStation's GetLoginEncryptionKey and EncryptLoginToken.
        let machine = "0123456789abcdef0123456789abcdef"
        #expect(Achievements.duckStationToken("AbCdEfGhIjKlMnOp", user: "Player1", machineKey: machine) == "hffK9oQn/aJuwElQ1gcSFw==")
        #expect(Achievements.duckStationToken("short", user: "Player1", machineKey: machine) == "v+SejdeWqHpZ459kH3DegA==")
        #expect(Achievements.duckStationToken("", user: "Player1", machineKey: machine) == "")
    }

    @Test func machineKeyIsTheHardwareUUIDInLowercaseHex() {
        let key = Achievements.machineKey()
        #expect(key.count == 32)
        #expect(key.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(key == Achievements.machineKey(), "the same every time, or DuckStation couldn't decrypt what it saved")
    }

    @Test func readsTheLoginResponse() throws {
        let ok = try Achievements.login(from: Data(#"{"Success":true,"User":"Player1","Token":"AbCdEfGhIjKlMnOp","Score":120}"#.utf8))
        #expect(ok.user == "Player1")
        #expect(ok.token == "AbCdEfGhIjKlMnOp")
        #expect(throws: Achievements.LoginFailed.self) {
            try Achievements.login(from: Data(#"{"Success":false,"Error":"Invalid User/Password combination. Please try again","Code":"invalid_credentials"}"#.utf8))
        }
        do {
            _ = try Achievements.login(from: Data(#"{"Success":false,"Error":"Invalid User/Password combination."}"#.utf8))
        } catch {
            #expect(error.localizedDescription == "Invalid User/Password combination.", "RetroAchievements' own wording reaches the player")
        }
    }

    @Test func sendsTheSameRequestAsTheEmulators() throws {
        let request = Achievements.loginRequest(user: "Player One", password: "a+b&c=d")
        #expect(request.url?.absoluteString == "https://retroachievements.org/dorequest.php")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self) == "r=login2&u=Player%20One&p=a%2Bb%26c%3Dd",
                "a + in a password must not arrive as a space")
    }

    @Test func writesEachEmulatorsOwnSettings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let machine = "0123456789abcdef0123456789abcdef"

        let retroArch = Achievements.signIn(.retroarch, text: "video_fullscreen = \"true\"\n", user: "Player1", token: "tok", now: now, machineKey: machine)
        #expect(CfgFile.value("cheevos_enable", in: retroArch) == "true")
        #expect(CfgFile.value("cheevos_token", in: retroArch) == "tok")
        #expect(CfgFile.value("video_fullscreen", in: retroArch) == "true")

        let duck = Achievements.signIn(.duckstation, text: "[Main]\nSettingsVersion = 3\n", user: "Player1", token: "AbCdEfGhIjKlMnOp", now: now, machineKey: machine)
        #expect(IniFile.value("Token", section: "Cheevos", in: duck) == "hffK9oQn/aJuwElQ1gcSFw==", "DuckStation gets the encrypted token, never the plain one")
        #expect(IniFile.value("LoginTimestamp", section: "Cheevos", in: duck) == "1800000000")
        #expect(IniFile.value("SettingsVersion", section: "Main", in: duck) == "3")

        let pcsx2 = Achievements.signIn(.pcsx2, text: "[UI]\nSetupWizardIncomplete = false\n", user: "Player1", token: "tok", now: now, machineKey: machine)
        #expect(IniFile.value("Token", section: "Achievements", in: pcsx2) == "tok", "PCSX2 moves it to secrets.ini itself")
        #expect(IniFile.value("Enabled", section: "Achievements", in: pcsx2) == "true")
        #expect(Achievements.signedIn(.pcsx2, in: pcsx2) == "Player1")
    }

    @Test func signingOutOnlyRemovesItsOwnSignIn() {
        let mine = "[Cheevos]\nUsername = Player1\nToken = abc\n"
        let cleared = Achievements.remove(user: "player1", from: mine, emulator: .duckstation)
        #expect(IniFile.value("Username", section: "Cheevos", in: cleared) == "")
        #expect(IniFile.value("Token", section: "Cheevos", in: cleared) == "")

        let theirs = "[Cheevos]\nUsername = SomeoneElse\nToken = xyz\n"
        #expect(Achievements.remove(user: "Player1", from: theirs, emulator: .duckstation) == theirs, "an account chosen in the emulator stays")
    }
}

@Suite struct AdvancedModeTests {
    @Test func gameOverridesWinAndUnsetFollowsTheEmulator() {
        let emulator = DisplayTweaks(resolution: .hd1080, widescreen: true, fullscreen: true)
        let game = DisplayTweaks(resolution: .uhd4k, fullscreen: false)
        #expect(emulator.overlaid(by: game) == DisplayTweaks(resolution: .uhd4k, widescreen: true, fullscreen: false))
        #expect(emulator.overlaid(by: nil) == emulator)
    }

    @Test func pcsx2KeysUseItsOwnSpelling() {
        let writes = Advanced.writes(DisplayTweaks(resolution: .hd1080, widescreen: true, aspect: .wide, fullscreen: true), for: .pcsx2)
        let values = Dictionary(uniqueKeysWithValues: writes.map { ("\($0.0.section!)/\($0.0.key)", $0.1) })
        #expect(values == ["EmuCore/GS/upscale_multiplier": "3", "EmuCore/EnableWideScreenPatches": "true",
                           "EmuCore/GS/AspectRatio": "16:9", "UI/StartFullscreen": "true"])
        #expect(Advanced.writes(DisplayTweaks(), for: .pcsx2).isEmpty)
        #expect(Advanced.writes(DisplayTweaks(resolution: .hd1080), for: .xemu).isEmpty)
    }

    @Test func appliesThenPutsTheOriginalsBack() throws {
        let s = try Scratch()
        let original = "[UI]\nStartFullscreen = false\n\n[EmuCore/GS]\nupscale_multiplier = 1\n"
        let ini = try s.text("PCSX2.ini", original)
        let cfg = try s.text("retroarch.cfg", "video_fullscreen = \"false\"\n")
        let writes: [(ConfigKey, String)] = [
            (ConfigKey(file: ini, section: "UI", key: "StartFullscreen"), "true"),
            (ConfigKey(file: ini, section: "EmuCore/GS", key: "upscale_multiplier"), "4"),
            // Not in the file yet, like most of Dolphin's: restoring removes it again.
            (ConfigKey(file: ini, section: "EmuCore", key: "EnableWideScreenPatches"), "true"),
            (ConfigKey(file: cfg, section: nil, key: "video_fullscreen"), "true"),
        ]
        let originals = try Advanced.apply(writes)
        let applied = try String(contentsOf: ini, encoding: .utf8)
        #expect(IniFile.value("upscale_multiplier", section: "EmuCore/GS", in: applied) == "4")
        #expect(IniFile.value("EnableWideScreenPatches", section: "EmuCore", in: applied) == "true")
        #expect(CfgFile.value("video_fullscreen", in: try String(contentsOf: cfg, encoding: .utf8)) == "true")

        Advanced.restore(originals)
        let restored = try String(contentsOf: ini, encoding: .utf8)
        #expect(IniFile.value("StartFullscreen", section: "UI", in: restored) == "false")
        #expect(IniFile.value("upscale_multiplier", section: "EmuCore/GS", in: restored) == "1")
        #expect(IniFile.value("EnableWideScreenPatches", section: "EmuCore", in: restored) == nil)
        #expect(CfgFile.value("video_fullscreen", in: try String(contentsOf: cfg, encoding: .utf8)) == "false")

        // A file the emulator hasn't made yet is left for it to create.
        let missing = s.dir.appendingPathComponent("GFX.ini")
        #expect(try Advanced.apply([(ConfigKey(file: missing, section: "Settings", key: "wideScreenHack"), "True")]).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
