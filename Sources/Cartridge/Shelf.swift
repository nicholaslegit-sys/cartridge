import SceneKit
import SwiftUI

/// One game case: a back shell with the disc tray, and a front cover hinged at the spine that carries the manual.
final class CaseNode {
    let game: Game
    let spec: CaseSpec
    let root = SCNNode()
    let hinge = SCNNode()
    let discSpin = SCNNode()
    private let shell: SCNNode
    private let spinePanel: SCNNode
    private let walls = SCNNode()
    private let cover: SCNNode
    let manual: SCNNode
    /// The cover printed on the booklet, kept while the case is in hand so the 3D booklet can start from it.
    private(set) var manualArt: CGImage?
    private let disc: SCNNode
    var slotPosition = SCNVector3Zero
    var slotEuler = SCNVector3Zero
    /// Where the disc rests on its hub when the case is shut.
    let discRestZ: CGFloat

    static let frontThickness: CGFloat = 0.0014
    /// The hollow between tray and cover that holds the disc and manual.
    static let cavity: CGFloat = 0.004
    static let wall: CGFloat = 0.0015

    /// The cover a case shows while standing on the shelf: only the last in a row has one, as only its front is visible.
    private let shelfFront: CGImage?

    init(game: Game, spec: CaseSpec, spine: CGImage, front: CGImage? = nil) {
        shelfFront = front
        self.game = game
        self.spec = spec
        root.name = "case:\(game.id.uuidString)"
        let t = Self.frontThickness, cavity = Self.cavity, wall = Self.wall
        let edge = Self.plastic(spec.plastic, coat: 0.4)

        // Back shell, from the back cover (-z) up to the tray face.
        let shellLength = spec.depth - t - cavity
        let shellBox = SCNBox(width: spec.width, height: spec.height, length: shellLength, chamferRadius: 0.0008)
        shellBox.materials = [edge]
        shell = SCNNode(geometry: shellBox)
        shell.position = SCNVector3(0, 0, -spec.depth / 2 + shellLength / 2)
        root.addChildNode(shell)
        let trayZ = -spec.depth / 2 + shellLength

        // Rim walls close the hollow on the three open sides and behind the spine.
        let rimZ = trayZ + cavity / 2
        for (w, h, x, y) in [(spec.width, wall, 0.0, spec.height / 2 - wall / 2), (spec.width, wall, 0.0, -spec.height / 2 + wall / 2),
                             (wall, spec.height, spec.width / 2 - wall / 2, 0.0), (wall, spec.height, -spec.width / 2 + wall / 2, 0.0)] {
            let box = SCNBox(width: w, height: h, length: cavity, chamferRadius: 0)
            box.materials = [edge]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(x, y, rimZ)
            walls.addChildNode(node)
        }
        root.addChildNode(walls)

        // The spine is one printed panel across the full thickness, facing -x.
        let spinePlane = SCNPlane(width: spec.depth, height: spec.height)
        spinePlane.materials = [Self.printed(spine)]
        spinePanel = SCNNode(geometry: spinePlane)
        spinePanel.position = SCNVector3(-spec.width / 2 - 0.0002, 0, 0)
        spinePanel.eulerAngles.y = -.pi / 2
        root.addChildNode(spinePanel)

        hinge.position = SCNVector3(-spec.width / 2, 0, spec.depth / 2 - t / 2)
        root.addChildNode(hinge)
        let coverBox = SCNBox(width: spec.width, height: spec.height, length: t, chamferRadius: 0.0005)
        coverBox.materials = Self.shelfCoverMaterials(front: front, edge: edge)
        cover = SCNNode(geometry: coverBox)
        cover.position = SCNVector3(spec.width / 2, 0, 0)
        hinge.addChildNode(cover)

        // The manual rides on the inside of the cover, so it swings into view as the case opens.
        let manualBox = SCNBox(width: spec.width * 0.9, height: spec.height * 0.92, length: 0.0018, chamferRadius: 0.0003)
        manual = SCNNode(geometry: manualBox)
        manual.name = "manual"
        manual.position = SCNVector3(spec.width / 2 + spec.width * 0.01, 0, -t / 2 - 0.001)
        manual.isHidden = true
        hinge.addChildNode(manual)

        discRestZ = trayZ + 0.0008
        discSpin.position = SCNVector3(0, 0, discRestZ)
        root.addChildNode(discSpin)
        disc = SCNNode(geometry: Self.discGeometry(outer: spec.discRadius, inner: 0.0075, thickness: 0.0012))
        disc.isHidden = true
        discSpin.addChildNode(disc)
    }

    /// Paints every face for close inspection. Shelf-only cases keep just their spine to save memory.
    func showDetail(spine: CGImage, front: CGImage, back: CGImage, tray: CGImage, coverInside: CGImage, manualArt: CGImage, label: CGImage, roughness: CGImage) {
        let edge = Self.plastic(spec.plastic, coat: 0.4)
        // SCNBox faces: +z, +x, -z, -x, +y, -y.
        shell.geometry?.materials = [Self.plastic(tray), edge, Self.printed(back, roughness: roughness), edge, edge, edge]
        spinePanel.geometry?.materials = [Self.printed(spine, roughness: roughness)]
        cover.geometry?.materials = [Self.printed(front, roughness: roughness), edge, Self.plastic(coverInside), edge, edge, edge]

        let paper = SCNMaterial()
        paper.lightingModel = .physicallyBased
        paper.diffuse.contents = NSColor(white: 0.93, alpha: 1)
        paper.roughness.contents = 0.9
        let print = SCNMaterial()
        print.lightingModel = .physicallyBased
        print.diffuse.contents = manualArt
        print.roughness.contents = 0.6
        // The printed side faces into the case (-z) until the cover swings round.
        manual.geometry?.materials = [paper, paper, print, paper, paper, paper]
        manual.isHidden = false
        self.manualArt = manualArt

        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = NSColor(white: 0.85, alpha: 1)
        side.metalness.contents = 1.0
        side.roughness.contents = 0.25
        let top = SCNMaterial()
        top.lightingModel = .physicallyBased
        top.diffuse.contents = label
        top.roughness.contents = 0.45
        let underside = SCNMaterial()
        underside.lightingModel = .physicallyBased
        underside.diffuse.contents = spec.discUnderside
        underside.metalness.contents = 1.0
        underside.roughness.contents = 0.08
        disc.geometry?.materials = [top, underside, side]
        disc.isHidden = false
    }

