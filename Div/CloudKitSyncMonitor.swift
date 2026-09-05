//tatasta
//  CloudKitSyncMonitor.swift
//  gThai
//
//  Portert fra gInfo sin CloudKitSyncMonitor — samme prinsipp: lytter på
//  NSPersistentCloudKitContainer.eventChangedNotification for å vise status,
//  historikk og diagnostikk for CloudKit-synkronisering i "Om gThai".
//
import Foundation
import CoreData
import CloudKit

@Observable
class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor(container: PersistenceController.shared.container)
    /// Overvåker gThai-speilet (GThaiReferenceStore) — samme klasse, annen container.
    static let gThaiMirror = CloudKitSyncMonitor(container: GThaiReferenceStore.shared.container)

    // MARK: - Observable Properties
    var isSyncing: Bool = false
    var lastImportDate: Date?
    var lastExportDate: Date?
    var lastError: Error?
    var syncEvents: [SyncEvent] = []

    // Diagnostics
    var totalImportCount: Int = 0
    var totalExportCount: Int = 0
    var totalFailureCount: Int = 0

    // Computed properties
    var statusText: String {
        if isSyncing {
            return "Syncing..."
        } else if let lastImport = lastImportDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last synced \(formatter.localizedString(for: lastImport, relativeTo: Date()))"
        } else {
            return "Waiting for sync"
        }
    }

    var statusColor: String {
        if lastError != nil {
            return "red"
        } else if isSyncing {
            return "orange"
        } else if lastImportDate != nil {
            return "green"
        } else {
            return "gray"
        }
    }

    // MARK: - Private Properties
    private var eventObserver: NSObjectProtocol?
    // Deklarert som base-typen fordi PersistenceController.container også er det
    // (er faktisk NSPersistentCloudKitContainer i praksis, se PersistenceController.swift).
    // eventChangedNotification/Event er statiske members på NSPersistentCloudKitContainer,
    // så de trenger ikke den konkrete typen her — kun viewContext og observer-objektet.
    private let container: NSPersistentContainer

    // MARK: - Initialization
    private init(container: NSPersistentContainer) {
        self.container = container
        setupObserver()
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup
    private func setupObserver() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudKitEvent(notification)
        }

        Logger.info("CloudKitSyncMonitor: Observer set up")
    }

    // MARK: - Event Handling
    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        switch event.type {
        case .setup:
            Logger.info("CloudKit: Setup event")

        case .import:
            if event.endDate != nil {
                isSyncing = false
                lastImportDate = Date()
                totalImportCount += 1
                recordEvent(type: .import, event: event)
            } else {
                isSyncing = true
                Logger.info("CloudKit import started")
            }

        case .export:
            if event.endDate != nil {
                isSyncing = false
                lastExportDate = Date()
                totalExportCount += 1
                recordEvent(type: .export, event: event)
            } else {
                isSyncing = true
                Logger.info("CloudKit export started")
            }

        @unknown default:
            Logger.info("CloudKit: Unknown event type")
        }
    }

    private func recordEvent(type: SyncEvent.EventType, event: NSPersistentCloudKitContainer.Event) {
        var errorDetails: String?
        var errorCode: Int?
        if let error = event.error {
            errorDetails = parseCloudKitError(error)
            errorCode = (error as NSError).code
        }

        let eventInfo = SyncEvent(
            type: type,
            date: Date(),
            succeeded: event.succeeded,
            error: event.error,
            errorDetails: errorDetails,
            errorCode: errorCode
        )
        syncEvents.insert(eventInfo, at: 0)
        if syncEvents.count > 50 {
            syncEvents.removeLast()
        }

        if !event.succeeded {
            totalFailureCount += 1
            lastError = event.error
            Logger.error("CloudKit \(type.label) failed: \(errorDetails ?? event.error?.localizedDescription ?? "Unknown error")")
        } else {
            lastError = nil
            Logger.info("CloudKit \(type.label) completed")
        }
    }

    /// Parse CloudKit feil for detaljert diagnostikk
    private func parseCloudKitError(_ error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == CKErrorDomain {
            let code = CKError.Code(rawValue: nsError.code)
            switch code {
            case .internalError:
                return "⚠️ CloudKit INTERNAL ERROR - Apple server problem. Try restarting the app or wait 5-10 minutes. If it persists: check iCloud settings."
            case .quotaExceeded:
                return "CloudKit quota exceeded - too much data or too many operations"
            case .networkFailure, .networkUnavailable:
                return "Network error - check your internet connection"
            case .serviceUnavailable:
                return "CloudKit service unavailable - Apple server problems"
            case .requestRateLimited:
                return "Request rate limited - wait before trying again"
            case .zoneBusy:
                return "CloudKit zone busy - too many concurrent operations"
            case .batchRequestFailed:
                return "Batch request failed - too many records at once"
            case .limitExceeded:
                return "CloudKit limit exceeded - too many operations"
            case .zoneNotFound:
                return "CloudKit zone not found - sync setup problem"
            case .userDeletedZone:
                return "User deleted CloudKit zone"
            case .partialFailure:
                return "Partial failure - some records synced, others failed"
            case .serverRecordChanged:
                return "Record changed on server - conflict"
            case .accountTemporarilyUnavailable:
                return "iCloud account temporarily unavailable - check settings"
            default:
                return "CloudKit error [\(nsError.code)]: \(error.localizedDescription)"
            }
        }

        return error.localizedDescription
    }

    // MARK: - Public Methods

    /// Hent antall ord for å bekrefte at data er synkronisert
    func getWordCount() -> Int {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")

        do {
            return try context.count(for: request)
        } catch {
            Logger.error("Error counting words: \(error)")
            return 0
        }
    }
}

// MARK: - Supporting Types
struct SyncEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let date: Date
    let succeeded: Bool
    let error: Error?
    let errorDetails: String?
    let errorCode: Int?

    enum EventType {
        case `import`
        case export

        var icon: String {
            switch self {
            case .import: return "arrow.down.circle.fill"
            case .export: return "arrow.up.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .import: return "Import"
            case .export: return "Export"
            }
        }
    }
}
