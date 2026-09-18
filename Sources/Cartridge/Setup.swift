import SwiftUI

/// What the setup screen asks for: the consoles the player actually runs, and where their games live.
///
/// Kept in UserDefaults rather than in the library file so `Paths` can read the games folder from any thread,
/// and so wiping the library never loses the answers.
@MainActor @Observable
final class AppSetup {
    enum Key {
        static let consoles = "setup.consoles"
        static let gamesFolder = "setup.gamesFolder"
        static let completedVersion = "setup.completedVersion"
    }

    /// Bumped when setup gains a step existing players should be shown again.
    static let version = 1

    var consoles: Set<System> {
        didSet { defaults.set(consoles.map(\.rawValue).sorted(), forKey: Key.consoles) }
    }

    /// nil means Cartridge's own Games folder.
    var gamesFolder: URL? {
        didSet { defaults.set(gamesFolder?.path, forKey: Key.gamesFolder) }
    }

    private var completedVersion: Int {
        didSet { defaults.set(completedVersion, forKey: Key.completedVersion) }
    }

    /// Whether the setup sheet is on screen. Opens itself on a first run.
    var isShowing: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let completed = defaults.integer(forKey: Key.completedVersion)
        consoles = Set((defaults.stringArray(forKey: Key.consoles) ?? []).compactMap(System.init(rawValue:)))
        gamesFolder = defaults.string(forKey: Key.gamesFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
        completedVersion = completed
        isShowing = completed < Self.version
    }

    func finish() {
        completedVersion = Self.version
        isShowing = false
    }

    /// Whether a system is one the player said they run. Nobody having chosen yet means "all of them".
    func runs(_ system: System) -> Bool {
        consoles.isEmpty || consoles.contains(system)
    }

    /// The chosen consoles in the order they are listed everywhere else, or every system when none were chosen.
    var chosen: [System] {
        consoles.isEmpty ? System.allCases : System.allCases.filter(consoles.contains)
    }

    /// Emulators worth showing: the ones the chosen consoles need.
    var emulators: [EmulatorID] {
        EmulatorID.allCases.filter { id in chosen.contains { $0.emulator == id } }
    }

    /// BIOS files the chosen consoles want - the ones they can't boot without, plus the optional extras.
    var biosNeeded: [BiosRequirement] {
        let systems = Set(chosen)
        return BiosRequirement.all.filter { systems.contains($0.system) }
    }

    /// Where a folder the player picked has to be before Cartridge will copy games into it.
    /// Returns the reason it can't be used, or nil when it is fine.
    nonisolated static func rejection(for folder: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "That folder doesn't exist any more."
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return "Cartridge can't write to that folder."
        }
        // A games folder inside the app's own support folder would be trashed along with it, and one at the root of a
        // volume or home folder means a "Games" pile in the middle of everything else.
        if folder.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            return "Pick a folder inside your home folder rather than the home folder itself."
        }
        return nil
    }

    /// Free space on the volume holding `folder`, for the setup screen's "room for your games" line.
    nonisolated static func freeSpace(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