    func setLabel(_ label: CGImage) {
        disc.geometry?.materials[0].diffuse.contents = label
    }

    func dropDetail(spine: CGImage) {
        let edge = Self.plastic(spec.plastic, coat: 0.4)
        shell.geometry?.materials = [edge]
        spinePanel.geometry?.materials = [Self.printed(spine)]
        cover.geometry?.materials = Self.shelfCoverMaterials(front: shelfFront, edge: edge)
        manual.isHidden = true
        manual.geometry?.materials = []
        manualArt = nil
        disc.isHidden = true
        disc.geometry?.materials = []
    }

    /// A flat ring facing +z, with the label mapped straight across it (SCNTube's cap mapping crops and mirrors it).
    /// Elements: printed top, underside, outer rim.
    static func discGeometry(outer: CGFloat, inner: CGFloat, thickness: CGFloat, segments: Int = 128) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var top: [Int32] = [], bottom: [Int32] = [], rim: [Int32] = []
        let half = thickness / 2
        for face in [1.0, -1.0] as [CGFloat] {
            let base = Int32(vertices.count)
            for i in 0...segments {
                let angle = CGFloat(i) / CGFloat(segments) * 2 * .pi
                for radius in [inner, outer] {
                    let x = cos(angle) * radius, y = sin(angle) * radius
                    vertices.append(SCNVector3(x, y, half * face))
                    normals.append(SCNVector3(0, 0, face))
                    // Seen from its own side, so the underside is mirrored back to read correctly.
                    uvs.append(CGPoint(x: 0.5 + face * x / (2 * outer), y: 0.5 - y / (2 * outer)))
                }
            }
            for i in 0..<Int32(segments) {
                let a = base + i * 2, b = a + 1, c = a + 2, d = a + 3
                if face > 0 { top += [a, b, d, a, d, c] } else { bottom += [a, d, b, a, c, d] }
            }
        }
        let rimBase = Int32(vertices.count)
        for i in 0...segments {
            let angle = CGFloat(i) / CGFloat(segments) * 2 * .pi
            for z in [half, -half] {
                vertices.append(SCNVector3(cos(angle) * outer, sin(angle) * outer, z))
                normals.append(SCNVector3(cos(angle), sin(angle), 0))
                uvs.append(CGPoint(x: CGFloat(i) / CGFloat(segments), y: z > 0 ? 0 : 1))
            }
        }
        for i in 0..<Int32(segments) {
            let a = rimBase + i * 2, b = a + 1, c = a + 2, d = a + 3
            rim += [a, b, d, a, d, c]
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [top, bottom, rim].map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        )
    }

    /// SCNBox faces: +z (the printed front), +x, -z, -x, +y, -y.
    static func shelfCoverMaterials(front: CGImage?, edge: SCNMaterial) -> [SCNMaterial] {
        guard let front else { return [edge] }
        return [printed(front), edge, edge, edge, edge, edge]
    }

    static func plastic(_ contents: Any, coat: CGFloat = 0.2) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = contents
        m.roughness.contents = 0.5
        m.metalness.contents = 0.0
        m.clearCoat.contents = coat
        m.clearCoatRoughness.contents = 0.25
        return m
    }

    /// A printed insert under a clear sleeve; the sleeve's scratches roughen its reflections.
    static func printed(_ image: CGImage, roughness: CGImage? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.roughness.contents = 0.45
        m.metalness.contents = 0.0
        m.clearCoat.contents = 0.3
        m.clearCoatRoughness.contents = roughness ?? 0.2
        return m
    }
}

@MainActor @Observable
final class ShelfController {
    enum Mode { case browsing, moving, inspecting }

    private(set) var mode: Mode = .browsing
    private(set) var hoveredID: UUID?
    private(set) var inspectedID: UUID?
    private(set) var isOpen = false

    enum BookletState: Equatable { case closed, loading, reading, failed }
    private(set) var booklet = BookletState.closed
    /// 1-based page numbers showing in the booklet, and how many pages it has.
    private(set) var bookletPages: (left: Int?, right: Int?, total: Int) = (nil, nil, 0)

    @ObservationIgnored let scene = SCNScene()
    @ObservationIgnored private let bookletHolder = SCNNode()
    @ObservationIgnored private var bookletNode: BookletNode?
    @ObservationIgnored let camera = SCNNode()
    @ObservationIgnored private let holder = SCNNode()
    @ObservationIgnored private let dimmer = SCNNode()
    @ObservationIgnored private let inspectLight = SCNNode()
    @ObservationIgnored private let shelf = SCNNode()
    @ObservationIgnored private let timer = SCNNode()
    @ObservationIgnored private var cases: [UUID: CaseNode] = [:]
    @ObservationIgnored private var spines: [UUID: CGImage] = [:]
    @ObservationIgnored private var signature = ""
    @ObservationIgnored private var pendingGames: [Game]?
    @ObservationIgnored private var panBounds = CGRect.zero
    @ObservationIgnored private var aspect: CGFloat = 1.6
    @ObservationIgnored weak var library: Library?

