import SwiftUI
import UniformTypeIdentifiers

// MARK: - Saves

/// Every emulator's saves: where they are, when they were last backed up, and putting a backup back.
struct SavesView: View {
    @Environment(SaveBackups.self) private var backups
    @State private var summaries: [EmulatorID: Summary] = [:]
    @State private var pickingFolder = false
    @State private var restoring: RestoreRequest?

    struct Summary {
        let files: Int
        let bytes: Int64
        let latest: Date?
    }

    struct RestoreRequest: Identifiable {
        let emulator: EmulatorID
        let backup: URL
        var id: URL { backup }
    }

    var body: some View {
        @Bindable var backups = backups
        List {
            Section {
                Text("Every emulator keeps its saves in its own folder. Cartridge copies them all to one place after each game, keeps the last \(SaveBackups.kept) copies for each emulator, and can put any of them back. Backups are ordinary folders, so you can open them without Cartridge.")
                    .foregroundStyle(.secondary)
                LabeledContent("Backups go to") {
                    HStack {
                        // As Finder names it: "iCloud Drive › Cartridge Saves", not ~/Library/Mobile Documents/com~apple~CloudDocs.
                        Text((FileManager.default.componentsToDisplay(forPath: backups.destination.path) ?? [backups.destination.path]).joined(separator: " › "))
                            .font(.callout).lineLimit(1).truncationMode(.head)
                            .help(backups.destination.path)
                        Button("Change…") { pickingFolder = true }
                        Button("Show in Finder") {
                            if let folder = try? Paths.ensure(backups.destination) { NSWorkspace.shared.open(folder) }
                        }
                    }
                }
                Toggle("Back up an emulator's saves when it quits", isOn: $backups.automatic)
            }

            Section("Emulators") {
                ForEach(EmulatorID.allCases) { id in
                    SaveRow(id: id, summary: summaries[id]) { backup in
                        restoring = RestoreRequest(emulator: id, backup: backup)
                    }
                }
            }
        }
        .navigationTitle("Saves")
        .toolbar {
            ToolbarItem {
                Button("Back Up Everything", systemImage: "externaldrive.badge.plus") {
                    Task { await backups.backUpEverything() }
                }
                .disabled(!backups.working.isEmpty)
            }
        }
        .task(id: backups.revision) {
            let ids = EmulatorID.allCases
            let computed = await Task.detached {
                Dictionary(uniqueKeysWithValues: ids.map { id in
                    let s = SaveBackups.summary(EmulatorData.saves(id))
                    return (id, Summary(files: s.files, bytes: s.bytes, latest: s.latest))
                })
            }.value
            summaries = computed
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { backups.destination = url }
        }
        .confirmationDialog("Restore these saves?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), presenting: restoring) { request in
            Button("Restore") { Task { await backups.restore(request.backup, for: request.emulator) } }
        } message: { request in
            Text("\(request.emulator.name)'s saves from \(SaveBackups.date(of: request.backup)?.formatted(date: .abbreviated, time: .shortened) ?? request.backup.lastPathComponent) go back in place. The saves there now are backed up first and moved to the Trash, so this can be undone.")
        }
        .alert("Saves", isPresented: Binding(get: { backups.error != nil }, set: { if !$0 { backups.error = nil } }), presenting: backups.error) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }
}

private struct SaveRow: View {
    let id: EmulatorID
    let summary: SavesView.Summary?
    let restore: (URL) -> Void
    @Environment(SaveBackups.self) private var backups

