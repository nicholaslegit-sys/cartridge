import SceneKit

/// An instruction booklet you can page through: one leaf per sheet, each hinged at the spine.
/// Leaf i shows page 2i on its front and page 2i+1 on its back, so turning a leaf reveals the next spread.
@MainActor
final class BookletNode {
    let root = SCNNode()
    private let binding = SCNNode()
    private var leaves: [SCNNode] = []
    private(set) var size: CGSize
    private(set) var turned = 0
    private var pdf: URL?
    private(set) var pages: BookletPages?
    private var textures: [Int: CGImage] = [:]
    private var requested = Set<Int>()
    private var generation = 0

    /// Leaves sit this far apart so the stacks never z-fight.
    static let leafGap: CGFloat = 0.00012
    static let leafThickness: CGFloat = 0.0001
    nonisolated static let pageHeightPixels = 1400
    nonisolated private static let renderQueue = DispatchQueue(label: "Cartridge.booklet-pages", qos: .userInitiated)

    var leafCount: Int { leaves.count }

    /// Pages showing now: left (nil when looking at the front cover) and right (nil at the back cover), 1-based.
    var visiblePages: (left: Int?, right: Int?) {
        let total = pages?.pages.count ?? 1
        let left = turned > 0 && 2 * turned - 1 < total ? 2 * turned : nil
        let right = turned < leaves.count && 2 * turned < total ? 2 * turned + 1 : nil
        return (left, right)
    }

    /// A closed booklet showing just its cover until the real pages are loaded.
    init(size: CGSize, cover: CGImage?) {
        self.size = size
        root.name = "booklet"
        root.addChildNode(binding)
        buildLeaves(count: 1)
        if let cover { leaves[0].childNodes.first?.geometry?.materials[0] = Self.paper(cover) }
        layout(animated: false, duration: 0)
    }

    /// Replaces the placeholder with the PDF's pages, sized to the PDF's own proportions.
    func load(pdf: URL, pages: BookletPages) {
        generation += 1
        self.pdf = pdf
        self.pages = pages
        textures = [:]
        requested = []
        size = CGSize(width: size.height * pages.aspect, height: size.height)
        turned = 0
        // Keep showing the cover already on screen until the PDF's first page has rendered.
        let cover = leaves.first?.childNodes.first?.geometry?.materials.first
        buildLeaves(count: max(1, (pages.pages.count + 1) / 2))
        if let cover { leaves[0].childNodes.first?.geometry?.materials[0] = cover }
        layout(animated: false, duration: 0)
        refreshTextures()
    }

    private func buildLeaves(count: Int) {
        leaves.forEach { $0.removeFromParentNode() }
        leaves = (0..<count).map { index in
            let sheet = SCNBox(width: size.width, height: size.height, length: Self.leafThickness, chamferRadius: 0)
            let edge = Self.paper(nil)
            // Faces: +z front page, +x, -z back page, -x, +y, -y.
            sheet.materials = [Self.paper(nil), edge, Self.paper(nil), edge, edge, edge]
            let sheetNode = SCNNode(geometry: sheet)
            sheetNode.position = SCNVector3(size.width / 2, 0, 0)
            sheetNode.name = "leaf-\(index)"
            let pivot = SCNNode()
            pivot.addChildNode(sheetNode)
            binding.addChildNode(pivot)
            return pivot
        }
    }

    private func restingZ(_ index: Int, turned: Bool) -> CGFloat {
        // Unturned leaves stack with the first on top; turned ones with the most recent on top.
        turned ? CGFloat(index + 1) * Self.leafGap : CGFloat(leaves.count - index) * Self.leafGap
    }

    /// Keeps the visible part centred: the cover alone, an open spread, or the back cover alone.
    private var bindingX: CGFloat {
        turned == 0 ? -size.width / 2 : turned == leaves.count ? size.width / 2 : 0
    }

    private func layout(animated: Bool, duration: TimeInterval) {
        for (index, pivot) in leaves.enumerated() {
            let isTurned = index < turned
            pivot.eulerAngles = SCNVector3(0, isTurned ? -CGFloat.pi : 0, 0)
            pivot.position = SCNVector3(0, 0, restingZ(index, turned: isTurned))
        }
        let target = SCNVector3(bindingX, 0, 0)
        if animated {
            let slide = SCNAction.move(to: target, duration: duration)
            slide.timingMode = .easeInEaseOut
            binding.runAction(slide)
        } else {
            binding.position = target
        }
    }

    /// Turns one leaf. Returns false when there is nothing further to turn.
    @discardableResult
    func turn(forward: Bool, duration: TimeInterval) -> Bool {
        guard forward ? turned < leaves.count : turned > 0 else { return false }
        let index = forward ? turned : turned - 1
        let pivot = leaves[index]
        turned += forward ? 1 : -1
        let lifted = CGFloat(leaves.count + 2) * Self.leafGap
        let rotate = SCNAction.rotateTo(x: 0, y: forward ? -CGFloat.pi : 0, z: 0, duration: duration, usesShortestUnitArc: false)
        rotate.timingMode = .easeInEaseOut
        pivot.runAction(.group([
            rotate,
            .sequence([
                .move(to: SCNVector3(0, 0, lifted), duration: duration * 0.2),
                .wait(duration: duration * 0.6),
                .move(to: SCNVector3(0, 0, restingZ(index, turned: forward)), duration: duration * 0.2),
            ]),
        ]))
        let slide = SCNAction.move(to: SCNVector3(bindingX, 0, 0), duration: duration)
        slide.timingMode = .easeInEaseOut
        binding.runAction(slide)
        refreshTextures()
        return true
    }

    /// Shuts the booklet again, all at once.
    func closeAll(duration: TimeInterval) {
        while turned > 0 { turn(forward: false, duration: duration) }
    }

    /// Renders the pages around the current spread and frees the rest.
    private func refreshTextures() {
        guard let pdf, let pages else { return }
        // The front cover stays loaded: it's what shows when the booklet goes back in the case.
        let wanted = Set((2 * turned - 3...2 * turned + 2).filter { $0 >= 0 && $0 < pages.pages.count } + [0])
        for index in textures.keys where !wanted.contains(index) && index != 0 {
            textures[index] = nil
            apply(page: index, image: nil)
        }
        requested = requested.intersection(wanted)
        let current = generation
        for index in wanted.sorted(by: { abs($0 - 2 * turned) < abs($1 - 2 * turned) }) where textures[index] == nil && !requested.contains(index) {
            requested.insert(index)
            let page = pages.pages[index]
            Self.renderQueue.async { [weak self] in
                let image = BookletPages.render(page, of: pdf, height: Self.pageHeightPixels)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == current, self.requested.contains(index), let image else { return }
                        self.textures[index] = image
                        self.apply(page: index, image: image)
                    }
                }
            }
        }
    }

    private func apply(page index: Int, image: CGImage?) {
        let leaf = index / 2
        guard leaves.indices.contains(leaf), let sheet = leaves[leaf].childNodes.first?.geometry else { return }
        sheet.materials[index % 2 == 0 ? 0 : 2] = Self.paper(image)
    }

    static func paper(_ image: CGImage?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image ?? NSColor(white: 0.94, alpha: 1)
        m.roughness.contents = 0.85
        m.metalness.contents = 0.0
        return m
    }
}
