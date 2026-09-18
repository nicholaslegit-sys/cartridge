import AppKit
import Metal
import SceneKit
import Testing
@testable import Cartridge

/// Renders the 3D shelf to PNGs for eyeballing. Run with
/// CARTRIDGE_HOME=<a library> CARTRIDGE_RENDER=<output folder> swift test --filter ShelfRenderTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CARTRIDGE_RENDER"] != nil))
@MainActor
struct ShelfRenderTests {
    @Test func renderShelfTakeAndOpen() async throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CARTRIDGE_RENDER"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let size = CGSize(width: 1400, height: 900)

        let library = Library()
        if ProcessInfo.processInfo.environment["CARTRIDGE_RENDER_FETCH"] == "1" {
            await library.fetchMissingArtwork()
        }
        let controller = ShelfController()
        controller.library = library
        controller.viewResized(size)
        let discs = library.games.filter { $0.system.isDisc }
        controller.sync(discs, artRevision: library.artRevision)
        #expect(controller.hasGames)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = controller.scene
        renderer.pointOfView = controller.camera
        var clock: TimeInterval = 0

        func shot(_ name: String) throws {
            let image = renderer.snapshot(atTime: clock, with: size, antialiasingMode: .multisampling4X)
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
        }
        /// Steps scene time and lets main-queue completion handlers run.
        func advance(_ seconds: TimeInterval) async throws {
            let steps = Int(seconds / 0.05)
            for _ in 0..<steps {
                clock += 0.05
                _ = renderer.snapshot(atTime: clock, with: CGSize(width: 64, height: 40), antialiasingMode: .none)
                try await Task.sleep(for: .milliseconds(2))
            }
        }

        try shot("1-shelf")
        let pick = try #require(discs.first { $0.system == .ps2 } ?? discs.first)
        controller.scroll(dx: 0, dy: -500)
        controller.hover(pick.id)
        try await advance(0.3)
        try shot("2-hover")
        controller.take(pick.id)
        try await advance(0.45)
        try shot("3-flying")
        try await advance(1.0)
        #expect(controller.mode == .inspecting)
        try shot("4-inspecting")
        controller.toggleOpen()
        try await advance(0.8)
        try shot("5-opening")
        try await advance(1.2)
        #expect(controller.isOpen)
        try shot("6-open")
        let label = ShelfArt.disc(game: pick, spec: CaseSpec.of(pick.system), label: nil, art: ShelfArt.cgImage(library.image(for: pick)))
        try NSBitmapImageRep(cgImage: label).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("label-texture.png"))
        controller.scroll(dx: 0, dy: 400)
        try shot("6b-closeup")
        controller.scroll(dx: 0, dy: -400)
        controller.drag(dx: 90, dy: 0)
        try shot("7-open-turned")
        // Zoomed all the way out, the turned case must stay whole in front of the dimmer.
        controller.scroll(dx: 0, dy: -1000)
        try shot("7b-open-turned-zoomed-out")
        controller.scroll(dx: 0, dy: 1000)

        // The booklet: fly it out, let the manual load (from the network with CARTRIDGE_RENDER_FETCH), read, put back.
        controller.openBooklet()
        #expect(controller.booklet == .loading)
        try await advance(0.3)
        try shot("8a-booklet-flying")
        for _ in 0..<600 where controller.booklet == .loading {
            try await advance(0.05)
            try await Task.sleep(for: .milliseconds(50))
        }
        print("booklet:", controller.booklet, library.manualStatus[pick.id] as Any)
        if controller.booklet == .reading {
            try await advance(1.2)
            try await Task.sleep(for: .seconds(2))
            try await advance(0.1)
            try shot("8b-booklet-spread")
            controller.turnPage(forward: true)
            try await advance(0.25)
            try shot("8c-booklet-turning")
            try await advance(0.5)
            try await Task.sleep(for: .seconds(1))
            try await advance(0.1)
            try shot("8d-booklet-next-spread")
            print("pages:", controller.bookletPages)
        } else {
            try shot("8b-booklet-failed")
        }
        controller.closeBooklet()
        try await advance(1.5)
        #expect(controller.booklet == .closed)
        #expect(controller.mode == .inspecting)
        try shot("8e-booklet-back-in-case")
        controller.putBack()
        try await advance(2.0)
        #expect(controller.mode == .browsing)
        try shot("8-back")
    }
}
