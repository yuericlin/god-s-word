// RepositoryView.swift — browse the CrossWire repository and download versions.

import SwiftUI
import SwordReader

struct RepositoryView: View {
    @Environment(\.moduleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var modules: [ModuleInfo] = []
    @State private var query = ""
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var downloading: Set<String> = []
    @State private var progress: [String: Double] = [:]
    @State private var tasks: [String: Task<Void, Never>] = [:]
    @State private var installedIDs: Set<String> = []
    @State private var selectedSourceID = BibleSource.crossWire.id

    /// All remote (repository) sources the user can download from.
    private var repositorySources: [BibleSource] {
        BibleSourceStore.shared.allSources.filter { $0.repositoryURL != nil }
    }

    private var selectedSource: BibleSource {
        repositorySources.first { $0.id == selectedSourceID } ?? BibleSource.crossWire
    }

    private var repository: SwordRepository {
        let url = selectedSource.repositoryURL ?? BibleSource.crossWire.repositoryURL!
        return SwordRepository(name: selectedSource.name, baseURL: url)
    }

    private var filtered: [ModuleInfo] {
        // Bibles the reader can open, plus commentaries the auxiliary
        // panel can read (REQ-AP-4).
        let base = modules.filter { $0.isRenderable || $0.isCommentaryRenderable }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter {
            $0.id.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading repository…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark",
                                            description: Text(errorMessage))
                } else {
                    VStack(spacing: 0) {
                        if repositorySources.count > 1 {
                            Picker("Source", selection: $selectedSourceID) {
                                ForEach(repositorySources) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding()
                        }
                        List(filtered, id: \.id) { mod in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mod.description).font(.headline)
                                    Text(mod.isCommentary
                                         ? "\(mod.id) · \(mod.language) · Commentary"
                                         : "\(mod.id) · \(mod.language)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusView(for: mod)
                            }
                        }
                        .searchable(text: $query, prompt: "Search versions")
                    }
                }
            }
            .navigationTitle("Add Bible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedSourceID) { Task { await load() } }
        .onAppear { installedIDs = Set(store.installedModules().map { $0.id }) }
    }

