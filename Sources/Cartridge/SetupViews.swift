import SwiftUI
import UniformTypeIdentifiers

/// The first-run screen. Asks which consoles the player runs, sorts out BIOS files for the ones that need them,
/// and finds out where their games should live - so the rest of the app only ever shows what they asked for.
struct SetupSheet: View {
    @Environment(AppSetup.self) private var setup
    @Environment(BiosStore.self) private var bios
    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome, consoles, bios, location, emulators

        var title: String {
            switch self {
            case .welcome: "Welcome to Cartridge"
            case .consoles: "Which consoles do you run?"
            case .bios: "BIOS files"
            case .location: "Where should your games live?"
            case .emulators: "Ready to play"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "A launcher for the games you already own."
            case .consoles: "Cartridge hides everything else, so you only see the systems you actually use."
            case .bios: "A few consoles can't boot without one. Cartridge checks the files you supply."
            case .location: "Games you import can be copied somewhere with room for them."
            case .emulators: "Install the emulators your consoles need, or leave it until you first press play."
            }
        }
    }

    /// The BIOS step is pointless for someone who only picked consoles that don't need one.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .bios || !setup.biosNeeded.isEmpty }
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(width: 780, height: 610)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.title2.bold())
                Text(step.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { each in
                    Circle()
                        .fill(each == step ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .consoles: ConsolePicker()
        case .bios: BiosStep()
        case .location: GamesFolderStep()
        case .emulators: SetupEmulatorsStep()
        }
    }

    private var footer: some View {
        HStack {
            if index > 0 {
                Button("Back") { step = steps[index - 1] }
            }
            Spacer()
            if step == .bios, !bios.missing(for: setup.biosNeeded).isEmpty {
                Text("You can add these later from Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(isLast ? "Start Playing" : "Continue") {
                if isLast {
                    setup.finish()
                } else {
                    step = steps[index + 1]
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(step == .consoles && setup.consoles.isEmpty)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 108, height: 108)
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 18) {
                Point(icon: "externaldrive.badge.plus", title: "Your dumps, your library",
                      text: "Drop in games you dumped from discs and carts you own. Cartridge never downloads commercial games or BIOS files.")
                Point(icon: "arrow.down.circle", title: "Emulators install themselves",
                      text: "The right emulator downloads from its official source the first time you press play, and updates from there too.")
                Point(icon: "books.vertical", title: "Covers, manuals and a shelf",
                      text: "Artwork and instruction booklets are looked up for you, and your collection stands on a 3D shelf you can pick up.")
            }
            .frame(maxWidth: 520, alignment: .leading)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 26)
    }

    private struct Point: View {
        let icon: String
        let title: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The console grid. Also used on its own in Settings.
struct ConsolePicker: View {
    @Environment(AppSetup.self) private var setup

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(System.makers, id: \.self) { maker in
                        let systems = System.allCases.filter { $0.maker == maker }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(maker).font(.subheadline.bold()).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 215, maximum: 320), spacing: 10, alignment: .leading)],
                                      alignment: .leading, spacing: 10) {
                                ForEach(systems) { system in
                                    ConsoleChip(system: system, selected: setup.consoles.contains(system)) {
                                        if setup.consoles.contains(system) {
                                            setup.consoles.remove(system)
                                        } else {
                                            setup.consoles.insert(system)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
            Divider()
            HStack {
                Text(setup.consoles.isEmpty ? "Pick at least one." : "\(setup.consoles.count) selected")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Select All") { setup.consoles = Set(System.allCases) }
                Button("Clear") { setup.consoles = [] }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
    }
}

private struct ConsoleChip: View {
    let system: System
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                SystemBadge(system: system)
                    .frame(width: 48, alignment: .leading)
                Text(system.name)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? system.color : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? system.color.opacity(0.14) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? system.color.opacity(0.65) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(system.setupNote ?? system.name)
    }
}

/// The BIOS list for the chosen consoles. Also used on its own in Settings.
struct BiosStep: View {
    @Environment(AppSetup.self) private var setup

    var body: some View {
        let requirements = setup.biosNeeded
        if requirements.isEmpty {
            ContentUnavailableView {
                Label("Nothing to supply", systemImage: "checkmark.seal")
            } description: {
                Text("None of the consoles you picked need a BIOS file.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cartridge can't give you a console BIOS: it is Sony's, Sega's or Microsoft's code, and the only lawful copy is the one you take off a console you own. What it does do is check the file really is that BIOS, tell you which revision it is, put it where the emulator looks, and remember its fingerprint so you can tell later if it was damaged.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(requirements) { requirement in
                        BiosRow(requirement: requirement)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
        }
    }
}

struct BiosRow: View {
    let requirement: BiosRequirement
    @Environment(BiosStore.self) private var bios
    @Environment(Library.self) private var library
    @Environment(Installer.self) private var installer
    @State private var picking = false
    @State private var dropTargeted = false

    private var installed: InstalledBios? { bios.installed[requirement.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                SystemBadge(system: requirement.system).frame(width: 48, alignment: .leading)
                Text(requirement.name).font(.headline)
                Text(requirement.required ? "Required" : "Optional")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((requirement.required ? Color.orange : Color.secondary).opacity(0.18), in: Capsule())
                    .foregroundStyle(requirement.required ? Color.orange : Color.secondary)
                Spacer()
                if installed != nil {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
            }

            Text(requirement.summary)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let installed {
                VStack(alignment: .leading, spacing: 3) {
                    Text(installed.identity).font(.callout.weight(.medium))
                    Text("\(installed.filename) · SHA-256 \(installed.sha256.prefix(16))…")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !requirement.targets.isEmpty {
                        Text("Copied into \(requirement.targets.map(\.name).joined(separator: " and "))'s BIOS folder.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(requirement.source).font(.caption).foregroundStyle(.secondary)
            }

            if let problem = bios.problems[requirement.id] {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if installed == nil, requirement.required {
                    Button("Choose File…") { picking = true }.buttonStyle(.borderedProminent)
                } else {
                    Button(installed == nil ? "Choose File…" : "Replace…") { picking = true }
                }
                if requirement.id == "ps3" {
                    Link("Get it from playstation.com", destination: URL(string: "https://www.playstation.com/en-us/support/hardware/ps3/system-software/")!)
                        .font(.callout)
                }
                if installed != nil {
                    Button("Verify") { bios.verify(requirement) }
                    Menu {
                        Button("Show in Finder") {
                            if let url = installed?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        if !requirement.targets.isEmpty {
                            Button("Copy to Emulators Again") {
                                do { try bios.reinstall(requirement) } catch { library.error = error.localizedDescription }
                            }
                        }
                        Button("Remove", role: .destructive) { bios.remove(requirement) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Spacer()
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(dropTargeted ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(dropTargeted ? Color.accentColor : .clear, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            accept(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { accept(url) }
        }
    }

    private func accept(_ url: URL) {
        do {
            try bios.accept(url, for: requirement)
            // RPCS3 is the only emulator that installs its firmware itself.
            if requirement.id == "ps3", let record = bios.installed["ps3"] {
                Task {
                    do { try await installer.installPS3Firmware(record.url) } catch { library.error = error.localizedDescription }
                }
            }
        } catch {
            library.error = error.localizedDescription
        }
    }
}

/// Where copied games are kept. Also used on its own in Settings.
struct GamesFolderStep: View {
    @Environment(AppSetup.self) private var setup
    @Environment(Library.self) private var library
    @State private var picking = false
    @AppStorage(Library.scanKey) private var scans = true

    private var folder: URL { Paths.games }
    private var isDefault: Bool { setup.gamesFolder == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When you add a game, Cartridge can copy it into its own library so the file can't wander off. Discs that come as a .cue or .gdi bring their track files along. Games you add without copying stay exactly where they are, wherever that is.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDefault ? "Cartridge's own folder" : folder.lastPathComponent).font(.headline)
                        Text(folder.path)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                } icon: {
                    Image(systemName: isDefault ? "internaldrive" : "externaldrive")
                        .font(.system(size: 22)).foregroundStyle(Color.accentColor)
                }

                if let drive = Paths.disconnectedVolume(of: folder) {
                    Label("“\(drive)” isn't connected. Plug it in before adding games, or choose another folder.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                } else if let free = AppSetup.freeSpace(at: folder) {
                    Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free on that volume.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Toggle("Add games that appear in this folder", isOn: $scans)
                Text("Cartridge looks when it starts and whenever you switch back to it, and adds what it recognises where it is, without copying. Files it can't place on a console are left for you to add with Add Games….")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Choose Folder…") { picking = true }
                    Button("Scan Now") { Task { await library.scanGamesFolderAndReport() } }
                        .disabled(library.scanning || Paths.disconnectedVolume(of: folder) != nil)
                    if !isDefault {
                        Button("Use Cartridge's Folder") { setup.gamesFolder = nil }
                    }
                    Button("Show in Finder") {
                        if let dir = try? Paths.ensure(folder) { NSWorkspace.shared.open(dir) }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))

            Label("A PS2 or Wii library runs to hundreds of gigabytes. An external drive is a good home for it - keep it plugged in, or the games on it can't be played.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !library.games.filter(\.managed).isEmpty {
                Label("Games already copied stay where they are and keep working. Only new imports go to a folder you pick now.", systemImage: "arrow.triangle.branch")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            if let reason = AppSetup.rejection(for: url) {
                library.error = reason
            } else {
                setup.gamesFolder = url
            }
        }
    }
}

/// The last step: the emulator list, filtered to the consoles that were picked.
private struct SetupEmulatorsStep: View {
    @Environment(AppSetup.self) private var setup
    @Environment(Installer.self) private var installer
    @Environment(Library.self) private var library

    private var pending: [EmulatorID] { setup.emulators.filter { installer.executable($0) == nil } }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("These are the emulators your consoles need. Installing now means the first game you open just starts; leaving it means Cartridge fetches one when you press play.")
                        .foregroundStyle(.secondary)
                }
                ForEach(setup.emulators) { id in
                    EmulatorRow(id: id)
                }
            }
            Divider()
            HStack {
                if pending.isEmpty {
                    Label("All installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(pending.count) not installed yet").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Install All (\(pending.count))") {
                    for id in pending {
                        Task {
                            do { try await installer.install(id) } catch is CancellationError {} catch {
                                library.error = error.localizedDescription
                            }
                        }
                    }
                }
                .disabled(pending.isEmpty)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
        }
        .task {
            if installer.latest.isEmpty { await installer.checkForUpdates() }
        }
    }
}
