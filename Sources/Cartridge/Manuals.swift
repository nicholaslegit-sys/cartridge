import CoreGraphics
import Foundation

/// Finds scanned instruction booklets in the Internet Archive's manual collections.
enum Manuals {
    enum Source: String {
        case archive = "Internet Archive"
        case museum = "Musée des jeux vidéo"
        case digitalPress = "Digital Press"
    }

    struct Candidate: Identifiable, Hashable {
        enum Location: Hashable {
            /// An archive item, whose PDF is picked from its file list when it's chosen.
            case archiveItem(String)
            case pdf(URL)
        }
        let source: Source
        let title: String
        let location: Location
        let score: Int

        var id: String {
            switch location {
            case .archiveItem(let identifier): "archive:\(identifier)"
            case .pdf(let url): url.absoluteString
            }
        }

        /// Where the booklet came from, for the player to follow.
        var page: String {
            switch location {
            case .archiveItem(let identifier): "https://archive.org/details/\(identifier)"
            case .pdf(let url): url.absoluteString
            }
        }
    }

    /// Words that name a console, per system, as they appear in archive titles and collection names.
    static let platformWords: [System: [String]] = [
        .nes: ["nes", "famicom"], .snes: ["snes", "super nintendo", "super famicom"], .n64: ["n64", "nintendo 64"],
        .gb: ["game boy", "gameboy", "dmg"], .gbc: ["game boy color", "gbc", "cgb"], .gba: ["game boy advance", "gba", "agb"],
        .nds: ["nintendo ds", "nds", "ntr"], .n3ds: ["3ds", "ctr"], .gamecube: ["gamecube", "game cube", "gcn", "dol"],
        .wii: ["wii", "rvl"], .mastersystem: ["master system", "sms"], .genesis: ["genesis", "mega drive", "megadrive"],
        .gamegear: ["game gear", "gamegear"], .saturn: ["saturn"], .dreamcast: ["dreamcast"],
        .ps1: ["playstation 1", "ps1", "psx", "playstationmanuals"], .ps2: ["playstation 2", "ps2", "ps 2"],
        .ps3: ["playstation 3", "ps3"], .ps4: ["playstation 4", "ps4"], .psp: ["psp", "playstation portable"],
        .xbox: ["xbox"], .atari2600: ["atari 2600", "2600", "vcs"], .pce: ["turbografx", "pc engine", "pce"],
    ]

    /// Tokens that describe the document rather than the game.
    static let documentWords: Set<String> = [
        "manual", "manuals", "instruction", "instructions", "booklet", "printable", "game", "games", "the", "a", "of", "and",
        "for", "usa", "us", "ntsc", "pal", "en", "eng", "english", "original", "scan", "scans", "hq", "nintendo", "sony",
        "sega", "microsoft", "playstation", "ps", "ps1", "ps2", "ps3", "ps4", "psx", "psp", "gamecube", "cube", "wii", "xbox",
        "dreamcast", "saturn", "n64", "snes", "nes", "gba", "gbc", "ds", "nds", "genesis", "mega", "drive", "master", "system",
        "gear", "boy", "color", "advance", "atari", "2600", "turbografx", "engine", "pc", "entertainment", "computer",
        "america", "inc", "console", "north", "eur", "europe", "uk", "australia", "world", "rev", "v1", "02",
        // Disc numbers and re-release labels don't make it a different game.
        "disc", "disk", "cd", "dvd", "umd", "greatest", "hits", "platinum", "players", "choice", "best", "classics",
    ]