    static let viewingDistance: CGFloat = 0.72
    static let holdDistance: CGFloat = 0.42
    static let bookletDistance: CGFloat = 0.33
    static let boardDepth: CGFloat = 0.30
    static let inHandBit = 1 << 4

    private static func markInHand(_ node: SCNNode, _ inHand: Bool) {
        node.enumerateHierarchy { child, _ in
            child.categoryBitMask = inHand ? child.categoryBitMask | inHandBit : child.categoryBitMask & ~inHandBit
            // Drawn after the dimmer, so zooming a case out past the dimmer never clips it.
            child.renderingOrder = inHand ? 10 : 0
        }
    }

    var hasGames: Bool { !cases.isEmpty }

    init() {
        scene.background.contents = NSColor(red: 0.035, green: 0.03, blue: 0.035, alpha: 1)
        scene.lightingEnvironment.contents = ShelfArt.environment
        scene.lightingEnvironment.intensity = 0.7

        let lens = SCNCamera()
        lens.fieldOfView = 40
        lens.zNear = 0.02
        lens.zFar = 20
        camera.camera = lens
        scene.rootNode.addChildNode(camera)

        let dimPlane = SCNPlane(width: 6, height: 6)
        let black = SCNMaterial()
        black.lightingModel = .constant
        black.diffuse.contents = NSColor.black
        black.writesToDepthBuffer = false
        dimPlane.materials = [black]
        dimmer.geometry = dimPlane
        dimmer.name = "dimmer"
        dimmer.renderingOrder = 5
        dimmer.position = SCNVector3(0, 0, -0.62)
        dimmer.opacity = 0
        dimmer.isHidden = true
        camera.addChildNode(dimmer)

        holder.position = SCNVector3(0, 0, -Self.holdDistance)
        camera.addChildNode(holder)
        bookletHolder.position = SCNVector3(0, 0, -Self.bookletDistance)
        camera.addChildNode(bookletHolder)

        let key = SCNLight()
        key.type = .spot
        key.intensity = 0
        // Only the case in hand is lit by this; the shelf behind stays dim.
        key.categoryBitMask = Self.inHandBit
        key.spotInnerAngle = 30
        key.spotOuterAngle = 80
        key.color = NSColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        inspectLight.light = key
        inspectLight.position = SCNVector3(-0.45, 0.4, -0.1)
        inspectLight.look(at: SCNVector3(0, 0, -Self.holdDistance), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        camera.addChildNode(inspectLight)

        scene.rootNode.addChildNode(shelf)
        scene.rootNode.addChildNode(timer)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func seconds(_ value: TimeInterval) -> TimeInterval { reduceMotion ? 0.01 : value }

    // MARK: Building the bookcase

    func sync(_ games: [Game], artRevision: Int) {
        let newSignature = games.map { "\($0.id)|\($0.title)|\($0.system.rawValue)" }.joined(separator: ",") + "#\(artRevision)"
        guard newSignature != signature else { return }
        guard mode == .browsing else {
            pendingGames = games
            return
        }
        signature = newSignature
        rebuild(games)
    }

    private func rebuild(_ games: [Game]) {
        let firstBuild = cases.isEmpty
        shelf.childNodes.forEach { $0.removeFromParentNode() }
        cases = [:]
        spines = [:]
        hoveredID = nil

        let rows: [(System, [Game])] = System.allCases.filter(\.isDisc).compactMap { system in
            let row = games.filter { $0.system == system }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return row.isEmpty ? nil : (system, row)
        }
        guard !rows.isEmpty else { return }

        // Spines for a big library take a while, so paint them across all cores. The last case in each row
        // has its front cover showing, so that one gets its cover painted too.
        let jobs = rows.flatMap { system, games in games.map { (game: $0, spec: CaseSpec.of(system), exposed: $0.id == games.last?.id) } }
        // Each iteration writes only its own slots.
        nonisolated(unsafe) let painted = UnsafeMutableBufferPointer<(spine: CGImage?, front: CGImage?)>.allocate(capacity: jobs.count)
        painted.initialize(repeating: (nil, nil))
        defer { painted.deallocate() }
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            let job = jobs[i]
            let scans = ShelfArt.Scans(game: job.game, spec: job.spec, spineOnly: true, withFront: job.exposed)
            painted[i] = (ShelfArt.spine(game: job.game, spec: job.spec, scan: scans.spine),
                          job.exposed ? ShelfArt.front(game: job.game, spec: job.spec, art: scans.front) : nil)
        }
        var paintedSpines: [UUID: CGImage] = [:]
        var paintedFronts: [UUID: CGImage] = [:]
        for (i, job) in jobs.enumerated() {
            paintedSpines[job.game.id] = painted[i].spine
            paintedFronts[job.game.id] = painted[i].front
        }

        let board: CGFloat = 0.022, pad: CGFloat = 0.06, gap: CGFloat = 0.0012
        var width: CGFloat = 0.6
        for (system, games) in rows {
            width = max(width, pad * 2 + CGFloat(games.count) * (CaseSpec.of(system).depth + gap))
        }
        let depth = Self.boardDepth

        func slab(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, at position: SCNVector3, vertical: Bool = false) {
            let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0.002)
            box.materials = [Self.woodMaterial(length: vertical ? h : w, vertical: vertical)]
            let node = SCNNode(geometry: box)
            node.position = position
            shelf.addChildNode(node)
        }

        var top: CGFloat = 0
        slab(width + 0.04, board, depth + 0.01, at: SCNVector3(width / 2, top + board / 2, 0))
        for (system, games) in rows {
            let spec = CaseSpec.of(system)
            let boardTop = top - spec.height - 0.05
            slab(width, board, depth, at: SCNVector3(width / 2, boardTop - board / 2, 0))

            let plate = SCNPlane(width: 0.15, height: 0.019)
            let plateMaterial = SCNMaterial()
            plateMaterial.lightingModel = .physicallyBased
            plateMaterial.diffuse.contents = ShelfArt.plate(system.name)
            plateMaterial.metalness.contents = 0.85
            plateMaterial.roughness.contents = 0.35
            plate.materials = [plateMaterial]
            let plateNode = SCNNode(geometry: plate)
            plateNode.position = SCNVector3(pad + 0.075, boardTop - board / 2, depth / 2 + 0.0015)
            shelf.addChildNode(plateNode)

            var x = pad
            for game in games {
                guard let spine = paintedSpines[game.id] else { continue }
                let node = CaseNode(game: game, spec: spec, spine: spine, front: paintedFronts[game.id])
                var rng = SeededRandom(game.id, salt: 9)
                // Standing on edge with the spine out, a little out of line like a real shelf.
                node.slotPosition = SCNVector3(x + spec.depth / 2, boardTop + spec.height / 2 + 0.0004, depth / 2 - spec.width / 2 - 0.01 - rng.unit() * 0.008)
                node.slotEuler = SCNVector3(0, CGFloat.pi / 2 + (rng.unit() - 0.5) * 0.03, 0)
                node.root.position = node.slotPosition
                node.root.eulerAngles = node.slotEuler
                shelf.addChildNode(node.root)
                cases[game.id] = node
                spines[game.id] = spine
                x += spec.depth + gap
            }
            top = boardTop - board
        }
        let bottom = top
        slab(0.02, -bottom + board * 2, depth + 0.01, at: SCNVector3(-0.01, (board + bottom) / 2, 0), vertical: true)
        slab(0.02, -bottom + board * 2, depth + 0.01, at: SCNVector3(width + 0.01, (board + bottom) / 2, 0), vertical: true)
        slab(width + 0.04, -bottom + board * 2, 0.01, at: SCNVector3(width / 2, (board + bottom) / 2, -depth / 2 - 0.005), vertical: true)

        let room = SCNLight()
        room.type = .ambient
        room.intensity = 200
        room.color = NSColor(red: 1, green: 0.92, blue: 0.85, alpha: 1)
        let roomNode = SCNNode()
        roomNode.light = room
        shelf.addChildNode(roomNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 650
        sun.castsShadow = true
        sun.shadowRadius = 8
        sun.shadowSampleCount = 16
        sun.shadowMapSize = CGSize(width: 4096, height: 4096)
        sun.shadowColor = NSColor(white: 0, alpha: 0.6)
        sun.automaticallyAdjustsShadowProjection = true
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.position = SCNVector3(width / 2 - 0.4, 1.0, 1.2)
        sunNode.look(at: SCNVector3(width / 2, bottom / 2, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        shelf.addChildNode(sunNode)

        panBounds = CGRect(x: -0.02, y: bottom - 0.02, width: width + 0.04, height: -bottom + board + 0.04)
        frameCamera(resetToTop: firstBuild)
    }

    /// Wood with the grain along the slab's long side, repeated at a real-world scale.
    static func woodMaterial(length: CGFloat, vertical: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = ShelfArt.wood
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        let scale = SCNMatrix4MakeScale(max(1, length / 0.6), max(1, length / 0.6) / 2, 1)
        m.diffuse.contentsTransform = vertical ? SCNMatrix4Mult(SCNMatrix4MakeRotation(.pi / 2, 0, 0, 1), scale) : scale
        m.roughness.contents = 0.65
        return m
    }

    func viewResized(_ size: CGSize) {
        guard size.height > 0 else { return }
        aspect = size.width / size.height
        frameCamera(resetToTop: false)
    }

    private var visibleHalfHeight: CGFloat { Self.viewingDistance * tan(20 * .pi / 180) }
    private var visibleHalfWidth: CGFloat { visibleHalfHeight * aspect }

    private func frameCamera(resetToTop: Bool) {
        var p = camera.position
        if resetToTop {
            p.x = panBounds.minX
            p.y = panBounds.maxY
        }
        p.z = Self.boardDepth / 2 + Self.viewingDistance
        camera.position = clamp(p)
    }

    /// Keeps the bookcase filling the view: centred when it fits, otherwise no further than its edges.
    private func clamp(_ p: SCNVector3) -> SCNVector3 {
        func axis(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, _ half: CGFloat) -> CGFloat {
            high - low <= half * 2 ? (low + high) / 2 : min(max(value, low + half), high - half)
        }
        return SCNVector3(axis(p.x, panBounds.minX, panBounds.maxX, visibleHalfWidth),
                          axis(p.y, panBounds.minY, panBounds.maxY, visibleHalfHeight), p.z)
    }

    // MARK: Input

    enum Target: Equatable {
        case nothing, booklet
        case game(UUID, manual: Bool)
    }

    func target(at point: CGPoint, in view: SCNView) -> Target {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
        var node = hits.first?.node
        var manual = false
        while let current = node {
            if current.name == "booklet" { return .booklet }
            if current.name == "manual" { manual = true }
            if let name = current.name, name.hasPrefix("case:"), let id = UUID(uuidString: String(name.dropFirst(5))) {
                return .game(id, manual: manual)
            }
            node = current.parent
        }
        return .nothing
    }

    func caseID(at point: CGPoint, in view: SCNView) -> UUID? {
        if case .game(let id, _) = target(at: point, in: view) { return id }
        return nil
    }

    func hover(_ id: UUID?) {
        guard mode == .browsing, id != hoveredID else { return }
        if let old = hoveredID, let node = cases[old] {
            node.root.runAction(.move(to: node.slotPosition, duration: seconds(0.18)), forKey: "hover")
        }
        hoveredID = id
        if let id, let node = cases[id] {
            var out = node.slotPosition
            out.z += 0.028
            node.root.runAction(.move(to: out, duration: seconds(0.18)), forKey: "hover")
        }
    }

    /// `onRightHalf` says which side of the view was clicked, for turning booklet pages.
    func click(_ target: Target, onRightHalf: Bool) {
        switch mode {
        case .browsing:
            if case .game(let id, _) = target { take(id) }
        case .inspecting where booklet != .closed:
            if target == .booklet { turnPage(forward: onRightHalf) } else { closeBooklet() }
        case .inspecting:
            if case .game(let id, let manual) = target, id == inspectedID {
                if manual, isOpen { openBooklet() } else { toggleOpen() }
            } else {
                putBack()
            }
        case .moving:
            break
        }
    }

    func drag(dx: CGFloat, dy: CGFloat) {
        switch mode {
        case .browsing:
            camera.position = clamp(SCNVector3(camera.position.x - dx * 0.0012, camera.position.y + dy * 0.0012, camera.position.z))
        case .inspecting:
            let turning = booklet == .closed ? holder : bookletHolder
            var angles = turning.eulerAngles
            angles.y += dx * 0.012
            angles.x = min(max(angles.x + dy * 0.008, -1.1), 1.1)
            turning.eulerAngles = angles
        case .moving:
            break
        }
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        switch mode {
        case .browsing:
            camera.position = clamp(SCNVector3(camera.position.x - dx * 0.0015, camera.position.y + dy * 0.0015, camera.position.z))
        case .inspecting where booklet != .closed:
            var p = bookletHolder.position
            p.z = min(max(p.z + dy * 0.001, -0.5), -0.16)
            bookletHolder.position = p
        case .inspecting:
            var p = holder.position
            p.z = min(max(p.z + dy * 0.001, -0.6), -0.3)
            holder.position = p
        case .moving:
            break
        }
    }

    // MARK: Taking a case, opening it, putting it back

    func take(_ id: UUID) {
        guard mode == .browsing, let node = cases[id] else { return }
        mode = .moving
        hoveredID = nil
        inspectedID = id
        isOpen = false
        node.root.removeAllActions()

        let game = library?.games.first { $0.id == id } ?? node.game
        let spec = node.spec
        Task {
            let faces = await Task.detached {
                let scans = ShelfArt.Scans(game: game, spec: spec)
                return (front: ShelfArt.front(game: game, spec: spec, art: scans.front),
                        back: ShelfArt.back(game: game, spec: spec, art: scans.front, shot: scans.title, scan: scans.back),
                        tray: ShelfArt.inside(spec: spec, tray: true),
                        coverInside: ShelfArt.inside(spec: spec, tray: false),
                        manual: ShelfArt.manual(game: game, spec: spec, art: scans.front),
                        label: ShelfArt.disc(game: game, spec: spec, label: scans.title, art: scans.front, scan: scans.disc),
                        roughness: ShelfArt.roughness(game.id),
                        needsLabel: scans.disc == nil && scans.title == nil,
                        art: scans.front)
            }.value
            guard inspectedID == id, let spine = spines[id] else { return }
            node.showDetail(spine: spine, front: faces.front, back: faces.back, tray: faces.tray, coverInside: faces.coverInside, manualArt: faces.manual, label: faces.label, roughness: faces.roughness)
            // Without a disc scan, the title screen makes a better label than the box art; fetch it if we can.
            let art = faces.art
            if faces.needsLabel, let library {
                await library.fetchLabelArt(game)
                if inspectedID == id, let fetched = ShelfArt.cgImage(library.labelImage(for: game)) {
                    let disc = await Task.detached { ShelfArt.disc(game: game, spec: spec, label: fetched, art: art) }.value
                    if inspectedID == id { node.setLabel(disc) }
                }
            }
        }

        // Keep it where it is on screen while handing it to the camera-mounted holder.
        holder.eulerAngles = SCNVector3Zero
        holder.position = SCNVector3(0, 0, -Self.holdDistance)
        let world = node.root.worldTransform
        node.root.removeFromParentNode()
        holder.addChildNode(node.root)
        node.root.transform = holder.convertTransform(world, from: nil)
        Self.markInHand(node.root, true)

        var pulled = node.root.position
        pulled.z += 0.09
        let pull = SCNAction.move(to: pulled, duration: seconds(0.22))
        pull.timingMode = .easeOut
        let fly = SCNAction.group([
            .move(to: SCNVector3Zero, duration: seconds(0.7)),
            .rotateTo(x: 0.06, y: -0.42, z: 0, duration: seconds(0.7), usesShortestUnitArc: true),
        ])
        fly.timingMode = .easeInEaseOut
        node.root.runAction(.sequence([pull, fly])) { [weak self] in
            DispatchQueue.main.async { self?.settle() }
        }
        dimmer.isHidden = false
        dimmer.runAction(.fadeOpacity(to: 0.8, duration: seconds(0.6)))
        inspectLight.runAction(Self.lightFade(to: 9, duration: seconds(0.6)))
    }

    private func settle() {
        guard mode == .moving, inspectedID != nil else { return }
        mode = .inspecting
        if !reduceMotion {
            let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.004, z: 0, duration: 1.6), .moveBy(x: 0, y: -0.004, z: 0, duration: 1.6)])
            bob.timingMode = .easeInEaseOut
            holder.runAction(.repeatForever(bob), forKey: "bob")
        }
    }

