import AppKit

/// Copies every emulator's saves somewhere safe, keeps the last few copies, and can put one back.
///
/// A backup is a plain folder - `<destination>/<Emulator>/<date>/<kind of save>/<path>` - so it can be opened,
/// copied or restored by hand without Cartridge.
@MainActor @Observable
final class SaveBackups {
    enum Key {
        static let folder = "saves.backupFolder"
        static let automatic = "saves.automatic"
    }

    /// Backups kept per emulator; the oldest go once there are more.
    nonisolated static let kept = 10

    var destination: URL {
        didSet { UserDefaults.standard.set(destination.path, forKey: Key.folder) }
    }

    /// Back up an emulator's saves when it quits.
    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Key.automatic) }
    }

    private(set) var working: Set<EmulatorID> = []
    /// Bumped after every backup or restore, so views re-read the disk.
    private(set) var revision = 0
    var error: String?

    init() {
        let defaults = UserDefaults.standard
        destination = defaults.string(forKey: Key.folder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultDestination
        automatic = defaults.object(forKey: Key.automatic) as? Bool ?? true
    }

    /// iCloud Drive when it's switched on, so saves reach every Mac signed in to it; otherwise Documents.
    static var defaultDestination: URL {
        let iCloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let base = FileManager.default.fileExists(atPath: iCloud.path) ? iCloud
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return base.appendingPathComponent("Cartridge Saves", isDirectory: true)
    }

    func folder(for id: EmulatorID) -> URL {
        destination.appendingPathComponent(id.name, isDirectory: true)
    }

    /// Backups of one emulator, newest first.
    func backups(of id: EmulatorID) -> [URL] {
        _ = revision
        return Self.backups(in: folder(for: id))
    }

    // MARK: Backing up and restoring

    /// Copies an emulator's saves into a new dated backup, unless nothing has changed since the last one.
    func backUp(_ id: EmulatorID, force: Bool = false) async {
        guard !working.contains(id) else { return }
        working.insert(id)
        defer {
            working.remove(id)
            revision += 1
        }
        let sets = EmulatorData.saves(id)
        let folder = folder(for: id)
        do {
            try await Task.detached {
                if !force, let latest = Self.latestChange(sets), let last = Self.backups(in: folder).first,
                   let lastDate = Self.date(of: last), latest <= lastDate { return }
                guard try Self.copy(sets, into: folder.appendingPathComponent(Self.stamp(Date()), isDirectory: true)) > 0 else { return }
                try Self.prune(folder, keeping: Self.kept)
            }.value
        } catch {
            self.error = "Couldn't back up \(id.name) saves: \(error.localizedDescription)"
        }
    }

    func backUpEverything() async {
        for id in EmulatorID.allCases where !EmulatorData.saves(id).flatMap(\.paths).isEmpty {
            await backUp(id, force: true)
        }
    }

    /// Puts a backup back. The saves there now are backed up first and then moved to the Trash, not deleted, so a
    /// restore can itself be undone.
    func restore(_ backup: URL, for id: EmulatorID) async {
        guard !Self.isRunning(id) else {
            error = "Quit \(id.name) first - it would write its own saves back over the restored ones when it closes."
            return
        }
        await backUp(id, force: true)
        working.insert(id)
        defer {
            working.remove(id)
            revision += 1
        }
        let sets = EmulatorData.saves(id)
        do {
            try await Task.detached { try Self.restore(sets, from: backup) }.value
        } catch {
            self.error = "Couldn't restore \(id.name) saves: \(error.localizedDescription)"
        }
    }

    /// Whether an emulator is open, whether Cartridge started it or not.
    static func isRunning(_ id: EmulatorID) -> Bool {
        let installed = Installer.folder(id).path
        return NSWorkspace.shared.runningApplications.contains { app in
            if let url = app.bundleURL ?? app.executableURL, url.path.hasPrefix(installed) { return true }
            return app.localizedName?.localizedCaseInsensitiveContains(id.name) == true
        }
    }

    // MARK: The work itself

    nonisolated static func stamp(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HHmmss"
        return format.string(from: date)
    }

    nonisolated static func date(of backup: URL) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HHmmss"
        return format.date(from: backup.lastPathComponent)
    }

    nonisolated static func backups(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { date(of: $0) != nil }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Copies every save file into `folder`, laid out as `<kind of save>/<path inside the emulator's folder>`.
    /// Returns how many top-level items were copied; nothing is created when there's nothing to copy.
    @discardableResult
    nonisolated static func copy(_ sets: [EmulatorData.SaveSet], into folder: URL) throws -> Int {
        let fm = FileManager.default
        var copied = 0
        for set in sets {
            for path in set.paths {
                let source = path.isEmpty ? set.base : set.base.appendingPathComponent(path)
                let target = path.isEmpty ? folder.appendingPathComponent(set.name) : folder.appendingPathComponent(set.name).appendingPathComponent(path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                copied += 1
            }
        }
        return copied
    }

    /// Puts each saved item back where it came from, moving whatever is there now to the Trash first.
    nonisolated static func restore(_ sets: [EmulatorData.SaveSet], from backup: URL,
                                    setAside: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let fm = FileManager.default
        for set in sets {
            let saved = backup.appendingPathComponent(set.name, isDirectory: true)
            guard fm.fileExists(atPath: saved.path) else { continue }
            // What the backup holds for this kind of save: the whole folder, or the paths the patterns matched.
            let paths = set.patterns == [""] ? [""] : set.patterns.flatMap { EmulatorData.expand($0, in: saved) }
            for path in paths {
                let source = path.isEmpty ? saved : saved.appendingPathComponent(path)
                let target = path.isEmpty ? set.base : set.base.appendingPathComponent(path)
                if fm.fileExists(atPath: target.path) { try setAside(target) }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            }
        }
    }

    nonisolated static func prune(_ folder: URL, keeping count: Int) throws {
        for old in backups(in: folder).dropFirst(count) {
            try FileManager.default.removeItem(at: old)
        }
    }

    /// When any save file last changed, and how many there are and how big.
    nonisolated static func summary(_ sets: [EmulatorData.SaveSet]) -> (files: Int, bytes: Int64, latest: Date?) {
        var files = 0
        var bytes: Int64 = 0
        var latest: Date?
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        for set in sets {
            for path in set.paths {
                let root = path.isEmpty ? set.base : set.base.appendingPathComponent(path)
                var items: [URL] = [root]
                if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
                    items += walker.compactMap { $0 as? URL }
                }
                for item in items {
                    guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                    files += 1
                    bytes += Int64(values.fileSize ?? 0)
                    if let date = values.contentModificationDate, date > (latest ?? .distantPast) { latest = date }
                }
            }
        }
        return (files, bytes, latest)
    }

    nonisolated static func latestChange(_ sets: [EmulatorData.SaveSet]) -> Date? {
        summary(sets).latest
    }
}
