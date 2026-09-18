import Foundation
import Security
import SQLite3

/// Every picture Cartridge keeps for a game, beyond its screenshots.
enum ArtKind: String, CaseIterable, Identifiable {
    case front, back, spine, full, disc, title, logo, fanart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .spine: "Spine"
        case .full: "Full Cover"
        case .disc: "Disc"
        case .title: "Title Screen"
        case .logo: "Logo"
        case .fanart: "Fanart"
        }
    }

    /// LaunchBox image types for this kind, best first.
    var launchBoxTypes: [String] {
        switch self {
        case .front: ["Box - Front", "Box - Front - Reconstructed", "Fanart - Box - Front", "Cart - Front"]
        case .back: ["Box - Back", "Box - Back - Reconstructed"]
        case .spine: ["Box - Spine"]
        case .full: ["Box - Full"]
        case .disc: ["Disc"]
        case .title: ["Screenshot - Game Title"]
        case .logo: ["Clear Logo"]
        case .fanart: ["Fanart - Background"]
        }
    }
}

extension Game {
    func artFile(_ kind: ArtKind) -> URL {
        switch kind {
        case .front: artURL
        case .title: labelArtURL
        default: Paths.art.appendingPathComponent("\(id.uuidString)-\(kind.rawValue).png")
        }
    }

    func screenshotFile(_ index: Int) -> URL {
        Paths.art.appendingPathComponent("\(id.uuidString)-shot\(index).png")
    }
}

/// Reduces a title to what survives differences in punctuation, region tags and article placement.
enum TitleKey {
    static func make(_ title: String) -> String {
        var t = Detect.title(fromFilename: title)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        if t.hasPrefix("the ") { t.removeFirst(4) }
        t = t.replacingOccurrences(of: ", the", with: "")
        return String(String.UnicodeScalarView(t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}

// MARK: - SQLite

final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String, readOnly: Bool = false) throws {
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw CartridgeError("Couldn't open the artwork database: \(message)")
        }
    }

    deinit { sqlite3_close(handle) }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return Statement(statement, db: self)
    }

    func rows(_ sql: String, _ args: [Any?] = [], _ each: (Statement) -> Void) throws {
        let statement = try prepare(sql)
        try statement.bind(args)
        while sqlite3_step(statement.handle) == SQLITE_ROW { each(statement) }
    }

    fileprivate func error() -> CartridgeError {
        CartridgeError("Artwork database error: \(String(cString: sqlite3_errmsg(handle)))")
    }

    final class Statement {
        fileprivate let handle: OpaquePointer
        private let db: SQLiteDB
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        fileprivate init(_ handle: OpaquePointer, db: SQLiteDB) {
            self.handle = handle
            self.db = db
        }

        deinit { sqlite3_finalize(handle) }

        func bind(_ args: [Any?]) throws {
            sqlite3_reset(handle)
            for (i, arg) in args.enumerated() {
                let index = Int32(i + 1)
                let result: Int32
                switch arg {
                case let value as Int: result = sqlite3_bind_int64(handle, index, Int64(value))
                case let value as String: result = sqlite3_bind_text(handle, index, value, -1, Self.transient)
                default: result = sqlite3_bind_null(handle, index)
                }
                guard result == SQLITE_OK else { throw db.error() }
            }
        }

        func run(_ args: [Any?]) throws {
            try bind(args)
            guard sqlite3_step(handle) == SQLITE_DONE else { throw db.error() }
        }

        func int(_ column: Int32) -> Int? {
            sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(handle, column))
        }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(handle, column).map { String(cString: $0) }
        }
    }
}

// MARK: - LaunchBox Games Database

struct LBGame: Identifiable, Hashable {
    let id: Int
    let name: String
    let platform: String
    let year: Int?
    let overview: String?
    let developer: String?
    let publisher: String?
    let genres: String?
    var video: String? = nil
}

struct LBImage: Hashable {
    let file: String
    let type: String
    let region: String?

    var url: URL { URL(string: "https://images.launchbox-app.com/")!.appending(path: file) }
}

enum LaunchBox {
    static let dumpURL = URL(string: "https://gamesdb.launchbox-app.com/Metadata.zip")!