    func toggleOpen() {
        guard mode == .inspecting, booklet == .closed, let id = inspectedID, let node = cases[id] else { return }
        mode = .moving
        let spec = node.spec
        if !isOpen {
            isOpen = true
            holder.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: seconds(0.35), usesShortestUnitArc: true))
            // Face the camera, then slide right so the open spread is centred.
            let face = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: seconds(0.35), usesShortestUnitArc: true)
            let center = SCNAction.move(to: SCNVector3(spec.width / 2, 0, -0.03), duration: seconds(0.8))
            center.timingMode = .easeInEaseOut
            node.root.runAction(.sequence([face, center]))

            let unlatch = SCNAction.rotateTo(x: 0, y: -0.07, z: 0, duration: seconds(0.09), usesShortestUnitArc: false)
            let pop = SCNAction.rotateTo(x: 0, y: -.pi * 0.985, z: 0, duration: seconds(0.8), usesShortestUnitArc: false)
            pop.timingFunction = { t in
                // Ease out with a small overshoot: the cover springs open and settles.
                let s: Float = 1.25, u = t - 1
                return 1 + (s + 1) * u * u * u + s * u * u
            }
            node.hinge.runAction(.sequence([.wait(duration: seconds(0.35)), unlatch, .run { _ in
                DispatchQueue.main.async { Self.click("Pop") }
            }, pop]))

            let lift = SCNAction.move(by: SCNVector3(0, 0, 0.005), duration: seconds(0.3))
            lift.timingMode = .easeOut
            node.discSpin.runAction(.sequence([.wait(duration: seconds(0.9)), lift]))
            if !reduceMotion {
                node.discSpin.runAction(.sequence([.wait(duration: seconds(1.0)), .repeatForever(.rotateBy(x: 0, y: 0, z: -.pi * 2, duration: 7))]), forKey: "spin")
            }
            after(seconds(1.25)) { [weak self] in
                if self?.mode == .moving { self?.mode = .inspecting }
            }
        } else {
            close(node) { [weak self] in self?.mode = .inspecting }
        }
    }

    private func close(_ node: CaseNode, then: @escaping @MainActor () -> Void) {
        isOpen = false
        node.discSpin.removeAction(forKey: "spin")
        node.discSpin.runAction(.group([
            .rotateTo(x: 0, y: 0, z: 0, duration: seconds(0.3), usesShortestUnitArc: true),
            .move(to: SCNVector3(0, 0, node.discRestZ), duration: seconds(0.3)),
        ]))
        let shut = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: seconds(0.45), usesShortestUnitArc: false)
        shut.timingMode = .easeIn
        node.hinge.runAction(.sequence([.wait(duration: seconds(0.15)), shut, .run { _ in
            DispatchQueue.main.async { Self.click("Tink") }
        }]))
        let back = SCNAction.move(to: SCNVector3Zero, duration: seconds(0.5))
        back.timingMode = .easeInEaseOut
        node.root.runAction(.sequence([.wait(duration: seconds(0.15)), back]))
        after(seconds(0.65), then)
    }

    func putBack() {
        guard mode == .inspecting, let id = inspectedID, let node = cases[id] else { return }
        if booklet != .closed { return closeBooklet() }
        mode = .moving
        if isOpen {
            close(node) { [weak self] in
                self?.mode = .inspecting
                self?.putBack()
            }
            return
        }
        holder.removeAction(forKey: "bob")
        let world = node.root.worldTransform
        node.root.removeFromParentNode()
        shelf.addChildNode(node.root)
        node.root.transform = shelf.convertTransform(world, from: nil)
        holder.eulerAngles = SCNVector3Zero
        holder.position = SCNVector3(0, 0, -Self.holdDistance)

        var outside = node.slotPosition
        outside.z += 0.09
        let fly = SCNAction.group([
            .move(to: outside, duration: seconds(0.6)),
            .rotateTo(x: node.slotEuler.x, y: node.slotEuler.y, z: node.slotEuler.z, duration: seconds(0.6), usesShortestUnitArc: true),
        ])
        fly.timingMode = .easeInEaseOut
        let slide = SCNAction.move(to: node.slotPosition, duration: seconds(0.22))
        slide.timingMode = .easeOut
        node.root.runAction(.sequence([fly, slide])) { [weak self] in
            DispatchQueue.main.async { self?.finishPutBack(id) }
        }
        dimmer.runAction(.sequence([.fadeOpacity(to: 0, duration: seconds(0.5)), .hide()]))
        inspectLight.runAction(Self.lightFade(to: 0, duration: seconds(0.5)))
    }

    private func finishPutBack(_ id: UUID) {
        if let node = cases[id], let spine = spines[id] {
            node.dropDetail(spine: spine)
            Self.markInHand(node.root, false)
        }
        inspectedID = nil
        mode = .browsing
        if let games = pendingGames {
            pendingGames = nil
            sync(games, artRevision: library?.artRevision ?? 0)
        }
    }

    // MARK: The instruction booklet

    /// Lifts the booklet out of the open case towards the camera, then fetches its pages.
    func openBooklet() {
        guard mode == .inspecting, isOpen, booklet == .closed, let id = inspectedID, let node = cases[id] else { return }
        mode = .moving
        booklet = .loading
        bookletPages = (nil, nil, 0)
        holder.removeAction(forKey: "bob")

        let book = BookletNode(size: CGSize(width: node.spec.width * 0.9, height: node.spec.height * 0.92), cover: node.manualArt)
        bookletNode = book
        bookletHolder.eulerAngles = SCNVector3Zero
        bookletHolder.position = SCNVector3(0, 0, -Self.bookletDistance)
        bookletHolder.addChildNode(book.root)
        // Start exactly where the booklet sits in the open case. Its printed side is -z there; the 3D booklet's
        // cover is +z, hence the half turn.
        book.root.simdWorldOrientation = node.manual.simdWorldOrientation * simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        book.root.simdWorldPosition = node.manual.simdWorldPosition
        Self.markInHand(book.root, true)
        node.manual.isHidden = true

        let fly = SCNAction.group([
            .move(to: SCNVector3Zero, duration: seconds(0.6)),
            .rotateTo(x: 0, y: 0, z: 0, duration: seconds(0.6), usesShortestUnitArc: true),
            .scale(to: 1, duration: seconds(0.6)),
        ])
        fly.timingMode = .easeInEaseOut
        book.root.runAction(fly)
        node.root.runAction(.fadeOut(duration: seconds(0.35)))
        after(seconds(0.6)) { [weak self] in
            if self?.mode == .moving { self?.mode = .inspecting }
        }
        loadBookletPages(for: id, into: book)
    }

    /// Tries again after the player chose a PDF.
    func reloadBooklet() {
        guard booklet != .closed, let id = inspectedID, let book = bookletNode else { return }
        booklet = .loading
        loadBookletPages(for: id, into: book)
    }

    private func loadBookletPages(for id: UUID, into book: BookletNode) {
        Task { [weak self] in
            guard let library = self?.library else { return }
            guard let url = await library.manual(for: id) else {
                if let self, self.bookletNode === book { self.booklet = .failed }
                return
            }
            let pages = await Task.detached { BookletPages.pageSizes(of: url).map { BookletPages(pageSizes: $0) } }.value
            guard let self, self.bookletNode === book else { return }
            guard let pages, !pages.pages.isEmpty else {
                self.booklet = .failed
                return
            }
            book.load(pdf: url, pages: pages)
            self.booklet = .reading
            self.updateBookletPages()
            // Open to the first spread once the pages are in, the way you'd flip past the cover.
            self.after(self.seconds(0.5)) { [weak self] in
                guard let self, self.bookletNode === book, book.turned == 0, book.leafCount > 1 else { return }
                self.turnPage(forward: true)
            }
        }
    }

    func turnPage(forward: Bool) {
        guard booklet == .reading, let book = bookletNode else { return }
        if book.turn(forward: forward, duration: seconds(0.55)) {
            updateBookletPages()
        }
    }

    private func updateBookletPages() {
        guard let book = bookletNode else { return }
        let visible = book.visiblePages
        bookletPages = (visible.left, visible.right, book.pages?.pages.count ?? 0)
    }

    /// Shuts the booklet and puts it back in the case.
    func closeBooklet() {
        guard booklet != .closed, mode == .inspecting, let book = bookletNode, let id = inspectedID, let node = cases[id] else { return }
        mode = .moving
        let closing = book.turned > 0 ? seconds(0.3) : 0
        book.closeAll(duration: seconds(0.3))

        // Fly back in world space, from wherever the player turned or zoomed it to.
        let startPosition = book.root.simdWorldPosition, startOrientation = book.root.simdWorldOrientation
        let endPosition = node.manual.simdWorldPosition
        let endOrientation = node.manual.simdWorldOrientation * simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        let duration = seconds(0.55)
        let fly = SCNAction.customAction(duration: duration) { root, elapsed in
            let x = Float(duration > 0 ? min(elapsed / CGFloat(duration), 1) : 1)
            let t = x * x * (3 - 2 * x)
            root.simdWorldPosition = simd_mix(startPosition, endPosition, SIMD3(repeating: t))
            root.simdWorldOrientation = simd_slerp(startOrientation, endOrientation, t)
        }
        book.root.runAction(.sequence([.wait(duration: closing), fly]))
        node.root.runAction(.sequence([.wait(duration: closing + seconds(0.2)), .fadeIn(duration: seconds(0.35))]))

        after(closing + duration + 0.05) { [weak self] in
            guard let self else { return }
            book.root.removeFromParentNode()
            node.manual.isHidden = false
            if self.bookletNode === book { self.bookletNode = nil }
            self.bookletHolder.eulerAngles = SCNVector3Zero
            self.bookletHolder.position = SCNVector3(0, 0, -Self.bookletDistance)
            self.booklet = .closed
            self.bookletPages = (nil, nil, 0)
            self.mode = .inspecting
        }
    }

    /// Runs `work` once `seconds` of scene time have passed, so it stays in step with the animations.
    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        timer.runAction(.wait(duration: seconds)) {
            DispatchQueue.main.async { work() }
        }
    }

    private static func lightFade(to intensity: CGFloat, duration: TimeInterval) -> SCNAction {
        var start: CGFloat?
        return .customAction(duration: duration) { node, elapsed in
            guard let light = node.light else { return }
            if start == nil { start = light.intensity }
            let t = duration > 0 ? min(elapsed / CGFloat(duration), 1) : 1
            light.intensity = start! + (intensity - start!) * t
        }
    }

    private static func click(_ name: String) {
        guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = 0.35
        sound.play()
    }
}

