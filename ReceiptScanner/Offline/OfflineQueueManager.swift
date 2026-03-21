// OfflineQueueManager.swift
// Persists receipts when offline (JSON in Documents/offline_queue.json).
// Flushes automatically when network becomes available.
// Max 100 receipts in queue to prevent storage bloat.

import Foundation
import Network
import Combine

final class OfflineQueueManager: ObservableObject {

    @Published private(set) var queuedReceipts: [Receipt] = []
    @Published var isFlushing: Bool = false

    private let maxQueueSize = 100
    private let queueURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_queue.json")
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        loadQueue()
    }

    // MARK: - Enqueue

    func enqueue(_ receipt: Receipt) throws {
        guard queuedReceipts.count < maxQueueSize else {
            throw AppError.offlineQueueFull
        }
        queuedReceipts.append(receipt)
        try persistQueue()
    }

    // MARK: - Flush

    /// Call when connectivity is restored. Requires Google services injected.
    func flushIfConnected() async {
        guard NetworkMonitor.shared.isConnected,
              !queuedReceipts.isEmpty,
              !isFlushing else { return }

        await MainActor.run { isFlushing = true }
        defer { Task { @MainActor in isFlushing = false } }

        // We don't have direct access to Google services here;
        // OfflineFlushCoordinator (owned by the ViewModel layer) calls this.
        // Post a notification that the active ViewModel can observe.
        NotificationCenter.default.post(name: .offlineQueueReadyToFlush, object: nil)
    }

    /// Remove a successfully submitted receipt from the queue.
    func dequeue(id: UUID) {
        queuedReceipts.removeAll { $0.id == id }
        try? persistQueue()
    }

    /// Clear the entire queue.
    func clearAll() {
        queuedReceipts.removeAll()
        try? persistQueue()
    }

    // MARK: - Persistence

    private func persistQueue() throws {
        let data = try encoder.encode(queuedReceipts)
        try data.write(to: queueURL, options: .atomic)
    }

    private func loadQueue() {
        guard
            let data = try? Data(contentsOf: queueURL),
            let receipts = try? decoder.decode([Receipt].self, from: data)
        else { return }
        queuedReceipts = receipts
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let offlineQueueReadyToFlush = Notification.Name("offlineQueueReadyToFlush")
}

// MARK: - NetworkMonitor (singleton)

final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private(set) var isConnected = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = (path.status == .satisfied)
            if path.status == .satisfied {
                Task { await OfflineQueueManager().flushIfConnected() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