    static let platforms: [System: String] = [
        .nes: "Nintendo Entertainment System", .snes: "Super Nintendo Entertainment System", .n64: "Nintendo 64",
        .gb: "Nintendo Game Boy", .gbc: "Nintendo Game Boy Color", .gba: "Nintendo Game Boy Advance",
        .nds: "Nintendo DS", .n3ds: "Nintendo 3DS", .gamecube: "Nintendo GameCube", .wii: "Nintendo Wii",
        .mastersystem: "Sega Master System", .genesis: "Sega Genesis", .gamegear: "Sega Game Gear",
        .saturn: "Sega Saturn", .dreamcast: "Sega Dreamcast", .ps1: "Sony Playstation", .ps2: "Sony Playstation 2",
        .ps3: "Sony Playstation 3", .ps4: "Sony Playstation 4", .psp: "Sony PSP", .xbox: "Microsoft Xbox",
        .atari2600: "Atari 2600", .pce: "NEC TurboGrafx-16",
    ]

    static var folder: URL { Paths.root.appendingPathComponent("Metadata", isDirectory: true) }
    static var databaseFile: URL { folder.appendingPathComponent("launchbox.sqlite") }

    static let regionPreference = ["North America", "United States", "", "World", "Canada", "United Kingdom", "Europe", "Australia", "Japan"]

    /// The best image of each kind, keeping to the front cover's region where it can, plus up to six gameplay screenshots.
    static func pick(_ images: [LBImage]) -> (art: [ArtKind: LBImage], screenshots: [LBImage]) {
        func rank(_ image: LBImage, preferring region: String?) -> Int {
            let r = image.region ?? ""
            if let region, r == region { return -1 }
            return regionPreference.firstIndex(of: r) ?? regionPreference.count
        }
        func best(_ types: [String], preferring region: String?) -> LBImage? {
            for type in types {
                let candidates = images.filter { $0.type == type }
                if let found = candidates.min(by: { rank($0, preferring: region) < rank($1, preferring: region) }) { return found }
            }
            return nil
        }
        var art: [ArtKind: LBImage] = [:]
        art[.front] = best(ArtKind.front.launchBoxTypes, preferring: nil)
        let region = art[.front]?.region
        for kind in ArtKind.allCases where kind != .front {
            art[kind] = best(kind.launchBoxTypes, preferring: region)
        }
        let shots = images.filter { $0.type == "Screenshot - Gameplay" }
            .sorted { rank($0, preferring: region) < rank($1, preferring: region) }
        return (art, Array(shots.prefix(6)))
    }

    /// Streams Metadata.xml into a SQLite index holding only the platforms and image types Cartridge uses.
    static func buildIndex(xml: URL, into destination: URL) throws -> Int {
        let temp = destination.deletingLastPathComponent().appendingPathComponent("launchbox-building.sqlite")
        try? FileManager.default.removeItem(at: temp)
        let db = try SQLiteDB(path: temp.path)
        try db.exec("""
            PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;
            CREATE TABLE games(id INTEGER PRIMARY KEY, name TEXT, key TEXT, platform TEXT, year INTEGER, overview TEXT, developer TEXT, publisher TEXT, genres TEXT, video TEXT);
            CREATE TABLE names(id INTEGER, name TEXT, key TEXT);
            CREATE TABLE images(id INTEGER, file TEXT, type TEXT, region TEXT);
            BEGIN;
            """)
        guard let stream = InputStream(url: xml) else { throw CartridgeError("Couldn't read \(xml.lastPathComponent)") }
        let indexer = try LaunchBoxIndexer(db: db)
        let parser = XMLParser(stream: stream)
        parser.delegate = indexer
        guard parser.parse() else {
            throw CartridgeError("The LaunchBox database couldn't be read: \(parser.parserError?.localizedDescription ?? "unknown error")")
        }
        if let failure = indexer.failure { throw failure }
        try db.exec("""
            COMMIT;
            CREATE INDEX games_key ON games(platform, key);
            CREATE INDEX names_key ON names(key);
            CREATE INDEX images_id ON images(id);
            """)
        let count = indexer.gameCount
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return count
    }
}

/// SAX handler for Metadata.xml: <LaunchBox> holds flat <Game>, <GameAlternateName> and <GameImage> records.
final class LaunchBoxIndexer: NSObject, XMLParserDelegate {
    private let insertGame: SQLiteDB.Statement
    private let insertName: SQLiteDB.Statement
    private let insertImage: SQLiteDB.Statement
    private let wantedPlatforms = Set(LaunchBox.platforms.values)
    private let wantedTypes = Set(ArtKind.allCases.flatMap(\.launchBoxTypes) + ["Screenshot - Gameplay"])
    private var keptIDs = Set<Int>()
    private var depth = 0
    private var record: String?
    private var fields: [String: String] = [:]
    private var text = ""
    private(set) var gameCount = 0
    private(set) var failure: Error?