final class ShelfSCNView: SCNView {
    weak var controller: ShelfController?
    private var downPoint: CGPoint?
    private var dragged = false

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        controller?.viewResized(newSize)
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        guard let controller else { return }
        let target = controller.target(at: point(event), in: self)
        if case .game(let id, _) = target { controller.hover(id) } else { controller.hover(nil) }
        switch (controller.mode, target) {
        case (.browsing, .game), (.inspecting, .game(_, manual: true)), (.inspecting, .booklet):
            NSCursor.pointingHand.set()
        default:
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        controller?.hover(nil)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downPoint = point(event)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        let p = point(event)
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 4 { dragged = true }
        if dragged {
            controller?.drag(dx: event.deltaX, dy: event.deltaY)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard !dragged else { return }
        guard let controller else { return }
        let p = point(event)
        controller.click(controller.target(at: p, in: self), onRightHalf: p.x > bounds.midX)
    }

    override func scrollWheel(with event: NSEvent) {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        controller?.scroll(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale)
    }

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49:                                  // space
            if controller.booklet == .closed { controller.toggleOpen() } else { controller.turnPage(forward: true) }
        case 123: controller.turnPage(forward: false)   // left arrow
        case 124: controller.turnPage(forward: true)    // right arrow
        case 53: controller.putBack()             // escape: closes the booklet first
        case 36, 76:                              // return, enter
            if let id = controller.inspectedID, let game = controller.library?.games.first(where: { $0.id == id }) {
                controller.library?.requestPlay(game)
            }
        default: super.keyDown(with: event)
        }
    }
}

