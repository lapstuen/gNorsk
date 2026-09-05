import Foundation
import CoreData

final class CoreDataWriteMonitor {
    static let shared = CoreDataWriteMonitor()

    private let dbg = SegmentationDebugLogger.shared
    private var isStarted = false
    private var observer: NSObjectProtocol?

    func startMonitoring() {
        guard !isStarted else { return }
        isStarted = true
        observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { [weak self] note in
            self?.handleDidSave(note)
        }
        dbg.log("🛰️ CoreDataWriteMonitor started")
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleDidSave(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let inserted = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updated  = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deleted  = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []

        func describe(_ obj: NSManagedObject) -> String {
            let entity = obj.entity.name ?? "<unknown>"
            if let word = obj as? ThaiWords {
                let thai = word.thaiWord ?? "<nil>"
                let eng  = word.englishWord ?? "<nil>"
                return "ThaiWords(thai='\(thai)', english='\(eng)')"
            }
            return entity
        }

        if !inserted.isEmpty {
            dbg.log("💾 CoreData didSave: INSERTED count=\(inserted.count)")
            for obj in inserted { dbg.log("  + \(describe(obj))") }
        }
        if !updated.isEmpty {
            dbg.log("💾 CoreData didSave: UPDATED count=\(updated.count)")
            for obj in updated { dbg.log("  ~ \(describe(obj))") }
        }
        if !deleted.isEmpty {
            dbg.log("💾 CoreData didSave: DELETED count=\(deleted.count)")
            for obj in deleted { dbg.log("  - \(describe(obj))") }
        }

        // Targeted alert for the reported case
        if inserted.contains(where: { ($0 as? ThaiWords)?.thaiWord == "เราไป" }) {
            dbg.log("⚠️ DETECTED WRITE of ThaiWords 'เราไป' during save")
            dbg.logCallStack(prefix: "STACK when ThaiWords('เราไป') was inserted")
        }
    }
}