    init(db: SQLiteDB) throws {
        insertGame = try db.prepare("INSERT OR REPLACE INTO games VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        insertName = try db.prepare("INSERT INTO names VALUES (?, ?, ?)")
        insertImage = try db.prepare("INSERT INTO images VALUES (?, ?, ?, ?)")
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if depth == 2 {
            record = name
            fields = [:]
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth == 3 { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        if depth == 3 {
            fields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        guard depth == 2, let record, let id = fields["DatabaseID"].flatMap(Int.init) else { return }
        do {
            switch record {
            case "Game":
                guard let platform = fields["Platform"], wantedPlatforms.contains(platform), let title = fields["Name"] else { return }
                let year = fields["ReleaseYear"].flatMap(Int.init) ?? fields["ReleaseDate"].flatMap { Int($0.prefix(4)) }
                try insertGame.run([id, title, TitleKey.make(title), platform, year, fields["Overview"], fields["Developer"], fields["Publisher"], fields["Genres"], fields["VideoURL"]])
                keptIDs.insert(id)
                gameCount += 1
            case "GameAlternateName":
                guard keptIDs.contains(id), let alternate = fields["AlternateName"] ?? fields["Name"] else { return }
                try insertName.run([id, alternate, TitleKey.make(alternate)])
            case "GameImage":
                guard keptIDs.contains(id), let file = fields["FileName"], let type = fields["Type"], wantedTypes.contains(type) else { return }
                try insertImage.run([id, file, type, fields["Region"]])
            default:
                return
            }
        } catch {
            failure = error
            parser.abortParsing()
        }
    }
}

/// Read side of the LaunchBox index.
final class LaunchBoxDB {
    private let db: SQLiteDB
    private let columns: String

    init(file: URL) throws {
        db = try SQLiteDB(path: file.path, readOnly: true)
        // Indexes built before trailers were added have no video column; read them without it.
        var hasVideo = false
        try db.rows("PRAGMA table_info(games)") { if $0.text(1) == "video" { hasVideo = true } }
        columns = "g.id, g.name, g.platform, g.year, g.overview, g.developer, g.publisher, g.genres, \(hasVideo ? "g.video" : "NULL")"
    }

    private func game(_ s: SQLiteDB.Statement) -> LBGame {
        LBGame(id: s.int(0) ?? 0, name: s.text(1) ?? "", platform: s.text(2) ?? "", year: s.int(3),
               overview: s.text(4), developer: s.text(5), publisher: s.text(6), genres: s.text(7), video: s.text(8))
    }

    func game(_ id: Int) -> LBGame? {
        var found: LBGame?
        try? db.rows("SELECT \(columns) FROM games g WHERE g.id = ?1", [id]) { found = game($0) }
        return found
    }

    /// An exact title match on the game's platform, by main or alternate name.
    func match(_ title: String, system: System) -> LBGame? {
        guard let platform = LaunchBox.platforms[system] else { return nil }
        let key = TitleKey.make(title)
        guard !key.isEmpty else { return nil }
        var found: LBGame?
        try? db.rows("""
            SELECT \(columns) FROM games g WHERE g.platform = ?1 AND g.key = ?2
            UNION SELECT \(columns) FROM names n JOIN games g ON g.id = n.id WHERE g.platform = ?1 AND n.key = ?2
            ORDER BY 1 LIMIT 1
            """, [platform, key]) { found = game($0) }
        return found
    }

    func search(_ text: String, system: System?) -> [LBGame] {
        let key = TitleKey.make(text)
        guard !key.isEmpty else { return [] }
        let platform = system.flatMap { LaunchBox.platforms[$0] }
        var results: [LBGame] = []
        try? db.rows("""
            SELECT DISTINCT \(columns) FROM games g LEFT JOIN names n ON n.id = g.id
            WHERE (?1 IS NULL OR g.platform = ?1) AND (g.key LIKE ?2 OR n.key LIKE ?2)
            ORDER BY (g.key = ?3) DESC, length(g.name) LIMIT 40
            """, [platform, "%\(key)%", key]) { results.append(game($0)) }
        return results
    }

    func images(_ id: Int) -> [LBImage] {
        var images: [LBImage] = []
        try? db.rows("SELECT file, type, region FROM images WHERE id = ?1", [id]) { s in
            if let file = s.text(0), let type = s.text(1) { images.append(LBImage(file: file, type: type, region: s.text(2))) }
        }
        return images
    }
}

// MARK: - YouTube

enum YouTube {
    /// The 11-character video id from any of YouTube's URL shapes, or a bare id.
    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isID = { (s: Substring) in s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
        if isID(Substring(trimmed)) { return trimmed }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(),
              host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value, isID(Substring(v)) {
            return v
        }
        let parts = url.path.split(separator: "/")
        if host == "youtu.be", let first = parts.first, isID(first) { return String(first) }
        if parts.count >= 2, ["embed", "v", "shorts", "live"].contains(parts[0]), isID(parts[1]) { return String(parts[1]) }
        return nil
    }
}

// MARK: - IGDB

struct IGDBGame: Decodable, Identifiable, Hashable {
    struct Image: Decodable, Hashable { let image_id: String }
    struct Named: Decodable, Hashable { let name: String }
    struct Involvement: Decodable, Hashable {
        let company: Named?
        let developer: Bool?
        let publisher: Bool?
    }

    let id: Int
    let name: String
    let first_release_date: Int?
    let summary: String?
    let cover: Image?
    let screenshots: [Image]?
    let artworks: [Image]?
    let genres: [Named]?
    let involved_companies: [Involvement]?
    let videos: [Video]?

    struct Video: Decodable, Hashable { let video_id: String }

    var year: Int? {
        first_release_date.map { Calendar(identifier: .gregorian).component(.year, from: Date(timeIntervalSince1970: TimeInterval($0))) }
    }

    func companies(developer: Bool) -> String? {
        let names = (involved_companies ?? []).filter { (developer ? $0.developer : $0.publisher) == true }.compactMap { $0.company?.name }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

/// IGDB's v4 API, authenticated as the player's own Twitch developer application.
actor IGDB {
    static let platformIDs: [System: Int] = [
        .nes: 18, .snes: 19, .n64: 4, .gb: 33, .gbc: 22, .gba: 24, .nds: 20, .n3ds: 37, .gamecube: 21, .wii: 5,
        .mastersystem: 64, .genesis: 29, .gamegear: 35, .saturn: 32, .dreamcast: 23, .ps1: 7, .ps2: 8, .ps3: 9,
        .ps4: 48, .psp: 38, .xbox: 11, .atari2600: 59, .pce: 86,
    ]

    static let fields = "name,first_release_date,summary,cover.image_id,screenshots.image_id,artworks.image_id,genres.name,involved_companies.company.name,involved_companies.developer,involved_companies.publisher,videos.video_id"

    let clientID: String
    private let secret: String
    private var token: (value: String, expires: Date)?

    init(clientID: String, secret: String) {
        self.clientID = clientID
        self.secret = secret
    }

    static func imageURL(_ imageID: String, size: String) -> URL {
        URL(string: "https://images.igdb.com/igdb/image/upload/t_\(size)/\(imageID).jpg")!
    }

    /// IGDB's query language quotes strings with double quotes; drop anything that could break out of one.
    static func searchQuery(_ title: String, system: System?) -> String {
        let cleaned = Detect.title(fromFilename: title).filter { $0 != "\"" && $0 != "\\" && $0 != ";" }
        var query = "search \"\(cleaned)\"; fields \(fields);"
        if let platform = system.flatMap({ platformIDs[$0] }) { query += " where platforms = (\(platform));" }
        return query + " limit 20;"
    }

    func search(_ title: String, system: System?) async throws -> [IGDBGame] {
        try await post("games", body: Self.searchQuery(title, system: system))
    }

    /// Twitch takes these as form fields. Sending the secret in the body instead of the URL keeps it out of the
    /// places URLs end up: proxy logs, crash reports and anything that records a request line.
    static func tokenRequest(clientID: String, secret: String) -> URLRequest {
        var request = Net.request(URL(string: "https://id.twitch.tv/oauth2/token")!, method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: secret),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
        ]
        // A "+" is legal in a query but means a space in a form body, so it has to be escaped here.
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private func accessToken(refresh: Bool) async throws -> String {
        if !refresh, let token, token.expires > Date() { return token.value }
        let (data, response) = try await URLSession.shared.data(for: Self.tokenRequest(clientID: clientID, secret: secret))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CartridgeError("Twitch didn't accept the IGDB Client ID and Secret. Check them in Settings → Artwork.")
        }
        struct Token: Decodable { let access_token: String; let expires_in: Int }
        let decoded = try JSONDecoder().decode(Token.self, from: data)
        // Renew a minute early rather than race the expiry.
        token = (decoded.access_token, Date().addingTimeInterval(TimeInterval(decoded.expires_in - 60)))
        return decoded.access_token
    }

    private func post<T: Decodable>(_ endpoint: String, body: String, refreshToken: Bool = false, retried: Bool = false) async throws -> T {
        var request = Net.request(URL(string: "https://api.igdb.com/v4/\(endpoint)")!, method: "POST")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(try await accessToken(refresh: refreshToken))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Only an expired token is worth a new one. Asking Twitch for another while being rate-limited by IGDB just
        // adds a request to the pile.
        if status == 401, !retried { return try await post(endpoint, body: body, refreshToken: true, retried: true) }
        if status == 429, !retried {
            // Four requests a second is the limit; wait and try once more.
            try await Task.sleep(for: .milliseconds(600))
            return try await post(endpoint, body: body, refreshToken: refreshToken, retried: true)
        }
        guard status == 200 else { throw CartridgeError("IGDB answered HTTP \(status)") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Keychain

enum Keychain {
    static let service = "app.cartridge.launcher"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw CartridgeError("Couldn't save to the Keychain (\(status))") }
    }
}

// MARK: - Sources state

@MainActor @Observable
final class ArtworkSources {
    enum LaunchBoxState: Equatable {
        case missing, downloading(Double), indexing, ready(games: Int, updated: Date)
    }

    private(set) var launchBox: LaunchBoxState = .missing
    private(set) var launchBoxError: String?
    @ObservationIgnored private(set) var launchBoxDB: LaunchBoxDB?
    var igdbClientID: String {
        didSet { UserDefaults.standard.set(igdbClientID, forKey: "igdbClientID") }
    }
    private(set) var hasIGDBSecret: Bool
    @ObservationIgnored private var igdbClient: IGDB?

    static let secretAccount = "igdb-client-secret"

    init() {
        igdbClientID = UserDefaults.standard.string(forKey: "igdbClientID") ?? ""
        hasIGDBSecret = Keychain.get(Self.secretAccount) != nil
        openLaunchBox()
    }

    var igdbConfigured: Bool { !igdbClientID.trimmingCharacters(in: .whitespaces).isEmpty && hasIGDBSecret }

    var igdb: IGDB? {
        guard igdbConfigured, let secret = Keychain.get(Self.secretAccount) else { return nil }
        let id = igdbClientID.trimmingCharacters(in: .whitespaces)
        if let client = igdbClient, client.clientID == id { return client }
        igdbClient = IGDB(clientID: id, secret: secret)
        return igdbClient
    }

    func setIGDBSecret(_ secret: String) throws {
        try Keychain.set(secret.trimmingCharacters(in: .whitespaces), for: Self.secretAccount)
        hasIGDBSecret = Keychain.get(Self.secretAccount) != nil
        igdbClient = nil
    }

    private func openLaunchBox() {
        let file = LaunchBox.databaseFile
        guard FileManager.default.fileExists(atPath: file.path), let db = try? LaunchBoxDB(file: file) else {
            launchBoxDB = nil
            launchBox = .missing
            return
        }
        launchBoxDB = db
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        var count = 0
        try? SQLiteDB(path: file.path, readOnly: true).rows("SELECT count(*) FROM games") { count = $0.int(0) ?? 0 }
        launchBox = .ready(games: count, updated: attributes?[.modificationDate] as? Date ?? Date())
    }

    var isBusy: Bool {
        switch launchBox {
        case .downloading, .indexing: true
        default: false
        }
    }

    /// Downloads LaunchBox's public metadata dump (about 100 MB) and indexes it. Keeps the old index if anything fails.
    func installLaunchBox() async {
        guard !isBusy else { return }
        launchBoxError = nil
        launchBox = .downloading(0)
        do {
            let folder = try Paths.ensure(LaunchBox.folder)
            let zip = folder.appendingPathComponent("Metadata.zip")
            let xml = folder.appendingPathComponent("Metadata.xml")
            defer {
                try? FileManager.default.removeItem(at: zip)
                try? FileManager.default.removeItem(at: xml)
            }
            try await Net.download(LaunchBox.dumpURL, to: zip) { [weak self] value in
                Task { @MainActor in
                    if case .downloading = self?.launchBox { self?.launchBox = .downloading(value) }
                }
            }
            launchBox = .indexing
            try await Shell.run("/usr/bin/unzip", ["-o", "-q", zip.path, "Metadata.xml", "-d", folder.path])
            let destination = LaunchBox.databaseFile
            _ = try await Task.detached { try LaunchBox.buildIndex(xml: xml, into: destination) }.value
            openLaunchBox()
        } catch {
            // Whatever was installed before is still on disk and still usable.
            openLaunchBox()
            if !Library.isCancellation(error) { launchBoxError = error.localizedDescription }
        }
    }

    func removeLaunchBox() {
        launchBoxDB = nil
        try? FileManager.default.removeItem(at: LaunchBox.databaseFile)
        launchBox = .missing
    }
}
