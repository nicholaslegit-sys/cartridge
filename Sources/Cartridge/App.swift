import SwiftUI

@main
struct CartridgeApp: App {
    @State private var library = Library()
    @State private var store = HomebrewStore()
    @State private var setup = AppSetup()
    @State private var bios = BiosStore()
    @State private var update = AppUpdate()

    var body: some Scene {
        Window("Cartridge", id: "main") {
            RootView()
                .environment(library)
                .environment(library.installer)
                .environment(library.saves)
                .environment(store)
                .environment(setup)
                .environment(bios)
                .environment(update)
                .frame(minWidth: 980, minHeight: 620)
                // Kept out here rather than inside RootView so it doesn't compete with the import sheet.
                // A sheet is hosted in its own window and doesn't inherit what was handed to the view presenting
                // it, so everything it reads has to be passed in again.
                .sheet(isPresented: Binding(get: { setup.isShowing }, set: { setup.isShowing = $0 })) {
                    SetupSheet()
                        .environment(library)
                        .environment(library.installer)
                        .environment(library.saves)
                        .environment(store)
                        .environment(setup)
                        .environment(bios)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cartridge") { About.show() }
                Button("Check for Updates…") { Task { await update.check(userAsked: true) } }
                    .disabled(update.checking)
                Button("Setup…") { setup.isShowing = true }
            }
            CommandGroup(after: .newItem) {
                Button("Scan Games Folder") { Task { await library.scanGamesFolderAndReport() } }
                    .disabled(library.scanning)
                Button("Fetch Missing Artwork") { Task { await library.fetchMissingArtwork() } }
                    .disabled(library.artworkProgress != nil)
                Button("Check All Game Files") { Task { await library.checkAllDumps() } }
                    .disabled(library.dumpProgress != nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Games…") { library.isPickingFiles = true }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(library)
                .environment(library.installer)
                .environment(library.saves)
                .environment(setup)
                .environment(bios)
        }
    }
}

/// The standard About panel, with the author, the CC licences we owe attribution for, and the source.
enum About {
    static let author = "Nicholas Seymour"
    static let repository = URL(string: "https://github.com/nicholaslegit-sys/cartridge")!

    static func show() {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: "By \(author)\n\n", attributes: [.font: body])
        func link(_ text: String, _ url: URL) {
            credits.append(NSAttributedString(string: text, attributes: [.font: body, .link: url]))
        }
        link("Source on GitHub", repository)
        credits.append(NSAttributedString(string: "\n\nModelled on", attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]))
        for credit in ShelfModels.credits {
            credits.append(NSAttributedString(string: "\n", attributes: [.font: body]))
            link(credit.title, credit.url)
            credits.append(NSAttributedString(string: " by \(credit.author), \(credit.license)", attributes: [.font: body]))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}

enum Page: Hashable {
    case shelf, all, recent, system(System), store, emulators, bios, saves, controllers
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(AppUpdate.self) private var update
    @Environment(AppSetup.self) private var setup
    @Environment(BiosStore.self) private var bios
    @SceneStorage("page") private var storedPage = "shelf"
    @State private var page: Page? = .shelf
    @State private var dropTargeted = false

    /// Systems with games in them. A console the player didn't pick still shows up once it has a game, so importing
    /// something unexpected never hides it.
    private var systemsInLibrary: [System] {
        System.allCases.filter { system in library.games.contains { $0.system == system } }
    }

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            List(selection: $page) {
                Section("Library") {
                    Label("Game Shelf", systemImage: "books.vertical").tag(Page.shelf)
                    Label("All Games", systemImage: "square.grid.2x2").badge(library.games.count).tag(Page.all)
                    Label("Recently Played", systemImage: "clock").tag(Page.recent)
                }
                if !systemsInLibrary.isEmpty {
                    Section("Systems") {
                        ForEach(systemsInLibrary) { system in
                            HStack(spacing: 8) {
                                // A fixed column keeps every console's name starting at the same place, however
                                // wide its badge is.
                                SystemBadge(system: system, compact: true)
                                    .frame(width: 36, alignment: .leading)
                                Text(system.name)
                            }
                            .badge(library.games.filter { $0.system == system }.count)
                            .tag(Page.system(system))
                        }
                    }
                }
                Section("Get Games") {
                    Label("Homebrew Store", systemImage: "bag").tag(Page.store)
                }
                Section("Setup") {
                    Label("Emulators", systemImage: "cpu").tag(Page.emulators)
                    Label("BIOS Files", systemImage: "memorychip")
                        .badge(bios.missing(for: setup.biosNeeded).count)
                        .tag(Page.bios)
                    Label("Controllers", systemImage: "gamecontroller").tag(Page.controllers)
                    Label("Saves", systemImage: "externaldrive.badge.timemachine").tag(Page.saves)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                if let available = update.available {
                    Link(destination: available.page) {
                        Label("Cartridge \(available.version) is out", systemImage: "arrow.down.circle.fill")
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .help("Open the release page")
                }
            }
        } detail: {
            switch page ?? .all {
            case .shelf:
                ShelfScreen()
            case .all:
                GameGridView(title: "All Games", games: library.games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, playsTrailers: true)
            case .recent:
                GameGridView(
                    title: "Recently Played",
                    games: library.games.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! },
                    emptyText: "Games you play show up here."
                )
            case .system(let system):
                GameGridView(title: system.name, games: library.games.filter { $0.system == system }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            case .store:
                StoreView()
            case .emulators:
                EmulatorsView()
            case .bios:
                BiosStep()
                    .navigationTitle("BIOS Files")
            case .saves:
                SavesView()
            case .controllers:
                ControllersView()
            }
        }
        .fileImporter(isPresented: $library.isPickingFiles, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.review(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            library.review(files)
            return !files.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: Binding(get: { !library.pending.isEmpty }, set: { if !$0 { library.discardPending(library.pending) } })) {
            ImportSheet()
        }
        .modifier(PlayPrompts(page: $page))
        .modifier(Reports())
        .onAppear { page = Page(storage: storedPage) }
        .task { await update.check() }
        .onChange(of: page) { _, new in storedPage = new?.storage ?? "all" }
    }
}

/// What pressing Play can ask first: downloading an emulator, or a BIOS it can't find.
private struct PlayPrompts: ViewModifier {
    @Binding var page: Page?
    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content
            .alert("Download what's needed?", isPresented: Binding(get: { library.confirmingPlay != nil }, set: { if !$0 { library.confirmingPlay = nil } }), presenting: library.confirmingPlay) { game in
                Button("Download & Play") { Task { await library.play(game) } }
                Button("Cancel", role: .cancel) {}
            } message: { game in
                Text("\(game.title) runs in \(game.system.emulator.name). Cartridge will download \(library.needsDownload(game).joined(separator: " and ")).")
            }
            .alert("BIOS needed", isPresented: Binding(get: { library.missingBios != nil }, set: { if !$0 { library.missingBios = nil } }), presenting: library.missingBios) { prompt in
                Button("Open BIOS Files") { page = .bios }
                // Someone who set the BIOS up inside the emulator, somewhere Cartridge doesn't look, can go ahead.
                Button("Play Anyway") { library.requestPlay(prompt.game, skippingBiosCheck: true) }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                Text("\(prompt.game.system.emulator.name) can't start \(prompt.game.system.name) games without the \(prompt.requirement.name), and there isn't one where it looks. Add the one from your own console in BIOS Files - Cartridge checks it and puts it in the right place.")
            }
    }
}

/// The results of things the player started from a menu, and errors.
private struct Reports: ViewModifier {
    @Environment(Library.self) private var library
    @Environment(AppUpdate.self) private var update

    func body(content: Content) -> some View {
        content
            .alert("Software update", isPresented: Binding(get: { update.report != nil }, set: { if !$0 { update.report = nil } })) {
                if let available = update.available {
                    Link("Open Release Page", destination: available.page)
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(update.report ?? "")
            }
            .sheet(item: Binding(get: { library.searchingArtwork }, set: { library.searchingArtwork = $0 })) { game in
                // A sheet is its own window and doesn't inherit the environment.
                FindArtworkSheet(game: game).environment(library)
            }
            .alert("Artwork", isPresented: Binding(get: { library.artworkReport != nil }, set: { if !$0 { library.artworkReport = nil } })) {
                if let game = library.artworkReport?.missing {
                    Button("Search Sources…") {
                        // Opening a sheet while the alert is still closing gets dropped.
                        Task { try? await Task.sleep(for: .milliseconds(300)); library.searchingArtwork = game }
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.artworkReport?.text ?? "")
            }
            .alert("Game files checked", isPresented: Binding(get: { library.dumpReport != nil }, set: { if !$0 { library.dumpReport = nil } })) {
                Button("OK") {}
            } message: {
                Text(library.dumpReport ?? "")
            }
            .alert("Games folder scanned", isPresented: Binding(get: { library.scanReport != nil }, set: { if !$0 { library.scanReport = nil } })) {
                Button("OK") {}
            } message: {
                Text(library.scanReport ?? "")
            }
            .alert("Something went wrong", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } }), presenting: library.error) { _ in
                Button("OK") {}
            } message: { Text($0) }
    }
}

extension Page {
    var storage: String {
        switch self {
        case .shelf: "shelf"
        case .all: "all"
        case .recent: "recent"
        case .system(let s): "system:\(s.rawValue)"
        case .store: "store"
        case .emulators: "emulators"
        case .bios: "bios"
        case .saves: "saves"
        case .controllers: "controllers"
        }
    }

    init(storage: String) {
        switch storage {
        case "shelf": self = .shelf
        case "recent": self = .recent
        case "store": self = .store
        case "emulators": self = .emulators
        case "bios": self = .bios
        case "saves": self = .saves
        case "controllers": self = .controllers
        default:
            if storage.hasPrefix("system:"), let system = System(rawValue: String(storage.dropFirst(7))) {
                self = .system(system)
            } else {
                self = storage == "all" ? .all : .shelf
            }
        }
    }
}
