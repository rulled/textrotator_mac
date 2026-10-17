import Foundation
import AppKit
import Combine
import TextRotatorCore

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(UpdateInfo)
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case extracting
    case readyToRelaunch
    case failed(String)
}

@MainActor
public final class UpdateService: NSObject, ObservableObject {
    public static let shared = UpdateService()

    @Published public private(set) var state: UpdateState = .idle
    @Published public var isAutomaticCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutomaticCheckEnabled, forKey: "auto_check_updates_enabled")
        }
    }

    private let repoOwner = "rulled"
    private let repoName = "textrotator_mac"
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?

    private override init() {
        self.isAutomaticCheckEnabled = UserDefaults.standard.object(forKey: "auto_check_updates_enabled") as? Bool ?? true
        super.init()
    }

    public var currentAppVersion: SemanticVersion {
        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return SemanticVersion(string: versionStr) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    // MARK: - Check for Updates

    public func checkForUpdates(isUserInitiated: Bool) {
        guard state != .checking else { return }
        state = .checking

        Task {
            do {
                let release = try await fetchLatestRelease()
                guard let remoteVersion = release.semanticVersion else {
                    throw NSError(
                        domain: "UpdateService",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Не удалось распознать версию опубликованного релиза (\(release.tagName))"]
                    )
                }

                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_update_check_timestamp")

                if remoteVersion > currentAppVersion {
                    let skipped = UserDefaults.standard.string(forKey: "skipped_update_version")
                    if !isUserInitiated && skipped == remoteVersion.description {
                        // Silent check: version was skipped by user
                        state = .idle
                        return
                    }

                    guard let asset = release.zipAsset else {
                        throw NSError(
                            domain: "UpdateService",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "В релизе \(release.tagName) не найден файл обновления TextRotator.zip"]
                        )
                    }

                    let info = UpdateInfo(
                        version: remoteVersion,
                        currentVersion: currentAppVersion,
                        releaseNotes: release.body ?? "Улучшения стабильности и исправления ошибок.",
                        downloadURL: asset.browserDownloadUrl,
                        zipSize: asset.size,
                        htmlURL: release.htmlUrl
                    )

                    state = .available(info)
                    UpdateWindowManager.shared.presentUpdateModal(info: info)
                } else {
                    state = .upToDate(currentVersion: currentAppVersion.description)
                    if isUserInitiated {
                        UpdateWindowManager.shared.presentUpToDateToast(version: currentAppVersion.description)
                    }
                }
            } catch {
                let nsError = error as NSError
                // 304 Not Modified means current version is still latest
                if nsError.domain == "UpdateService" && nsError.code == 304 {
                    state = .upToDate(currentVersion: currentAppVersion.description)
                    if isUserInitiated {
                        UpdateWindowManager.shared.presentUpToDateToast(version: currentAppVersion.description)
                    }
                    return
                }

                state = .failed(error.localizedDescription)
                if isUserInitiated {
                    UpdateWindowManager.shared.presentErrorAlert(error: error.localizedDescription)
                }
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TextRotator-App-Updater", forHTTPHeaderField: "User-Agent")

        // ETag caching to avoid GitHub rate limits
        if let etag = UserDefaults.standard.string(forKey: "github_release_etag") {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 304 {
            throw NSError(domain: "UpdateService", code: 304, userInfo: [NSLocalizedDescriptionKey: "Версия актуальна"])
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw NSError(domain: "UpdateService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Релизы пока не опубликованы на GitHub"])
            }
            throw NSError(
                domain: "UpdateService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub API вернул статус \(httpResponse.statusCode)"]
            )
        }

        if let newEtag = httpResponse.allHeaderFields["Etag"] as? String {
            UserDefaults.standard.set(newEtag, forKey: "github_release_etag")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    // MARK: - User Decisions

    public func skipVersion(_ version: SemanticVersion) {
        UserDefaults.standard.set(version.description, forKey: "skipped_update_version")
        state = .idle
        UpdateWindowManager.shared.closeModal()
    }

    public func remindLater() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_remind_later_timestamp")
        state = .idle
        UpdateWindowManager.shared.closeModal()
    }

    // MARK: - Download & Pipeline

    public func downloadAndInstall(info: UpdateInfo) {
        state = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: info.zipSize)

        let sessionConfig = URLSessionConfiguration.default
        let delegate = DownloadProgressDelegate(
            onProgress: { [weak self] progress, bytesWritten, total in
                Task { @MainActor in
                    self?.state = .downloading(progress: progress, bytesWritten: bytesWritten, totalBytes: total)
                }
            },
            onComplete: { [weak self] tempLocation in
                Task { @MainActor in
                    await self?.processDownloadedZip(tempLocation: tempLocation)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.state = .failed(error.localizedDescription)
                }
            }
        )

        downloadSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        downloadTask = downloadSession?.downloadTask(with: info.downloadURL)
        downloadTask?.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    private func processDownloadedZip(tempLocation: URL) async {
        state = .extracting

        do {
            let fileManager = FileManager.default
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("com.rulled.textrotator/Updates", isDirectory: true)

            try? fileManager.removeItem(at: cacheDir)
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            let zipDest = cacheDir.appendingPathComponent("update.zip")
            try fileManager.moveItem(at: tempLocation, to: zipDest)

            // Extract with /usr/bin/ditto preserving permissions, xattrs, and symlinks
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzipProcess.arguments = ["-x", "-k", zipDest.path, cacheDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw NSError(domain: "UpdateService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ошибка распаковки архива обновления"])
            }

            let extractedApp = cacheDir.appendingPathComponent("TextRotator.app")
            guard fileManager.fileExists(atPath: extractedApp.path) else {
                throw NSError(domain: "UpdateService", code: 4, userInfo: [NSLocalizedDescriptionKey: "В архиве не найдено приложение TextRotator.app"])
            }

            // Verify codesign of extracted bundle
            let codesignProcess = Process()
            codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesignProcess.arguments = ["--verify", "--deep", "--strict", extractedApp.path]
            try codesignProcess.run()
            codesignProcess.waitUntilExit()

            guard codesignProcess.terminationStatus == 0 else {
                throw NSError(domain: "UpdateService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Распакованное обновление не прошло проверку целостности"])
            }

            state = .readyToRelaunch
            try launchRelaunchHelperAndExit(stagedAppPath: extractedApp.path)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - In-Place Atomic Replacement & Relaunch

    private func launchRelaunchHelperAndExit(stagedAppPath: String) throws {
        let currentAppPath = Bundle.main.bundleURL.path
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let scriptContent = """
        #!/bin/bash
        PID="\(currentPID)"
        SOURCE="\(stagedAppPath)"
        DEST="\(currentAppPath)"

        # 1. Wait for current process to exit cleanly
        COUNT=0
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.1
            COUNT=$((COUNT + 1))
            if [ $COUNT -gt 80 ]; then
                kill -9 "$PID" 2>/dev/null || true
                break
            fi
        done

        # 2. Atomic replacement
        BACKUP="${DEST}.old.$$"
        mv "$DEST" "$BACKUP" 2>/dev/null || true

        if cp -R "$SOURCE" "$DEST"; then
            rm -rf "$BACKUP"
            # Remove Gatekeeper quarantine if set
            xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
            # 3. Relaunch updated application
            open "$DEST"
        else
            # Rollback on failure
            if [ -d "$BACKUP" ]; then
                mv "$BACKUP" "$DEST" 2>/dev/null || true
            fi
            open "$DEST"
        fi

        # Cleanup
        rm -rf "$(dirname "$SOURCE")"
        rm -f "$0"
        """

        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("textrotator_updater_\(UUID().uuidString).sh")
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", scriptURL.path]
        try chmodProcess.run()
        chmodProcess.waitUntilExit()

        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        launchProcess.arguments = ["-c", "nohup \"\(scriptURL.path)\" >/dev/null 2>&1 &"]
        try launchProcess.run()

        NSApplication.shared.terminate(nil)
    }
}

// MARK: - URLSessionDownloadDelegate for Smooth Progress Tracking

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private let onComplete: @Sendable (URL) -> Void
    private let onError: @Sendable (Error) -> Void

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (URL) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
        let progress = min(max(Double(totalBytesWritten) / Double(expected), 0.0), 1.0)
        onProgress(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.moveItem(at: location, to: tempURL)
        onComplete(tempURL)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onError(error)
        }
    }
}