    var body: some View {
        let sets = EmulatorData.saves(id)
        let history = backups.backups(of: id)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(id.name).font(.headline)
                if sets.isEmpty {
                    Text(id == .xemu ? "xemu keeps saves inside its hard-disk image, which is too big to copy after every game. Back up that image from xemu's settings folder instead." : "Nothing to back up.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(sets.map(\.name).joined(separator: " · ")).font(.callout)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    if let last = history.first.flatMap(SaveBackups.date(of:)) {
                        Text("Backed up \(last.formatted(.relative(presentation: .named))) · \(history.count) cop\(history.count == 1 ? "y" : "ies") kept")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if backups.working.contains(id) {
                ProgressView().controlSize(.small)
            } else if !sets.isEmpty {
                HStack {
                    Button("Back Up Now") { Task { await backups.backUp(id, force: true) } }
                        .disabled((summary?.files ?? 0) == 0)
                    Menu {
                        if history.isEmpty {
                            Text("No backups yet")
                        } else {
                            ForEach(history, id: \.self) { backup in
                                Button("Restore \(SaveBackups.date(of: backup)?.formatted(date: .abbreviated, time: .shortened) ?? backup.lastPathComponent)…") {
                                    restore(backup)
                                }
                            }
                        }
                        Divider()
                        Button("Show Saves in Finder") {
                            let existing = sets.flatMap { set in set.paths.map { $0.isEmpty ? set.base : set.base.appendingPathComponent($0) } }
                            if !existing.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(existing) }
                        }
                        .disabled(summary?.files ?? 0 == 0)
                        Button("Show Backups in Finder") {
                            if let folder = try? Paths.ensure(backups.folder(for: id)) { NSWorkspace.shared.open(folder) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        guard let summary else { return "Looking…" }
        guard summary.files > 0 else { return "Nothing saved yet." }
        let size = ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file)
        let changed = summary.latest.map { " · changed \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return "\(summary.files) file\(summary.files == 1 ? "" : "s") · \(size)\(changed)"
    }
}

// MARK: - Dump check

/// A game's verdict from the known-good dump lists, and the buttons to get one.
struct DumpRow: View {
    let game: Game
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if library.checkingDump.contains(game.id) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Comparing with the \(DumpCheck.list(for: game.system)?.folder == "redump" ? "Redump" : "No-Intro") list…").font(.callout)
                }
            } else if let verdict = game.dump {
                Label(verdict.title, systemImage: verdict.symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(color(verdict))
                Text(verdict.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if case .verified(let name) = verdict, name != game.title {
                        Button("Use “\(name)” as the Title") { library.rename(game, to: name) }
                    }
                    Button("Check Again") { Task { await library.checkDumpShowingErrors(game.id) } }
                }
                .controlSize(.small)
            } else {
                Button("Check Game File") { Task { await library.checkDumpShowingErrors(game.id) } }
                Text(DumpCheck.list(for: game.system) == nil
                     ? "There's no list of known-good \(game.system.name) dumps to compare with."
                     : "Compares it with the \(game.system.isDisc ? "Redump" : "No-Intro") list of known-good dumps, which catches a bad dump before it crashes a game.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func color(_ verdict: DumpCheck.Verdict) -> Color {
        switch verdict {
        case .verified: .green
        case .bad: .orange
        case .unknown, .unsupported: .secondary
        }
    }
}

// MARK: - RetroAchievements

struct AchievementsSettings: View {
    @Environment(Library.self) private var library
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        let achievements = library.achievements
        Form {
            Section {
                Text("Sign in once and RetroArch, DuckStation and PCSX2 all earn achievements on your account. Cartridge swaps your password for a sign-in token the same way the emulators do: the password isn't kept, and the token stays in your Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                Link("Make a free account at retroachievements.org", destination: Achievements.site)
            }
            if let name = achievements.username {
                Section("Signed in as \(name)") {
                    ForEach(Achievements.supported) { id in
                        LabeledContent(id.name) {
                            Text(achievements.status[id] ?? "…").font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Button("Update Emulators Now") { achievements.applyToEmulators() }
                        Button("Sign Out", role: .destructive) { achievements.signOut() }
                    }
                    Text("An emulator that's open gets the sign-in when it quits, and one that already has a different account signed in keeps it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Sign in") {
                    TextField("Username", text: $user, prompt: Text("Your RetroAchievements user name"))
                        .textContentType(.username)
                    SecureField("Password", text: $password, prompt: Text("Only sent to retroachievements.org"))
                        .textContentType(.password)
                    HStack {
                        Button("Sign In") {
                            Task {
                                await achievements.signIn(user: user, password: password)
                                password = ""
                            }
                        }
                        .disabled(user.isEmpty || password.isEmpty || achievements.signingIn)
                        if achievements.signingIn { ProgressView().controlSize(.small) }
                    }
                    if let error = achievements.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { achievements.refreshStatus() }
    }
}

// MARK: - Controllers

import GameController

/// The controllers that are connected, and what each emulator needs before it uses them.
struct ControllersView: View {
    @Environment(Installer.self) private var installer
    @Environment(Library.self) private var library
    @State private var controllers: [GCController] = []

    var body: some View {
        List {
            Section {
                Text("Cartridge doesn't write button mappings into emulators itself. Button names differ between Xbox and PlayStation controllers and change between emulator versions, so each emulator's own automatic mapping, which sees the controller you actually have, gets it right where a guess from Cartridge could leave buttons dead. What's below is what each one needs, once.")
                    .foregroundStyle(.secondary)
            }
            Section("Connected") {
                if controllers.isEmpty {
                    Text("No controller connected. Pair one in System Settings → Bluetooth, or plug it in.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controllers, id: \.self) { controller in
                        HStack {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.vendorName ?? "Controller").font(.headline)
                                Text(controller.productCategory).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let battery = controller.battery {
                                Label("\(Int(battery.batteryLevel * 100))%", systemImage: battery.batteryState == .charging ? "battery.100.bolt" : "battery.75")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("In each emulator") {
                ForEach(EmulatorID.allCases) { id in
                    let note = id.controllerSetup
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: note.automatic ? "checkmark.circle.fill" : "hand.tap")
                            .foregroundStyle(note.automatic ? .green : .orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(id.name).font(.headline)
                            Text(note.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if !note.automatic {
                            if installer.executable(id) != nil {
                                Button("Open \(id.name)") {
                                    Task {
                                        do { _ = try await installer.launch(id, arguments: []) { _ in } } catch { library.error = error.localizedDescription }
                                    }
                                }
                            } else {
                                Text("Not installed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("Controllers")
        .onAppear { controllers = GCController.controllers() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in controllers = GCController.controllers() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in controllers = GCController.controllers() }
    }
}

extension EmulatorID {
    /// Whether an emulator picks up a controller by itself, and if not, the one thing to do in it.
    var controllerSetup: (automatic: Bool, text: String) {
        switch self {
        case .retroarch: (true, "Sets up Xbox, PlayStation and most other controllers by itself.")
        case .ppsspp: (true, "Uses Xbox and PlayStation controllers by itself.")
        case .flycast: (true, "Uses a connected controller as the Dreamcast pad by itself.")
        case .xemu: (true, "Plugs the first connected controller into port 1 by itself.")
        case .shadps4: (true, "Uses a connected controller by itself.")
        case .duckstation: (false, "Its first-run setup offers Automatic Mapping for the controller it finds - choose it once. Later: Settings → Controllers → Automatic Mapping.")
        case .pcsx2: (false, "Its first-run setup offers Automatic Mapping - choose it once. Later: Settings → Controllers → Automatic Mapping.")
        case .dolphin: (false, "Needs mapping once: Controllers → Configure next to Port 1, choose your controller as the device, and set the buttons.")
        case .azahar: (false, "Needs mapping once in its Controls settings.")
        case .rpcs3: (false, "Needs your controller chosen once in its Pads settings.")
        }
    }
}