    /// Words that mean it isn't the manual, or not an English one.
    static let wrongDocument: Set<String> = ["guide", "guides", "strategy", "walkthrough", "magazine", "poster", "catalog", "catalogue", "insert"]
    static let foreignLanguage: Set<String> = [
        "spielanleitung", "anleitung", "emploi", "notice", "istruzioni", "manuale", "instrucciones", "handleiding", "japan", "jpn", "jp",
        "ger", "fre", "fra", "ita", "spa", "france", "germany", "spain", "italy", "brazil", "korea", "china", "asia",
    ]

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// How well an archive item looks like this game's manual. Below zero means it isn't.
    static func score(itemTitle: String, language: String?, collections: [String], gameTitle: String, system: System) -> Int {
        let game = Set(tokens(Detect.title(fromFilename: gameTitle))).subtracting(documentWords)
        let itemWords = tokens(itemTitle)
        let item = Set(itemWords)
        guard !game.isEmpty, item.isDisjoint(with: wrongDocument) else { return -1 }

        var score = 100
        var extras = item.subtracting(game).subtracting(documentWords).subtracting(foreignLanguage)
        if !game.isSubset(of: item) {
            // Some scans squash the name together, like "Halo-CombatEvolvedusa.pdf".
            let gameKey = TitleKey.make(gameTitle), itemKey = TitleKey.make(itemTitle)
            guard gameKey.count >= 5, let range = itemKey.range(of: gameKey) else { return -1 }
            let rest = itemKey.replacingCharacters(in: range, with: "")
            if wrongDocument.contains(where: rest.contains) { return -1 }
            extras = rest.isEmpty || ["usa", "us", "ntsc", "eur", "europe", "pal", "uk"].contains(rest) ? [] : [rest]
        }
        // "Disc 2" numbers a disc, not a sequel.
        let discNumbers = Set(zip(itemWords, itemWords.dropFirst()).filter { ["disc", "disk", "cd"].contains($0.0) }.map(\.1))
        extras.subtract(discNumbers)
        // Extra words are usually a different game: a sequel, a spin-off, a compilation.
        for word in extras {
            if let number = Int(word) {
                // A release year says nothing about which game it is; any other number is probably a sequel.
                if !(1970...2030).contains(number) { score -= 60 }
            } else {
                score -= 50
            }
        }
        let haystack = " " + (itemWords + collections.flatMap(tokens)).joined(separator: " ") + " "
        func mentions(_ phrase: String) -> Bool { haystack.contains(" " + tokens(phrase).joined(separator: " ") + " ") }
        if (platformWords[system] ?? []).contains(where: mentions) {
            score += 20
        } else if platformWords.contains(where: { $0.key != system && $0.value.contains(where: mentions) }) {
            score -= 45
        } else {
            score -= 15
        }
        if let language, !language.isEmpty {
            score += language.lowercased().hasPrefix("en") ? 10 : -45
        }
        if !item.isDisjoint(with: foreignLanguage) { score -= 45 }
        if item.contains("usa") || item.contains("ntsc") { score += 5 }
        return score
    }

    /// The lowest score Cartridge downloads without asking.
    static let confidentScore = 80

    /// Every source at once; a source that fails or has nothing just contributes nothing.
    static func find(title: String, system: System) async -> [Candidate] {
        async let items = (try? archiveSearch(title: title, system: system)) ?? []
        async let collections = (try? archiveCollectionSearch(title: title, system: system)) ?? []
        async let museum = (try? museumSearch(title: title, system: system)) ?? []
        async let press = (try? digitalPressSearch(title: title, system: system)) ?? []
        var seen = Set<String>()
        return (await items + collections + museum + press)
            .sorted { $0.score > $1.score }
            .filter { seen.insert($0.id).inserted }
    }

    static func resolve(_ candidate: Candidate) async throws -> URL {
        switch candidate.location {
        case .pdf(let url):
            return url
        case .archiveItem(let identifier):
            let metadata = URL(string: "https://archive.org/metadata")!.appending(path: identifier)
            guard let pdf = try pickPDF(await Net.data(metadata)) else {
                throw CartridgeError("“\(candidate.title)” on the Internet Archive has no PDF.")
            }
            return downloadURL(identifier: identifier, file: pdf.name)
        }
    }

    /// The console's name as manual sites spell it, so scoring credits the right platform.
    static func platformPhrase(_ system: System) -> [String] {
        Array((platformWords[system] ?? []).prefix(1))
    }

    // MARK: Internet Archive: individual manual items

