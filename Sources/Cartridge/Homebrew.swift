import Foundation

/// A game from Homebrew Hub (hh.gbdev.io): free, author-distributed homebrew for Game Boy, GBC, GBA and NES.
struct HomebrewEntry: Decodable, Identifiable, Hashable {
    struct File: Hashable {
        let filename: String
        let isDefault: Bool
        let playable: Bool
    }

    let slug: String
    let title: String
    let platform: String
    let developer: String?
    let license: String?
    let summary: String?
    let screenshots: [String]
    let files: [File]
    let tags: [String]
    let basepath: String
    let website: URL?

    var id: String { slug }

    var system: System? {
        ["GB": .gb, "GBC": .gbc, "GBA": .gba, "NES": .nes][platform]
    }

    /// The author's default ROM, else the first playable one, else anything with a ROM extension.
    var romFile: File? {
        let roms: Set = ["gb", "gbc", "cgb", "gba", "nes", "zip"]
        return files.first { $0.isDefault && $0.playable }
            ?? files.first { $0.playable }
            ?? files.first { roms.contains(($0.filename as NSString).pathExtension.lowercased()) }
    }

    func fileURL(_ name: String) -> URL? {
        URL(string: "https://hh3.gbdev.io/static")?
            .appending(path: basepath).appending(path: "entries").appending(path: slug).appending(path: name)
    }

    var screenshotURLs: [URL] { screenshots.compactMap(fileURL) }

    enum CodingKeys: String, CodingKey {
        case slug, title, platform, developer, license, description, screenshots, files, tags, basepath, gameWebsite
    }

    private struct RawFile: Decodable {
        let filename: String
        let `default`: Bool?
        let playable: Bool?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        // The slug becomes a folder name under Games, so one that could lead out of it drops the entry.
        guard !slug.isEmpty, !slug.contains("/"), slug != ".", slug != ".." else {
            throw DecodingError.dataCorruptedError(forKey: .slug, in: c, debugDescription: "Unsafe slug")
        }
        title = try c.decode(String.self, forKey: .title)
        platform = try c.decode(String.self, forKey: .platform)
        basepath = try c.decode(String.self, forKey: .basepath)
        // The database stores developers as a string, a list, or an object.
        if let name = try? c.decode(String.self, forKey: .developer) {
            developer = name
        } else if let names = try? c.decode([String].self, forKey: .developer) {
            developer = names.joined(separator: ", ")
        } else {
            developer = nil
        }
        license = try? c.decode(String.self, forKey: .license)
        summary = try? c.decode(String.self, forKey: .description)
        screenshots = (try? c.decode([String].self, forKey: .screenshots)) ?? []
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        // Only web links: a file:// or app-scheme link would open something on this Mac when clicked.
        website = (try? c.decode(String.self, forKey: .gameWebsite)).flatMap(URL.init(string:))
            .flatMap { ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil }
        files = ((try? c.decode([Lenient<RawFile>].self, forKey: .files)) ?? []).compactMap(\.value).map {
            File(filename: $0.filename, isDefault: $0.default ?? false, playable: $0.playable ?? false)
        }
    }
}

struct HomebrewPage: Decodable {
    let results: Int
    let page_total: Int
    let page_current: Int
    let entries: [Lenient<HomebrewEntry>]
}

/// Decodes what it can and skips the rest, so one odd entry doesn't blank a whole page.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

@MainActor @Observable
final class HomebrewStore {
    static let platforms = [("GB", "Game Boy"), ("GBC", "Game Boy Color"), ("GBA", "Game Boy Advance"), ("NES", "NES")]

    var platform = "GB"
    var query = ""
    private(set) var entries: [HomebrewEntry] = []
    private(set) var loading = false
    private(set) var hasMore = true
    private(set) var error: String?
    @ObservationIgnored private var page = 0
    @ObservationIgnored private var generation = 0

    func reload() async {
        generation += 1
        entries = []
        page = 0
        hasMore = true
        error = nil
        loading = false
        await loadMore()
    }

    func loadMore() async {
        guard !loading, hasMore else { return }
        let started = generation
        loading = true
        defer { if started == generation { loading = false } }
        do {
            let search = query.trimmingCharacters(in: .whitespaces)
            var found: [HomebrewEntry] = []
            var more = false
            if search.isEmpty {
                let result = try await Self.fetch(platform: platform, title: nil, page: page + 1)
                found = result.entries.compactMap(\.value)
                more = result.page_current < result.page_total
            } else {
                // Title matching on the server is case-sensitive, so ask for the common spellings.
                for variant in Self.spellings(of: search) {
                    for p in 1...2 {
                        let result = try await Self.fetch(platform: platform, title: variant, page: p)
                        found += result.entries.compactMap(\.value)
                        if result.page_current >= result.page_total { break }
                    }
                }
            }
            guard started == generation else { return }
            page += 1
            hasMore = more
            for entry in found where !entries.contains(where: { $0.slug == entry.slug }) {
                entries.append(entry)
            }
        } catch {
            guard started == generation else { return }
            self.error = error.localizedDescription
            hasMore = false
        }
    }

    nonisolated static func spellings(of text: String) -> [String] {
        var seen: [String] = []
        for variant in [text, text.capitalized, text.lowercased(), text.uppercased()] where !seen.contains(variant) {
            seen.append(variant)
        }
        return seen
    }

    nonisolated static func fetch(platform: String, title: String?, page: Int) async throws -> HomebrewPage {
        var components = URLComponents(string: "https://hh3.gbdev.io/api/search")!
        components.queryItems = [URLQueryItem(name: "platform", value: platform), URLQueryItem(name: "page", value: String(page))]
        if let title { components.queryItems?.append(URLQueryItem(name: "title", value: title)) }
        return try JSONDecoder().decode(HomebrewPage.self, from: try await Net.data(components.url!))
    }
}
