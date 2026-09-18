import SwiftUI

struct SystemBadge: View {
    let system: System
    var compact = false

    var body: some View {
        Text(system.short)
            .font(.system(size: compact ? 8 : 10, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, compact ? 3 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .frame(minWidth: compact ? 30 : nil)
            .background(system.color, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ArtView: View {
    let game: Game
    @Environment(Library.self) private var library

    var body: some View {
        if let image = library.image(for: game) {
            ZStack {
                Rectangle().fill(.black.opacity(0.85))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(game.pixelArt ? .none : .high)
                    .aspectRatio(contentMode: .fit)
            }
        } else {
            ZStack {
                LinearGradient(colors: [game.system.color, game.system.color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 6) {
                    Text(game.system.short)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(game.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                }
            }
        }
    }
}

struct GameGridView: View {
    let title: String
    let games: [Game]
    var emptyText = "Drop game files or folders here, or add them from disk."
    /// Turn the selected game's cover into its trailer after a moment.
    var playsTrailers = false

    @Environment(Library.self) private var library
    @State private var selection: UUID?
    @State private var search = ""

    private var filtered: [Game] {
        search.isEmpty ? games : games.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var selectedGame: Game? {
        library.games.first { $0.id == selection }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 18, alignment: .top)], spacing: 20) {
                ForEach(filtered) { game in
                    GameCard(game: game, selected: selection == game.id)
                        // One gesture reading AppKit's click count: a separate count-2 gesture lost the second click
                        // once the first one opened the inspector. Only a game already selected plays, so a grid that
                        // reflowed under the pointer can't start its neighbour.
                        .onTapGesture {
                            if NSApp.currentEvent?.clickCount == 2, selection == game.id { library.requestPlay(game) }
                            selection = game.id
                        }
                        .contextMenu { GameMenu(game: game) }
                }
            }
            .padding(20)
        }
        .overlay {
            if games.isEmpty {
                ContentUnavailableView {
                    Label("No games here yet", systemImage: "opticaldisc")
                } description: {
                    Text(emptyText)
                } actions: {
                    Button("Add Games…") { library.isPickingFiles = true }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle(title)
        .searchable(text: $search, placement: .toolbar, prompt: "Search games")
        .toolbar {
            if !library.unpacking.isEmpty {
                ToolbarItem {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Unpacking \(library.unpacking.count)…").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if !library.copying.isEmpty {
                ToolbarItem {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Copying \(library.copying.count)…").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let progress = library.dumpProgress {
                ToolbarItem {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking \(progress.done)/\(progress.total)").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem {
                if let progress = library.artworkProgress {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Artwork \(progress.done)/\(progress.total)").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Fetch Missing Artwork", systemImage: "photo.stack") {
                        Task { await library.fetchMissingArtwork() }
                    }
                    .help("Look up covers, discs and screenshots for games that are missing them")
                }
            }
            ToolbarItem {
                Button("Add Games", systemImage: "plus") { library.isPickingFiles = true }
            }
        }
        .inspector(isPresented: Binding(get: { selectedGame != nil }, set: { if !$0 { selection = nil } })) {
            if let game = selectedGame {
                GameInspector(game: game, playsTrailers: playsTrailers)
                    .inspectorColumnWidth(min: 270, ideal: 300, max: 380)
            }
        }
    }
}

struct GameCard: View {
    let game: Game
    let selected: Bool
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtView(game: game)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if library.sessions[game.id] != nil {
                        Label("Playing", systemImage: "gamecontroller.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay {
                    if let status = library.status[game.id] {
                        ZStack {
                            Rectangle().fill(.black.opacity(0.55))
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(.white)
                                Text(status).font(.caption.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                            }
                            .padding(8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .shadow(color: .black.opacity(selected ? 0.35 : 0.18), radius: selected ? 8 : 3, y: 2)
            Text(game.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                SystemBadge(system: game.system)
                if !FileManager.default.fileExists(atPath: game.path) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("The game file is missing")
                }
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.16) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct GameMenu: View {
    let game: Game
    @Environment(Library.self) private var library

    var body: some View {
        if library.sessions[game.id] != nil {
            Button("Quit Game") { library.stop(game) }
        } else {
            Button("Play") { library.requestPlay(game) }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
        Button("Check Game File") { Task { await library.checkDumpReporting(game.id) } }
            .disabled(library.checkingDump.contains(game.id))
        Button("Search Artwork…") { library.searchingArtwork = game }
        Divider()
        Button(game.managed ? "Remove and Move Files to Trash" : "Remove from Library", role: .destructive) {
            library.remove(game)
        }
    }
}

struct PlayControls: View {
    let game: Game
    @Environment(Library.self) private var library
    @Environment(Installer.self) private var installer

    private var progress: Double? {
        installer.jobs[game.system.emulator.rawValue] ?? game.system.core.flatMap { installer.jobs["core:\($0)"] }
    }

    var body: some View {
        if library.sessions[game.id] != nil {
            HStack {
                Label("Playing", systemImage: "gamecontroller.fill").foregroundStyle(.green).font(.headline)
                Spacer()
                Button("Quit Game") { library.stop(game) }
            }
        } else if let status = library.status[game.id] {
            VStack(alignment: .leading, spacing: 6) {
                Text(status).font(.callout)
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
        } else {
            Button {
                library.requestPlay(game)
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

struct GameInspector: View {
    let game: Game
    var playsTrailers = false
    @Environment(Library.self) private var library
    @Environment(Installer.self) private var installer
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmingRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CoverWithTrailer(game: game, playsTrailers: playsTrailers)

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title).font(.title2.bold()).textSelection(.enabled)
                    Text([game.system.name, game.releaseYear.map(String.init), game.developer].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if let genres = game.genres, !genres.isEmpty {
                        Text(genres).font(.caption).foregroundStyle(.secondary)
                    }
                }

                PlayControls(game: game)

                if let note = game.system.setupNote {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                GameTweaksSection(game: game)

                if let overview = game.overview, !overview.isEmpty {
                    OverviewText(text: overview)
                }

                ArtworkPanel(game: game)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    row("Emulator", "\(game.system.emulator.name)\(installer.installedVersion(game.system.emulator).map { " \($0)" } ?? " (not installed)")")
                    row("Last played", game.lastPlayed.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                    row("Play time", Duration.seconds(game.playSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    if let publisher = game.publisher { row("Publisher", publisher) }
                    row("Added", game.added.formatted(date: .abbreviated, time: .omitted))
                    row("Location", game.managed ? "Cartridge library" : "In place")
                }
                .font(.callout)

                DumpRow(game: game)

                Picker("System", selection: Binding(get: { game.system }, set: { library.setSystem(game, $0) })) {
                    SystemPickerItems()
                }

                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
                    Button("Rename…") {
                        newTitle = game.title
                        renaming = true
                    }
                }
                Button("Remove from Library…", role: .destructive) { confirmingRemove = true }
            }
            .padding(16)
        }
        .alert("Rename Game", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") { library.rename(game, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(game.title)?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { library.remove(game) }
        } message: {
            Text(game.managed ? "Its files in Cartridge's library move to the Trash." : "The game's files stay where they are.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(2)
        }
    }
}

struct SystemPickerItems: View {
    var body: some View {
        ForEach(System.makers, id: \.self) { maker in
            Section(maker) {
                ForEach(System.allCases.filter { $0.maker == maker }) { system in
                    Text(system.name).tag(system)
                }
            }
        }
    }
}

struct ImportSheet: View {
    @Environment(Library.self) private var library
    @Environment(AppSetup.self) private var setup
    @AppStorage("copyOnImport") private var copy = true

    private var ready: Int { library.pending.filter { $0.system != nil }.count }

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 14) {
            Text(library.pending.count == 1 ? "Add 1 Item" : "Add \(library.pending.count) Items")
                .font(.title2.bold())
            Text("Check the system Cartridge picked for each one. Items without a system are skipped.")
                .foregroundStyle(.secondary)

            List {
                ForEach($library.pending) { $item in
                    HStack(spacing: 10) {
                        Image(systemName: Detect.isDirectory(item.url) ? "folder.fill" : "doc.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Picker("System", selection: $item.system) {
                            Text("Choose…").tag(System?.none)
                            // The consoles the player said they run come first; the rest stay reachable below.
                            if !setup.consoles.isEmpty {
                                Section("Your Consoles") {
                                    ForEach(setup.chosen) { system in
                                        Text(system.name).tag(System?.some(system))
                                    }
                                }
                            }
                            ForEach(System.makers, id: \.self) { maker in
                                let systems = System.allCases.filter { $0.maker == maker && !setup.consoles.contains($0) }
                                if !systems.isEmpty {
                                    Section(maker) {
                                        ForEach(systems) { system in
                                            Text(system.name).tag(System?.some(system))
                                        }
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        Button {
                            library.discardPending([item])
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Don't add this")
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 240)

            Toggle("Copy into Cartridge's library", isOn: $copy)
            Text(copy
                 ? "Files are copied to \(Paths.games.path), together with the track files a .cue, .gdi or .m3u needs."
                 : "Games stay where they are. Moving or renaming them later breaks the link.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { library.discardPending(library.pending) }
                    .keyboardShortcut(.cancelAction)
                Button(ready == 1 ? "Add 1 Game" : "Add \(ready) Games") {
                    Task { await library.importPending(copy: copy) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ready == 0)
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}


struct OverviewText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.callout)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
            Button(expanded ? "Less" : "More") { expanded.toggle() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}