    static func archiveSearch(title: String, system: System) async throws -> [Candidate] {
        let words = tokens(Detect.title(fromFilename: title)).filter { !documentWords.contains($0) }
        guard !words.isEmpty else { return [] }
        let query = "mediatype:texts AND collection:(manuals OR consolemanuals) AND title:(\(words.map { "\"\($0)\"" }.joined(separator: " AND ")))"
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl[]", value: "identifier"), URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "language"), URLQueryItem(name: "fl[]", value: "collection"),
            URLQueryItem(name: "rows", value: "60"), URLQueryItem(name: "output", value: "json"),
        ]
        return try rank(await Net.data(components.url!), gameTitle: title, system: system)
    }

    // MARK: Internet Archive: whole-console manual collections

    /// Archive items that each hold one console's manuals as individually named PDFs.
    static let archiveCollections: [System: [String]] = [
        .ps1: ["SonyPlaystationManuals"], .ps2: ["SonyPlaystation2Manuals_201812"], .psp: ["SonyPSPManuals", "SonyPSPManualsv1.2"],
        .gamecube: ["NintendoGameCubeManuals"], .wii: ["wii-manuals_202508"], .n64: ["Nintendo64Manuals_201812"],
        .nes: ["NESManuals"], .snes: ["SNESManuals"], .gb: ["NintendoGameBoyManuals"], .gbc: ["NintendoGameBoyColorManuals"],
        .gba: ["NintendoGameBoyAdvanceManuals"], .nds: ["NintendoDSManuals"], .n3ds: ["Nintendo3DSManuals"],
        .xbox: ["MicrosoftXboxManuals"], .dreamcast: ["SEGADreamcastManuals_201812"], .saturn: ["SEGASaturnManuals_201812"],
        .genesis: ["SEGAGenesisMegaDriveManuals"], .mastersystem: ["SEGAMasterSystemManuals"], .gamegear: ["SEGAGameGearManuals"],
        .atari2600: ["Atari2600Manuals_201812"], .pce: ["NECTurboGrafx-16Manuals"],
    ]

    static func archiveCollectionSearch(title: String, system: System) async throws -> [Candidate] {
        var results: [Candidate] = []
        for identifier in archiveCollections[system] ?? [] {
            let metadata = try await Catalog.shared.data(URL(string: "https://archive.org/metadata")!.appending(path: identifier))
            let files = (try JSONDecoder().decode(Metadata.self, from: metadata).files ?? []).map(\.name)
            results += collectionCandidates(files: files, identifier: identifier, gameTitle: title, system: system)
        }
        return results
    }

    static func collectionCandidates(files: [String], identifier: String, gameTitle: String, system: System) -> [Candidate] {
        files.compactMap { name in
            let lower = name.lowercased()
            // The archive's own "_text" copies duplicate the scans.
            guard lower.hasSuffix(".pdf"), !lower.hasSuffix("_text.pdf") else { return nil }
            let stem = (name as NSString).deletingPathExtension
            let score = score(itemTitle: stem, language: nil, collections: platformPhrase(system), gameTitle: gameTitle, system: system)
            return score > 0 ? Candidate(source: .archive, title: stem, location: .pdf(downloadURL(identifier: identifier, file: name)), score: score) : nil
        }
    }

    // MARK: Musée des jeux vidéo

    static let museumBase = URL(string: "https://www.musee-des-jeux-video.com")!
    static let museumSystems: [System: Int] = [
        .nes: 28, .snes: 33, .n64: 29, .gb: 17, .gbc: 143, .gba: 18, .nds: 81, .n3ds: 115, .gamecube: 62, .wii: 93,
        .mastersystem: 23, .genesis: 25, .gamegear: 19, .saturn: 51, .dreamcast: 68, .ps1: 31, .ps2: 80, .ps3: 121,
        .ps4: 114, .psp: 89, .xbox: 59, .atari2600: 76, .pce: 30,
    ]

    struct MuseumGame: Equatable {
        let path: String
        let system: Int
        let title: String
    }

    struct MuseumManual: Equatable {
        let url: URL
        let region: String
        let title: String
    }

    static func museumSearch(title: String, system: System) async throws -> [Candidate] {
        guard let systemID = museumSystems[system] else { return [] }
        let query = Detect.title(fromFilename: title).replacingOccurrences(of: "/", with: " ")
        let search = museumBase.appending(path: "fr").appending(path: "search").appending(path: query).appending(path: "all").appending(path: "all")
        let games = parseMuseumSearch(String(decoding: try await Net.data(search), as: UTF8.self))
            .filter { $0.system == systemID }
            .map { ($0, score(itemTitle: $0.title, language: nil, collections: platformPhrase(system), gameTitle: title, system: system)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        var results: [Candidate] = []
        // A game's page lists its manuals; two pages is plenty and keeps the load on the site light.
        for (game, _) in games.prefix(2) {
            guard let page = URL(string: game.path, relativeTo: museumBase) else { continue }
            for manual in parseMuseumManuals(String(decoding: try await Net.data(page), as: UTF8.self)) {
                let named = "\(manual.title) (\(museumRegions[manual.region] ?? manual.region))"
                let score = score(itemTitle: named, language: nil, collections: platformPhrase(system), gameTitle: title, system: system)
                if score > 0 { results.append(Candidate(source: .museum, title: named, location: .pdf(manual.url), score: score)) }
            }
        }
        return results
    }

    static let museumRegions = ["us": "USA", "eu": "Europe", "uk": "UK", "au": "Australia", "fr": "France", "de": "Germany",
                                "es": "Spain", "it": "Italy", "jp": "Japan", "br": "Brazil", "kr": "Korea", "cn": "China"]

    static func parseMuseumSearch(_ html: String) -> [MuseumGame] {
        html.matches(of: #/href="(/fr/game/[^"]+/(\d+)/2/\d+)" title="Image in-game du jeu (.*?) sur [^"]*"/#).compactMap { match in
            guard let system = Int(match.2) else { return nil }
            return MuseumGame(path: String(match.1), system: system, title: decodeEntities(String(match.3)))
        }
    }

    static func parseMuseumManuals(_ html: String) -> [MuseumManual] {
        var seen = Set<String>()
        return html.matches(of: #/href="(https://www\.musee-des-jeux-video\.com/fr/manual/[^"]+/\d+_([a-z]{2})-([^"/]+)\.pdf)"/#).compactMap { match in
            guard seen.insert(String(match.1)).inserted, let url = URL(string: String(match.1)) else { return nil }
            let title = (String(match.3).removingPercentEncoding ?? String(match.3)).replacingOccurrences(of: "-", with: " ")
            return MuseumManual(url: url, region: String(match.2), title: title)
        }
    }

    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: Digital Press

    static let digitalPressFolders: [System: String] = [
        .nes: "nes", .snes: "snes", .gb: "gameboy", .gbc: "gameboy", .genesis: "genesis", .saturn: "saturn",
        .dreamcast: "dreamcast", .mastersystem: "sms", .atari2600: "atari2600", .pce: "turbografx",
    ]

    static func digitalPressSearch(title: String, system: System) async throws -> [Candidate] {
        guard let folder = digitalPressFolders[system] else { return [] }
        let base = URL(string: "https://www.digitpress.com/library/manuals/")!.appending(path: folder)
        let index = String(decoding: try await Catalog.shared.data(base.appending(path: "index.html")), as: UTF8.self)
        return parseDigitalPress(index).compactMap { file, name in
            let score = score(itemTitle: name, language: nil, collections: platformPhrase(system), gameTitle: title, system: system)
            return score > 0 ? Candidate(source: .digitalPress, title: name, location: .pdf(base.appending(path: file)), score: score) : nil
        }
    }

    static func parseDigitalPress(_ html: String) -> [(file: String, name: String)] {
        html.matches(of: #/(?i)href="([^"/]+\.pdf)"[^>]*>([^<]+)</#).map { (String($0.1), decodeEntities(String($0.2)).trimmingCharacters(in: .whitespaces)) }
    }

    struct SearchResponse: Decodable {
        struct Body: Decodable { let docs: [Doc] }
        struct Doc: Decodable {
            let identifier: String
            let title: String?
            let language: Flexible?
            let collection: Flexible?
        }
        let response: Body
    }

    /// Archive fields come back as either a string or a list of strings.
    struct Flexible: Decodable {
        let values: [String]
        init(from decoder: Decoder) throws {
            if let one = try? String(from: decoder) { values = [one] } else { values = (try? [String](from: decoder)) ?? [] }
        }
    }

    static func rank(_ data: Data, gameTitle: String, system: System) throws -> [Candidate] {
        try JSONDecoder().decode(SearchResponse.self, from: data).response.docs.compactMap { doc in
            guard let title = doc.title else { return nil }
            let score = score(itemTitle: title, language: doc.language?.values.first, collections: doc.collection?.values ?? [], gameTitle: gameTitle, system: system)
            return score > 0 ? Candidate(source: .archive, title: title, location: .archiveItem(doc.identifier), score: score) : nil
        }
        .sorted { $0.score > $1.score }
    }

    struct Metadata: Decodable {
        struct File: Decodable {
            let name: String
            let format: String?
            let source: String?
            let size: String?
        }
        let files: [File]?
    }

    /// The item's scanned PDF: the uploaded original unless it is huge, when the archive's compressed copy loads faster.
    static func pickPDF(_ data: Data) throws -> (name: String, bytes: Int)? {
        let files = (try JSONDecoder().decode(Metadata.self, from: data).files ?? []).filter { $0.name.lowercased().hasSuffix(".pdf") }
        let sized = files.map { (file: $0, bytes: Int($0.size ?? "") ?? 0) }
        let original = sized.filter { $0.file.source == "original" }.max { $0.bytes < $1.bytes }
        let derived = sized.filter { $0.file.source != "original" }.min { $0.bytes < $1.bytes }
        if let original, original.bytes <= 60_000_000 || derived == nil { return (original.file.name, original.bytes) }
        return derived.map { ($0.file.name, $0.bytes) }
    }

    static func downloadURL(identifier: String, file: String) -> URL {
        URL(string: "https://archive.org/download")!.appending(path: identifier).appending(path: file)
    }

    static func searchPage(title: String) -> URL {
        var components = URLComponents(string: "https://archive.org/search")!
        components.queryItems = [URLQueryItem(name: "query", value: "\(Detect.title(fromFilename: title)) manual")]
        return components.url!
    }
}

/// The pages of a booklet as they are read, from a PDF whose pages may be single pages or scanned two-page spreads.
struct BookletPages {
    enum Half: Equatable { case whole, left, right }

    struct Page: Equatable {
        let pdfIndex: Int
        let half: Half
    }

    let pages: [Page]
    /// Width over height of one page.
    let aspect: CGFloat

    /// Landscape PDF pages are spreads and become two pages. A landscape first page is a cover wrap: its right half
    /// is the front cover and its left half the back, which goes last.
    init(pageSizes: [CGSize]) {
        var pages: [Page] = []
        var backCover: Page?
        var aspects: [CGFloat] = []
        for (index, size) in pageSizes.enumerated() where size.width > 0 && size.height > 0 {
            if size.width > size.height * 1.15 {
                if index == 0 {
                    pages.append(Page(pdfIndex: 0, half: .right))
                    backCover = Page(pdfIndex: 0, half: .left)
                } else {
                    pages += [Page(pdfIndex: index, half: .left), Page(pdfIndex: index, half: .right)]
                }
                aspects.append(size.width / 2 / size.height)
            } else {
                pages.append(Page(pdfIndex: index, half: .whole))
                aspects.append(size.width / size.height)
            }
        }
        if let backCover { pages.append(backCover) }
        self.pages = pages
        let sorted = aspects.sorted()
        aspect = sorted.isEmpty ? 0.7 : min(max(sorted[sorted.count / 2], 0.4), 1.2)
    }

    /// Renders one page at `height` pixels. Opens its own document, so it is safe on any thread.
    static func render(_ page: Page, of url: URL, height: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let pdfPage = document.page(at: page.pdfIndex + 1) else { return nil }
        var box = pdfPage.getBoxRect(.cropBox)
        if pdfPage.rotationAngle % 180 != 0 { box.size = CGSize(width: box.height, height: box.width) }
        guard box.width > 0, box.height > 0 else { return nil }
        let fullWidth = Int((CGFloat(height) * box.width / box.height).rounded())
        let full = ShelfArt.canvas(CGFloat(fullWidth), CGFloat(height)) { ctx, rect in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(rect)
            ctx.interpolationQuality = .high
            // getDrawingTransform never scales up, and scanned booklets are often small in PDF units, so place the
            // page by hand: centre it, undo the page's own rotation, and scale it to fill the height.
            let raw = pdfPage.getBoxRect(.cropBox)
            let angle = CGFloat(pdfPage.rotationAngle)
            let scale = pdfPage.rotationAngle % 180 == 0 ? rect.height / raw.height : rect.height / raw.width
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -angle * .pi / 180)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -raw.midX, y: -raw.midY)
            ctx.clip(to: raw)
            ctx.drawPDFPage(pdfPage)
        }
        switch page.half {
        case .whole: return full
        case .left: return full.cropping(to: CGRect(x: 0, y: 0, width: full.width / 2, height: full.height))
        case .right: return full.cropping(to: CGRect(x: full.width / 2, y: 0, width: full.width - full.width / 2, height: full.height))
        }
    }

    static func pageSizes(of url: URL) -> [CGSize]? {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return nil }
        return (1...document.numberOfPages).map { index in
            guard let page = document.page(at: index) else { return .zero }
            let box = page.getBoxRect(.cropBox)
            return page.rotationAngle % 180 != 0 ? CGSize(width: box.height, height: box.width) : box.size
        }
    }
}

/// Remembers big catalogue files (whole-console file lists, site indexes) for the rest of the session.
actor Catalog {
    static let shared = Catalog()
    private var cache: [URL: Data] = [:]

    func data(_ url: URL) async throws -> Data {
        if let cached = cache[url] { return cached }
        let data = try await Net.data(url)
        cache[url] = data
        return data
    }
}
