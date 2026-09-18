import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            ConsolePicker()
                .tabItem { Label("Consoles", systemImage: "gamecontroller") }
            GamesFolderStep()
                .tabItem { Label("Games", systemImage: "folder") }
            BiosStep()
                .tabItem { Label("BIOS", systemImage: "memorychip") }
            AchievementsSettings()
                .tabItem { Label("Achievements", systemImage: "trophy") }
            ArtworkSettings()
                .tabItem { Label("Artwork", systemImage: "photo.on.rectangle.angled") }
            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            CreditsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 620)
    }
}

struct ArtworkSettings: View {
    @Environment(Library.self) private var library
    @State private var secret = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var artwork = library.artwork
        Form {
            Section("LaunchBox Games Database") {
                Text("Front and back covers, spines, full wraps, disc scans, title screens and gameplay screenshots. Cartridge downloads LaunchBox's public database once (about 100 MB) and keeps a small index of the consoles it supports. Images download per game.")
                    .font(.callout).foregroundStyle(.secondary)
                switch artwork.launchBox {
                case .missing:
                    Button("Download Database (100 MB)") { Task { await artwork.installLaunchBox() } }
                case .downloading(let progress):
                    ProgressView(value: progress) { Text("Downloading…") }
                case .indexing:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Indexing games and images…")
                    }
                case .ready(let games, let updated):
                    LabeledContent("Installed", value: "\(games.formatted()) games · \(updated.formatted(date: .abbreviated, time: .omitted))")
                    HStack {
                        Button("Update") { Task { await artwork.installLaunchBox() } }
                        Button("Remove", role: .destructive) { artwork.removeLaunchBox() }
                    }
                }
                if let error = artwork.launchBoxError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("IGDB") {
                Text("Covers, screenshots and artwork from IGDB, which needs a free Twitch developer application. Register one (any name, OAuth redirect http://localhost, category Application Integration), then paste its Client ID and a Client Secret here. The secret is kept in your Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                Link("Open the Twitch Developer Console", destination: URL(string: "https://dev.twitch.tv/console/apps")!)
                TextField("Client ID", text: $artwork.igdbClientID)
                SecureField(artwork.hasIGDBSecret ? "Client Secret (saved — type to replace)" : "Client Secret", text: $secret)
                HStack {
                    Button("Save Secret") {
                        do {
                            try artwork.setIGDBSecret(secret)
                            secret = ""
                            testResult = nil
                        } catch {
                            testResult = error.localizedDescription
                        }
                    }
                    .disabled(secret.isEmpty)
                    Button("Test Connection") { test() }
                        .disabled(!artwork.igdbConfigured || testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if let testResult {
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("The Cover Project") {
                Text("The Cover Project has no API and puts a bot check in front of its site, so Cartridge doesn't download from it automatically. Open a game's details, choose “Find on The Cover Project”, download the scan you like and drop it on the Full Cover slot — the 3D case wraps it around the front, spine and back.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func test() {
        guard let igdb = library.artwork.igdb else { return }
        testing = true
        testResult = nil
        Task {
            do {
                let results = try await igdb.search("Halo", system: .xbox)
                testResult = "Connected. A test search found \(results.count) result\(results.count == 1 ? "" : "s")."
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

struct CreditsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Form {
            Section("Cartridge") {
                LabeledContent("Author", value: About.author)
                Link("Source on GitHub", destination: About.repository)
            }
            Section {
                Toggle("Demo Mode", isOn: Binding(get: { library.demoMode }, set: { library.setDemoMode($0) }))
                    .disabled(!library.sessions.isEmpty)
            } footer: {
                Text(library.sessions.isEmpty
                     ? "Shows a sample library of well-known games to try the shelf with. Your own library is kept as it is and comes back when you turn this off."
                     : "Quit the game that's running to switch.")
            }
            Section {
                ForEach(ShelfModels.credits, id: \.title) { credit in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(credit.title, destination: credit.url)
                        Text("by \(credit.author) · \(credit.license)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Modelled on")
            } footer: {
                Text("The bookcase, cases and discs are drawn in code; these models were the reference.")
            }
            Section("Artwork and data") {
                Link("LaunchBox Games Database", destination: URL(string: "https://gamesdb.launchbox-app.com")!)
                Link("IGDB", destination: URL(string: "https://www.igdb.com")!)
                Link("libretro thumbnails", destination: URL(string: "https://thumbnails.libretro.com")!)
                Link("Homebrew Hub", destination: URL(string: "https://hh.gbdev.io")!)
            }
        }
        .formStyle(.grouped)
    }
}

/// The art slots, screenshots and lookup buttons in a game's inspector.
struct ArtworkPanel: View {
    let game: Game
    @Environment(Library.self) private var library

    static let slots: [ArtKind] = [.front, .back, .spine, .full, .disc, .title, .logo, .fanart]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Artwork").font(.headline)
                Spacer()
                Button("Find Artwork…") { library.searchingArtwork = game }
                    .controlSize(.small)
            }
            if game.artChecked, !FileManager.default.fileExists(atPath: game.artURL.path) {
                HStack {
                    Label("No artwork found for this title.", systemImage: "photo.badge.exclamationmark")
                        .font(.callout)
                    Spacer()
                    Button("Search Sources…") { library.searchingArtwork = game }
                }
                .padding(10)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(Self.slots) { kind in
                    ArtSlot(game: game, kind: kind)
                }
            }
            let shots = library.screenshots(for: game)
            if !shots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(shots, id: \.self) { url in
                            if let image = NSImage(contentsOf: url) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
            }
            ManualRow(game: game)
            Button("Find on The Cover Project") {
                var components = URLComponents(string: "https://www.thecoverproject.net/view.php")!
                components.queryItems = [URLQueryItem(name: "searchstring", value: game.title)]
                if let url = components.url { NSWorkspace.shared.open(url) }
            }
            .controlSize(.small)
            Text("Drop an image on a slot to use it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ArtSlot: View {
    let game: Game
    let kind: ArtKind
    @Environment(Library.self) private var library
    @State private var targeted = false

    var body: some View {
        let image = library.image(for: game, kind)
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6))
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(2)
                } else {
                    Image(systemName: "plus").foregroundStyle(.tertiary)
                }
            }
            .frame(height: 64)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 2))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            } isTargeted: { targeted = $0 }
            .contextMenu {
                Button("Choose File…") { choose() }
                if image != nil {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.artFile(kind)]) }
                    Button("Remove", role: .destructive) { library.removeArt(kind, for: game) }
                }
            }
            Text(kind.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .help("Drop an image here, or right-click to choose one")
    }

    private func load(_ url: URL) {
        Task {
            do {
                let data = url.isFileURL ? try Data(contentsOf: url) : try await Net.data(url)
                try library.setArt(data, kind: kind, for: game)
            } catch {
                library.error = "Couldn't use that image: \(error.localizedDescription)"
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose the \(kind.label.lowercased()) image for \(game.title)"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
}

struct FindArtworkSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case launchBox = "LaunchBox", igdb = "IGDB", libretro = "libretro"
        var id: String { rawValue }
    }

    let game: Game
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .launchBox
    @State private var query = ""
    @State private var everyConsole = false
    @State private var launchBoxResults: [LBGame] = []
    @State private var igdbResults: [IGDBGame] = []
    @State private var libretroResults: [String] = []
    @State private var selection: Int?
    @State private var searching = false
    @State private var applying = false
    @State private var message: String?

    private var available: Bool {
        switch source {
        case .launchBox: library.artwork.launchBoxDB != nil
        case .igdb: library.artwork.igdbConfigured
        case .libretro: game.system.thumbnailSet != nil
        }
    }

    private var noResults: Bool {
        switch source {
        case .launchBox: launchBoxResults.isEmpty
        case .igdb: igdbResults.isEmpty
        case .libretro: libretroResults.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Artwork for \(game.title)").font(.title3.bold())
            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if available {
                HStack {
                    TextField("Title", text: $query).onSubmit(search)
                    if source != .libretro { Toggle("Every console", isOn: $everyConsole) }
                    Button("Search", action: search).disabled(searching)
                }
                List(selection: $selection) {
                    if source == .launchBox {
                        ForEach(launchBoxResults) { result in
                            ResultRow(
                                title: result.name, detail: [result.platform, result.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                thumbnail: library.artwork.launchBoxDB.flatMap { LaunchBox.pick($0.images(result.id)).art[.front]?.url }
                            )
                            .tag(result.id)
                        }
                    } else if source == .libretro {
                        ForEach(Array(libretroResults.prefix(200).enumerated()), id: \.offset) { index, name in
                            ResultRow(title: name, detail: game.system.name,
                                      thumbnail: Library.thumbnailURL(game.system, name: name))
                            .tag(index)
                        }
                    } else {
                        ForEach(igdbResults) { result in
                            ResultRow(
                                title: result.name, detail: result.year.map(String.init) ?? "",
                                thumbnail: result.cover.map { IGDB.imageURL($0.image_id, size: "cover_small") }
                            )
                            .tag(result.id)
                        }
                    }
                }
                .overlay {
                    if searching {
                        ProgressView()
                    } else if noResults {
                        ContentUnavailableView.search(text: query)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(source == .launchBox ? "LaunchBox database not installed" : "IGDB isn't set up", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text(source == .launchBox ? "Download it once in Settings → Artwork." : "Add a Twitch Client ID and Secret in Settings → Artwork.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
                .frame(maxHeight: .infinity)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text(source == .libretro
                     ? "libretro has box fronts and title screens, named after the No-Intro and Redump dump lists."
                     : "Replaces this game's artwork with the match's. Slots the match doesn't have are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Use Artwork", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || applying)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .onAppear {
            // A title that picked up a duplicate suffix ("… Game 2") searches as the file's clean name.
            let fromFile = Detect.title(fromFilename: game.url.deletingPathExtension().lastPathComponent)
            query = game.title.hasPrefix(fromFile) ? fromFile : game.title
            if library.artwork.launchBoxDB == nil, library.artwork.igdbConfigured { source = .igdb }
            search()
        }
        .onChange(of: source) { search() }
        .onChange(of: everyConsole) { search() }
    }

    private func search() {
        selection = nil
        message = nil
        let system = everyConsole ? nil : game.system
        switch source {
        case .launchBox:
            launchBoxResults = library.artwork.launchBoxDB?.search(query, system: system) ?? []
        case .libretro:
            searching = true
            let text = query
            Task {
                do {
                    libretroResults = try await library.searchLibretro(text, system: game.system)
                } catch {
                    libretroResults = []
                    message = error.localizedDescription
                }
                searching = false
            }
        case .igdb:
            guard let igdb = library.artwork.igdb else { return }
            searching = true
            let text = query
            Task {
                do {
                    igdbResults = try await igdb.search(text, system: system)
                } catch {
                    igdbResults = []
                    message = error.localizedDescription
                }
                searching = false
            }
        }
    }

    private func apply() {
        guard let selection else { return }
        applying = true
        Task {
            do {
                if source == .libretro, libretroResults.indices.contains(selection) {
                    try await library.applyLibretro(libretroResults[selection], to: game.id)
                } else if source == .launchBox, let match = launchBoxResults.first(where: { $0.id == selection }) {
                    try await library.applyLaunchBox(match, to: game.id, overwrite: true)
                } else if let match = igdbResults.first(where: { $0.id == selection }) {
                    try await library.applyIGDB(match, to: game.id, overwrite: true)
                }
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            applying = false
        }
    }
}

private struct ResultRow: View {
    let title: String
    let detail: String
    let thumbnail: URL?

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: thumbnail)
                .frame(width: 44, height: 56)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The game's instruction booklet: whether one is saved, and ways to get or replace it.
struct ManualRow: View {
    let game: Game
    @Environment(Library.self) private var library

    var body: some View {
        let saved = FileManager.default.fileExists(atPath: game.manualURL.path)
        HStack(spacing: 8) {
            Image(systemName: saved ? "book.closed.fill" : "book.closed").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Instruction Booklet").font(.callout)
                Text(detail(saved: saved)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Menu {
                if !saved {
                    Button("Find Online") { Task { _ = await library.manual(for: game.id) } }
                }
                let matches = library.manualCandidates[game.id] ?? []
                if !matches.isEmpty {
                    Menu("Possible Matches") {
                        ForEach(matches.prefix(15)) { match in
                            Button("\(match.title) — \(match.source.rawValue)") { Task { await library.useManual(match, for: game.id) } }
                        }
                    }
                }
                Button("Choose PDF…") { choose() }
                Button("Search the Internet Archive in Browser") { NSWorkspace.shared.open(Manuals.searchPage(title: game.title)) }
                if saved {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.manualURL]) }
                    Button("Remove", role: .destructive) { library.removeManual(for: game) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func detail(saved: Bool) -> String {
        switch library.manualStatus[game.id] {
        case .searching: return "Searching manual archives…"
        case .downloading(let progress): return "Downloading… \(Int(progress * 100))%"
        case .failed(let message): return message
        case nil: return saved ? "Saved — open it from the case on the Game Shelf" : "Not downloaded yet"
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose the instruction booklet for \(game.title)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.setManual(url, for: game) } catch { library.error = error.localizedDescription }
    }
}
