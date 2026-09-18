import SwiftUI

/// Loads images through Net so requests carry Cartridge's User-Agent (some hosts refuse anonymous clients).
struct RemoteImage: View {
    let url: URL?
    var pixelated = false
    @State private var image: NSImage?
    @State private var failed = false

    static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(pixelated ? .none : .high)
                    .aspectRatio(contentMode: .fit)
            } else if failed || url == nil {
                Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            failed = false
            guard let url else { image = nil; return }
            if let cached = Self.cache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            image = nil
            do {
                let data = try await Net.data(url)
                guard let loaded = NSImage(data: data) else { failed = true; return }
                Self.cache.setObject(loaded, forKey: url as NSURL)
                image = loaded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

struct StoreView: View {
    @Environment(HomebrewStore.self) private var store
    @State private var detail: HomebrewEntry?

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free homebrew").font(.largeTitle.bold())
                    Text("New games made by independent developers for Game Boy, Game Boy Advance and NES, shared through Homebrew Hub. Each one downloads straight from hh.gbdev.io.")
                        .foregroundStyle(.secondary)
                }

                Picker("Platform", selection: $store.platform) {
                    ForEach(HomebrewStore.platforms, id: \.0) { id, name in
                        Text(name).tag(id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)

                if let error = store.error, store.entries.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't reach Homebrew Hub", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await store.reload() } }
                    }
                } else if store.entries.isEmpty, !store.loading {
                    ContentUnavailableView.search(text: store.query)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 18, alignment: .top)], spacing: 20) {
                    ForEach(store.entries) { entry in
                        StoreCard(entry: entry)
                            .onTapGesture { detail = entry }
                    }
                }

                HStack {
                    Spacer()
                    if store.loading {
                        ProgressView()
                    } else if store.hasMore, !store.entries.isEmpty {
                        Button("Load More") { Task { await store.loadMore() } }
                    }
                    Spacer()
                }
                .padding(.bottom, 10)
            }
            .padding(24)
        }
        .navigationTitle("Homebrew Store")
        .searchable(text: $store.query, placement: .toolbar, prompt: "Search titles")
        .onSubmit(of: .search) { Task { await store.reload() } }
        .onChange(of: store.platform) { Task { await store.reload() } }
        .onChange(of: store.query) { _, query in
            if query.isEmpty { Task { await store.reload() } }
        }
        .task {
            if store.entries.isEmpty { await store.reload() }
        }
        .sheet(item: $detail) { entry in
            StoreDetail(entry: entry)
        }
    }
}