    @ViewBuilder
    private func statusView(for mod: ModuleInfo) -> some View {
        if installedIDs.contains(mod.id) {
            Text("Installed").font(.caption).foregroundStyle(.secondary)
        } else if downloading.contains(mod.id) {
            HStack(spacing: 6) {
                if let fraction = progress[mod.id] {
                    ProgressView(value: fraction).frame(width: 60)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
                Button {
                    tasks[mod.id]?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel download")
            }
        } else {
            Button("Get") { tasks[mod.id] = Task { await download(mod) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: repository.catalogURL)
            modules = try SwordRepository.parseCatalog([UInt8](data))
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func download(_ mod: ModuleInfo) async {
        let id = mod.id
        downloading.insert(id)
        defer {
            downloading.remove(id)
            progress[id] = nil
            tasks[id] = nil
        }
        do {
            let data = try await PackageDownloader.fetch(
                from: repository.packageURL(for: id)
            ) { fraction in
                progress[id] = fraction
            }
            // Install off the main thread: unpacking a package must never
            // freeze the page.
            let store = self.store
            _ = try await Task.detached(priority: .userInitiated) {
                try store.install(packageData: data, moduleID: id)
            }.value
            // Tag the module with the source it was downloaded from so it
            // appears under that source in the library.
            BibleSourceStore.shared.setSourceID(selectedSourceID, forModule: mod.id)
            installedIDs.insert(mod.id)
        } catch is CancellationError {
            // Cancelled by the user — not an error.
        } catch let error as URLError where error.code == .cancelled {
            // Cancelled by the user — not an error.
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}

/// The commentary counterpart of RepositoryView (REQ-AP-10): the same
/// repository browser, but listing only commentaries the auxiliary
/// panel can read, under an "Add Commentary" title, with each
/// commentary's declared license shown under its name (REQ-AP-8).
struct CommentaryRepositoryView: View {
    @Environment(\.moduleStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var modules: [ModuleInfo] = []
    @State private var query = ""
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var downloading: Set<String> = []
    @State private var progress: [String: Double] = [:]
    @State private var tasks: [String: Task<Void, Never>] = [:]
    @State private var installedIDs: Set<String> = []
    @State private var selectedSourceID = BibleSource.crossWire.id

    /// All remote (repository) sources the user can download from.
    private var repositorySources: [BibleSource] {
        BibleSourceStore.shared.allSources.filter { $0.repositoryURL != nil }
    }

    private var selectedSource: BibleSource {
        repositorySources.first { $0.id == selectedSourceID } ?? BibleSource.crossWire
    }

    private var repository: SwordRepository {
        let url = selectedSource.repositoryURL ?? BibleSource.crossWire.repositoryURL!
        return SwordRepository(name: selectedSource.name, baseURL: url)
    }

    private var filtered: [ModuleInfo] {
        // Only commentaries the panel can read (REQ-AP-4).
        let base = modules.filter { $0.isCommentaryRenderable }
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter {
            $0.id.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading repository…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.exclamationmark",
                                            description: Text(errorMessage))
                } else {
                    VStack(spacing: 0) {
                        if repositorySources.count > 1 {
                            Picker("Source", selection: $selectedSourceID) {
                                ForEach(repositorySources) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding()
                        }
                        List(filtered, id: \.id) { mod in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mod.description).font(.headline)
                                    Text("\(mod.id) · \(mod.language)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !mod.distributionLicense.isEmpty {
                                        Text(mod.distributionLicense)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                statusView(for: mod)
                            }
                        }
                        .searchable(text: $query, prompt: "Search commentaries")
                    }
                }
            }
            .navigationTitle("Add Commentary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedSourceID) { Task { await load() } }
        .onAppear { installedIDs = Set(store.installedModules().map { $0.id }) }
    }

    @ViewBuilder
    private func statusView(for mod: ModuleInfo) -> some View {
        if installedIDs.contains(mod.id) {
            Text("Installed").font(.caption).foregroundStyle(.secondary)
        } else if downloading.contains(mod.id) {
            HStack(spacing: 6) {
                if let fraction = progress[mod.id] {
                    ProgressView(value: fraction).frame(width: 60)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
                Button {
                    tasks[mod.id]?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel download")
            }
        } else {
            Button("Get") { tasks[mod.id] = Task { await download(mod) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: repository.catalogURL)
            modules = try SwordRepository.parseCatalog([UInt8](data))
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func download(_ mod: ModuleInfo) async {
        let id = mod.id
        downloading.insert(id)
        defer {
            downloading.remove(id)
            progress[id] = nil
            tasks[id] = nil
        }
        do {
            let data = try await PackageDownloader.fetch(
                from: repository.packageURL(for: id)
            ) { fraction in
                progress[id] = fraction
            }
            // Install off the main thread: unpacking a package must never
            // freeze the page.
            let store = self.store
            _ = try await Task.detached(priority: .userInitiated) {
                try store.install(packageData: data, moduleID: id)
            }.value
            // Tag the module with the source it was downloaded from.
            BibleSourceStore.shared.setSourceID(selectedSourceID, forModule: mod.id)
            installedIDs.insert(mod.id)
        } catch is CancellationError {
            // Cancelled by the user — not an error.
        } catch let error as URLError where error.code == .cancelled {
            // Cancelled by the user — not an error.
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}

/// One-shot package download with progress, cancellation, and timeouts.
/// The plain `URLSession.data(from:)` API offers no progress and no
/// cancel, and its default resource timeout is days — a stalled transfer
/// spun forever behind a bare spinner. Here the surrounding Task's
/// cancellation cancels the transfer, progress is reported as a fraction
/// (when the server gives a length), and a transfer that stalls for
/// 30 seconds — or runs past 15 minutes in total — fails with an error
/// instead of hanging.
final class PackageDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[UInt8], Error>?
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var cancelRequested = false
    private var finished = false
    // Touched only on the session's serial delegate queue.
    private var buffer: [UInt8] = []
    private var expectedLength: Int64 = 0
    private var progressHandler: (@MainActor (Double) -> Void)?

    static func fetch(from url: URL,
                      progress: @escaping @MainActor (Double) -> Void) async throws -> [UInt8] {
        let downloader = PackageDownloader()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.begin(url: url, continuation: continuation, progress: progress)
            }
        } onCancel: {
            downloader.cancel()
        }
    }

    private func begin(url: URL, continuation: CheckedContinuation<[UInt8], Error>,
                       progress: @escaping @MainActor (Double) -> Void) {
        lock.lock()
        self.continuation = continuation
        progressHandler = progress
        let alreadyCancelled = cancelRequested
        lock.unlock()
        guard !alreadyCancelled else {
            finish(with: .failure(CancellationError()))
            return
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 900
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: url)
        lock.lock()
        self.session = session
        dataTask = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock()
        cancelRequested = true
        let task = dataTask
        lock.unlock()
        task?.cancel()
    }

    private func finish(with result: Result<[UInt8], Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        let session = self.session
        lock.unlock()
        session?.finishTasksAndInvalidate()
        switch result {
        case .success(let bytes): continuation.resume(returning: bytes)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            finish(with: .failure(ModuleStoreError.downloadFailed))
            return .cancel
        }
        expectedLength = response.expectedContentLength
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(contentsOf: data)
        if expectedLength > 0, let progressHandler {
            let fraction = Double(buffer.count) / Double(expectedLength)
            Task { @MainActor in progressHandler(fraction) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled {
                finish(with: .failure(CancellationError()))
            } else {
                finish(with: .failure(error))
            }
        } else {
            finish(with: .success(buffer))
        }
    }
}
