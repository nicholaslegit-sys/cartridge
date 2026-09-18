import Foundation

struct CartridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Paths {
    /// CARTRIDGE_HOME lets tests run against a throwaway directory.
    static let root: URL = {
        if let home = ProcessInfo.processInfo.environment["CARTRIDGE_HOME"] {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cartridge", isDirectory: true)
    }()
    static let demoKey = "demoMode"
    /// Demo Mode swaps in a separate sample library - its own game list, art and games - kept apart from the real one.
    static var isDemo: Bool { UserDefaults.standard.bool(forKey: demoKey) }
    /// Where the current library's list, art and games live.
    static var library: URL { isDemo ? root.appendingPathComponent("Demo", isDirectory: true) : root }

    /// Cartridge's own Games folder, whatever the player later chose.
    static var defaultGames: URL { library.appendingPathComponent("Games", isDirectory: true) }

    /// Where copied games land. Setup can point this at any folder - an external drive, usually.
    static var games: URL {
        // Tests run against CARTRIDGE_HOME and must not pick up the folder chosen in the real app.
        guard ProcessInfo.processInfo.environment["CARTRIDGE_HOME"] == nil, !isDemo,
              let chosen = UserDefaults.standard.string(forKey: AppSetup.Key.gamesFolder), !chosen.isEmpty
        else { return defaultGames }
        return URL(fileURLWithPath: chosen, isDirectory: true)
    }

    /// Every folder copied games can be in: the current one, plus Cartridge's own for games copied before it moved.
    static var gamesRoots: [URL] {
        let current = games
        return current == defaultGames ? [current] : [current, defaultGames]
    }

    /// Where zips and 7zs are unpacked before their games are added. Inside the games folder, so adding is a move
    /// on the same drive, and hidden, so the folder scan skips it.
    static var unpacking: URL { games.appendingPathComponent(".Unpacking", isDirectory: true) }

    static var emulators: URL { root.appendingPathComponent("Emulators", isDirectory: true) }
    static var art: URL { library.appendingPathComponent("Art", isDirectory: true) }
    static var bios: URL { root.appendingPathComponent("BIOS", isDirectory: true) }
    static var libraryFile: URL { library.appendingPathComponent("library.json") }

    /// Where RetroArch looks for BIOS files: its config's system_directory, else ~/Documents/RetroArch/system - not
    /// Application Support, which RetroArch stopped using for this in early 2024.
    static var retroArchSystem: URL {
        EmulatorData.retroArchDirectory("system_directory", default: "system")
    }

    /// The name of the drive a path is on when that drive isn't connected, else nil.
    static func disconnectedVolume(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return FileManager.default.fileExists(atPath: "/Volumes/\(parts[2])") ? nil : parts[2]
    }

    /// Refuses to copy into a games folder whose drive is unplugged, rather than failing with a permissions error
    /// about /Volumes.
    static func checkGamesFolder() throws {
        if let drive = disconnectedVolume(of: games) {
            throw CartridgeError("Your games folder is on “\(drive)”, which isn't connected. Plug it in, or choose another folder in Settings → Games.")
        }
    }

    static func ensure(_ dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum Shell {
    /// Runs a tool to completion and returns its combined output; throws on a non-zero exit.
    static func runSync(_ tool: String, _ args: [String], input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        // Drain before waiting: a tool that fills the pipe buffer would otherwise never exit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let name = (tool as NSString).lastPathComponent
            throw CartridgeError("\(name) failed (exit \(process.terminationStatus)): \(text.suffix(400))")
        }
        return text
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], input: String? = nil) async throws -> String {
        try await Task.detached { try runSync(tool, args, input: input) }.value
    }
}

enum Net {
    /// Follows the app's own version, so it can't drift from the release.
    static let userAgent = "Cartridge/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (macOS)"

    static func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func data(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try check(response, url)
        return data
    }

    static func exists(_ url: URL) async -> Bool {
        guard let (_, response) = try? await URLSession.shared.data(for: request(url, method: "HEAD")) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    static func check(_ response: URLResponse?, _ url: URL) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CartridgeError("\(url.host ?? "Server") answered HTTP \(status) for \(url.lastPathComponent)") }
    }

    /// Downloads to `destination`, reporting progress from 0 to 1. Cancelling the calling task cancels the download.
    static func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        // The last part of `destination` is often a name a server chose. "." or ".." in it would point the download at
        // the folder it was meant to land in - which is then deleted to make room for the file - so refuse those first.
        guard !destination.pathComponents.contains(".."), destination.lastPathComponent != "." else {
            throw CartridgeError("“\(destination.lastPathComponent)” isn't a name Cartridge can save a download as")
        }
        let box = DownloadBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = URLSession.shared.downloadTask(with: request(url)) { temp, response, error in
                    do {
                        if let error { throw error }
                        try check(response, url)
                        guard let temp else { throw CartridgeError("Download of \(url.lastPathComponent) produced no file") }
                        try? FileManager.default.removeItem(at: destination)
                        // The temporary file is deleted when this handler returns, so move it now.
                        try FileManager.default.moveItem(at: temp, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.start(task, progress: progress)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private final class DownloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var cancelled = false
    private var lastReported = -1.0

    func start(_ task: URLSessionDownloadTask, progress: @escaping @Sendable (Double) -> Void) {
        lock.lock()
        self.task = task
        observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            guard let self else { return }
            let value = p.fractionCompleted
            self.lock.lock()
            let report = value - self.lastReported >= 0.01 || value >= 1
            if report { self.lastReported = value }
            self.lock.unlock()
            if report { progress(value) }
        }
        let alreadyCancelled = cancelled
        lock.unlock()
        task.resume()
        if alreadyCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
