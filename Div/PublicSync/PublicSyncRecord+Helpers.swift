// PublicSyncRecord+Helpers.swift
// Lokal bokføring av hva som er sendt til/hentet fra den delte Public CloudKit-databasen.
// Rører ikke ThaiWords/Sentence i det hele tatt — helt separat sporingstabell.
import CoreData

enum PublicSyncSourceType: Int16 {
    case word = 0
    case sentence = 1
}

enum PublicSyncDirection: Int16 {
    case export = 0
    case importFromPublic = 1
}

extension PublicSyncRecord {

    var sourceTypeValue: PublicSyncSourceType {
        get { PublicSyncSourceType(rawValue: sourceType) ?? .word }
        set { sourceType = newValue.rawValue }
    }

    var directionValue: PublicSyncDirection {
        get { PublicSyncDirection(rawValue: direction) ?? .export }
        set { direction = newValue.rawValue }
    }

    static func find(
        sourceId: UUID,
        direction: PublicSyncDirection,
        in context: NSManagedObjectContext
    ) -> PublicSyncRecord? {
        let request: NSFetchRequest<PublicSyncRecord> = PublicSyncRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND direction == %d", sourceId as CVarArg, direction.rawValue
        )
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Sjekker om et gitt Public-record allerede er importert lokalt (uavhengig av om thaiWord senere er endret).
    static func isAlreadyImported(publicRecordName: String, in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<PublicSyncRecord> = PublicSyncRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "publicRecordName == %@ AND direction == %d",
            publicRecordName, PublicSyncDirection.importFromPublic.rawValue
        )
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    /// Oppretter eller oppdaterer sporingsposten for en gitt kilde + retning. Kaller IKKE context.save().
    @discardableResult
    static func upsert(
        sourceId: UUID,
        sourceType: PublicSyncSourceType,
        direction: PublicSyncDirection,
        publicRecordName: String,
        in context: NSManagedObjectContext
    ) -> PublicSyncRecord {
        let record = find(sourceId: sourceId, direction: direction, in: context) ?? {
            let new = PublicSyncRecord(context: context)
            new.id = UUID()
            new.sourceId = sourceId
            return new
        }()
        record.sourceTypeValue = sourceType
        record.directionValue = direction
        record.publicRecordName = publicRecordName
        record.date = Date()
        return record
    }

    /// Alle ord som tidligere er eksportert — brukes av en fremtidig "Oppdater eksporterte ord"-knapp.
    static func exportedSourceIds(sourceType: PublicSyncSourceType, in context: NSManagedObjectContext) -> [UUID] {
        let request: NSFetchRequest<PublicSyncRecord> = PublicSyncRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceType == %d AND direction == %d",
            sourceType.rawValue, PublicSyncDirection.export.rawValue
        )
        let records = (try? context.fetch(request)) ?? []
        return records.compactMap { $0.sourceId }
    }
}