struct StoreCard: View {
    let entry: HomebrewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: entry.screenshotURLs.first, pixelated: true)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(entry.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                if let system = entry.system { SystemBadge(system: system) }
                Text(entry.developer ?? "Unknown developer")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            GetButton(entry: entry)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct GetButton: View {
    let entry: HomebrewEntry
    @Environment(Library.self) private var library

    var body: some View {
        if let game = library.games.first(where: { $0.homebrewSlug == entry.slug }) {
            Button {
                library.requestPlay(game)
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else if let progress = library.downloads[entry.slug] {
            ProgressView(value: progress).frame(height: 22)
        } else {
            Button {
                Task { await library.installHomebrew(entry) }
            } label: {
                Label("Get", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(entry.romFile == nil)
        }
    }
}

struct StoreDetail: View {
    let entry: HomebrewEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(entry.screenshotURLs, id: \.self) { url in
                        RemoteImage(url: url, pixelated: true)
                            .frame(width: 300, height: 220)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
            .background(.black.opacity(0.9))
            .frame(height: entry.screenshotURLs.isEmpty ? 0 : 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title).font(.largeTitle.bold())
                        if let system = entry.system { SystemBadge(system: system) }
                    }
                    Text(entry.developer ?? "Unknown developer").foregroundStyle(.secondary)
                    GetButton(entry: entry).frame(maxWidth: 220)
                    if let summary = entry.summary {
                        Text(summary).textSelection(.enabled)
                    }
                    if !entry.tags.isEmpty {
                        Text(entry.tags.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        if let license = entry.license { Label(license, systemImage: "doc.text") }
                        if let website = entry.website { Link("Game website", destination: website) }
                    }
                    .font(.callout)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 620)
    }
}

struct EmulatorsView: View {
    @Environment(Installer.self) private var installer
    @Environment(AppSetup.self) private var setup
    @State private var showingAll = false

    /// Only the emulators the chosen consoles need, so the page isn't a wall of things nobody asked for.
    private var shown: [EmulatorID] {
        showingAll ? EmulatorID.allCases : setup.emulators
    }

    var body: some View {
        List {
            Section {
                Text("Cartridge downloads an emulator from its official source the first time you play a game that needs it, or you can install them here. BIOS and firmware files never come from Cartridge: dump them from consoles you own.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { id in
                EmulatorRow(id: id)
            }
            if !showingAll, shown.count < EmulatorID.allCases.count {
                Button("Show the other \(EmulatorID.allCases.count - shown.count) emulators") { showingAll = true }
                    .buttonStyle(.link)
            }
        }
        .navigationTitle("Emulators")
        .toolbar {
            ToolbarItem {
                if installer.checking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check for Updates", systemImage: "arrow.clockwise") {
                        Task { await installer.checkForUpdates() }
                    }
                }
            }
        }
        .task {
            if installer.latest.isEmpty { await installer.checkForUpdates() }
        }
    }
}

struct EmulatorRow: View {
    let id: EmulatorID
    @Environment(Installer.self) private var installer
    @Environment(Library.self) private var library
    @State private var pickingFirmware = false
    @State private var confirmingUninstall = false

    var body: some View {
        let executable = installer.executable(id)
        let version = installer.installedVersion(id)
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let executable, id.binaryName == nil {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: executable.path))
                        .resizable()
                } else {
                    Image(systemName: "cpu").font(.system(size: 26)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(id.name).font(.headline)
                    statusCapsule(installed: executable != nil, version: version)
                }
                Text(id.systems.map(\.name).joined(separator: ", "))
                    .font(.callout)
                Text("From \(id.source)")
                    .font(.caption).foregroundStyle(.secondary)
                if id == .retroarch {
                    let cores = Array(Set(id.systems.compactMap(\.core))).sorted()
                    Text(cores.map { installer.hasCore($0) ? "\($0) ✓" : $0 }.joined(separator: "  ·  "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let progress = installer.jobs[id.rawValue] {
                    HStack {
                        ProgressView(value: progress)
                        Button("Cancel") { installer.cancel(id.rawValue) }.controlSize(.small)
                    }
                }
                if let error = installer.checkErrors[id] {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Spacer()

            if installer.jobs[id.rawValue] == nil {
                HStack {
                    if executable == nil {
                        Button("Install") { perform { try await installer.install(id) } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        if installer.updateAvailable(id), let latest = installer.latest[id] {
                            Button("Update to \(latest.version)") { perform { try await installer.install(id) } }
                                .buttonStyle(.borderedProminent)
                        }
                        if id.binaryName == nil {
                            Button("Open") {
                                if let executable { NSWorkspace.shared.openApplication(at: executable, configuration: .init()) }
                            }
                        }
                        Menu {
                            Button("Show in Finder") {
                                if let executable { NSWorkspace.shared.activateFileViewerSelecting([executable]) }
                            }
                            if id == .rpcs3 {
                                Button("Install PS3 System Software…") { pickingFirmware = true }
                                Link("Get PS3UPDAT.PUP from playstation.com", destination: URL(string: "https://www.playstation.com/en-us/support/hardware/ps3/system-software/")!)
                            }
                            if id == .retroarch {
                                Button("Open BIOS Folder") {
                                    if let folder = try? Paths.ensure(Paths.retroArchSystem) { NSWorkspace.shared.open(folder) }
                                }
                            }
                            Divider()
                            Button("Reinstall") { perform { try await installer.install(id) } }
                            Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .fileImporter(isPresented: $pickingFirmware, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                perform { try await installer.installPS3Firmware(url) }
            }
        }
        .confirmationDialog("Uninstall \(id.name)?", isPresented: $confirmingUninstall) {
            Button("Move to Trash", role: .destructive) {
                do { try installer.uninstall(id) } catch { library.error = error.localizedDescription }
            }
        } message: {
            Text(id == .retroarch ? "RetroArch and its downloaded cores move to the Trash. Your games stay in the library." : "\(id.name) moves to the Trash. Your games stay in the library.")
        }
    }

    private func statusCapsule(installed: Bool, version: String?) -> some View {
        let (text, color): (String, Color) = !installed
            ? ("Not installed", .gray)
            : installer.updateAvailable(id) ? ("Update available", .orange) : (version ?? "Installed", .green)
        return Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                library.error = error.localizedDescription
            }
        }
    }
}