struct ShelfSceneView: NSViewRepresentable {
    let controller: ShelfController

    func makeNSView(context: Context) -> ShelfSCNView {
        let view = ShelfSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.controller = controller
        view.scene = controller.scene
        view.pointOfView = controller.camera
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = false
        view.isPlaying = true
        return view
    }

    func updateNSView(_ view: ShelfSCNView, context: Context) {}
}

struct ShelfScreen: View {
    @Environment(Library.self) private var library
    @State private var controller = ShelfController()

    private var discGames: [Game] { library.games.filter { $0.system.isDisc } }

    private func game(_ id: UUID?) -> Game? {
        library.games.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            ShelfSceneView(controller: controller)

            VStack {
                if let game = game(controller.hoveredID), controller.mode == .browsing {
                    HStack(spacing: 8) {
                        SystemBadge(system: game.system)
                        Text(game.title).font(.headline)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
                Spacer()
                if let game = game(controller.inspectedID), controller.booklet != .closed {
                    BookletBar(game: game, controller: controller)
                        .padding(18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let game = game(controller.inspectedID) {
                    InspectionBar(game: game, controller: controller)
                        .padding(18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !discGames.isEmpty {
                    Text("Click a case to take it off the shelf · Scroll or drag to browse")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.inspectedID)
            .animation(.easeInOut(duration: 0.2), value: controller.booklet)
            .animation(.easeInOut(duration: 0.15), value: controller.hoveredID)

            if discGames.isEmpty {
                ContentUnavailableView {
                    Label("Your shelf is empty", systemImage: "books.vertical")
                } description: {
                    Text("Disc games (PlayStation, GameCube, Wii, Xbox, Dreamcast, Saturn, PSP) show up here as cases you can pick up and open.")
                } actions: {
                    Button("Add Games…") { library.isPickingFiles = true }
                }
                .foregroundStyle(.white)
            }
        }
        .navigationTitle("Game Shelf")
        .onAppear {
            controller.library = library
            controller.sync(discGames, artRevision: library.artRevision)
        }
        .onChange(of: discGames) { _, games in controller.sync(games, artRevision: library.artRevision) }
        .onChange(of: library.artRevision) { _, revision in controller.sync(discGames, artRevision: revision) }
    }
}

struct InspectionBar: View {
    let game: Game
    let controller: ShelfController
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    SystemBadge(system: game.system)
                    Text(game.title).font(.title3.bold()).lineLimit(1)
                }
                Text(controller.isOpen ? "Click the booklet to read it · Space to close" : "Drag to turn it over · Space to open")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button(controller.isOpen ? "Close Case" : "Open Case") { controller.toggleOpen() }
                .disabled(controller.mode != .inspecting)
            PlayControls(game: game)
                .frame(width: 170)
            Button("Put Back") { controller.putBack() }
                .disabled(controller.mode != .inspecting)
        }
        .padding(14)
        .frame(maxWidth: 820)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, .dark)
    }
}

struct BookletBar: View {
    let game: Game
    let controller: ShelfController
    @Environment(Library.self) private var library

    private var status: String {
        switch controller.booklet {
        case .closed:
            return ""
        case .loading:
            switch library.manualStatus[game.id] {
            case .searching: return "Searching manual archives (Internet Archive, Musée des jeux vidéo, Digital Press)…"
            case .downloading(let progress): return "Downloading the manual… \(Int(progress * 100))%"
            default: return "Opening the booklet…"
            }
        case .reading:
            let pages = controller.bookletPages
            let showing = [pages.left, pages.right].compactMap { $0 }.map(String.init).joined(separator: "–")
            return "Page \(showing) of \(pages.total) · ← → or click a page to turn"
        case .failed:
            if case .failed(let message) = library.manualStatus[game.id] { return message }
            return "That manual couldn't be opened."
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    SystemBadge(system: game.system)
                    Text("\(game.title) — Instruction Booklet").font(.title3.bold()).lineLimit(1)
                }
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 20)
            switch controller.booklet {
            case .loading:
                if case .downloading(let progress) = library.manualStatus[game.id] {
                    ProgressView(value: progress).frame(width: 120)
                } else {
                    ProgressView().controlSize(.small)
                }
            case .reading:
                if let source = library.games.first(where: { $0.id == game.id })?.manualSource, let url = URL(string: source), url.scheme == "https" {
                    Link("Source", destination: url).font(.caption)
                }
                Button { controller.turnPage(forward: false) } label: { Image(systemName: "chevron.left") }
                    .disabled(controller.bookletPages.left == nil)
                Button { controller.turnPage(forward: true) } label: { Image(systemName: "chevron.right") }
                    .disabled(controller.bookletPages.right == nil)
            case .failed:
                let matches = library.manualCandidates[game.id] ?? []
                if !matches.isEmpty {
                    Menu("Possible Matches") {
                        ForEach(matches.prefix(15)) { match in
                            Button("\(match.title) — \(match.source.rawValue)") {
                                Task {
                                    if await library.useManual(match, for: game.id) != nil { controller.reloadBooklet() }
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
                Button("Choose PDF…") { choosePDF() }
                Button("Search the Archive") { NSWorkspace.shared.open(Manuals.searchPage(title: game.title)) }
            case .closed:
                EmptyView()
            }
            Button("Back to Case") { controller.closeBooklet() }
                .disabled(controller.mode != .inspecting)
        }
        .padding(14)
        .frame(maxWidth: 860)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, .dark)
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose the instruction booklet for \(game.title)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.setManual(url, for: game)
            controller.reloadBooklet()
        } catch {
            library.error = error.localizedDescription
        }
    }
}
