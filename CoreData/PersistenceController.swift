//
//  PersistenceController.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/18/25.
//
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    // 🔁 In-memory container for previews
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Create test data
        for i in 1...10 {
            let word = ThaiWords(context: context)
            word.id = UUID()
            word.thaiWord = ["ไป", "มา", "กิน", "ดื่ม", "นอน", "เดิน", "วิ่ง", "อ่าน", "เขียน", "พูด"][i-1]
            word.englishWord = ["go", "come", "eat", "drink", "sleep", "walk", "run", "read", "write", "speak"][i-1]
            word.ipa = ["pai", "maa", "kin", "dɯ̀ːm", "nɔɔn", "dɤːn", "wîŋ", "àan", "khǐan", "phûut"][i-1]
            word.sentence = word.thaiWord
            word.groupId = 1
            word.insertDate = Date().addingTimeInterval(-Double(i) * 3600) // Stagger creation times
            word.modifiedDate = Date().addingTimeInterval(-Double(10 - i) * 1800) // Recent modifications

            // Set learning states for variety
            if i <= 3 {
                word.learningState = LearningState.new.rawValue
            } else if i <= 6 {
                word.learningState = LearningState.learning.rawValue
                word.dueAt = Date().addingTimeInterval(-3600) // Due 1 hour ago
                word.repetitions = 1
            } else {
                word.learningState = LearningState.reviewing.rawValue
                word.dueAt = Date().addingTimeInterval(-86400) // Due 1 day ago
                word.repetitions = 3
            }
        }

        try? context.save()
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // ⚠️ NSPersistentCloudKitContainer krasjer i Xcode Previews (sandkassen der
        // mangler CloudKit-entitlements/nettverkstilgang). Bruk vanlig
        // NSPersistentContainer for in-memory previews, ekte CloudKit-container
        // kun for den delte, faktiske app-instansen.
        let container: NSPersistentContainer = inMemory
            ? NSPersistentContainer(name: "gNorsk")
            : NSPersistentCloudKitContainer(name: "gNorsk")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Aktiver lightweight migration
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            if !inMemory {
                // Påkrevd nå som appen har to iCloud-containere deklarert (gNorsk + gThai-speilet,
                // se GThaiReferenceStore) — uten dette blir CKContainer.default() tvetydig.
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.lapstuen.gNorsk"
                )
            }
        }

        container.loadPersistentStores { (_, error) in
            if let error = error as NSError? {
                fatalError("❌ Core Data error: \(error), \(error.userInfo)")
            }

            // 🧠 Viktig for 133020-konflikter (fra AppDelegate):
            let ctx = container.viewContext
            ctx.automaticallyMergesChangesFromParent = true
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            ctx.undoManager = nil
            ctx.shouldDeleteInaccessibleFaults = true

            if !inMemory {
                PersistenceController.migrateWordTypesIfNeeded(context: ctx)
                PersistenceController.normalizeThaiTextIfNeeded(context: ctx)
                FrequencyGroupSeeder.seedIfNeeded(context: ctx)
                // Kjøres hver oppstart (ikke bare én gang): reinstallering av appen
                // nullstiller UserDefaults-flagget over, men ikke CloudKit-dataene, så
                // FrequencyGroupSeeder kan lage nye duplikater av de samme 46 gruppene
                // ved hver reinstallering. Denne rydder opp uansett hvor mange ganger
                // det skjer igjen.
                PersistenceController.dedupeGroupsWithSameGroupId(context: ctx)
            }
        }

        self.container = container
    }

    // One-time migration: NFC-normalize all Thai text fields to fix hidden duplicates
    private static func normalizeThaiTextIfNeeded(context: NSManagedObjectContext) {
        let key = "thaiNFCNormalizationDone_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        guard let words = try? context.fetch(fetch) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        var count = 0
        for word in words {
            var changed = false
            if let t = word.thaiWord {
                let n = t.precomposedStringWithCanonicalMapping
                if n != t { word.thaiWord = n; changed = true }
            }
            if let s = word.sentence {
                let n = s.precomposedStringWithCanonicalMapping
                if n != s { word.sentence = n; changed = true }
            }
            if changed { count += 1 }
        }

        if count > 0, (try? context.save()) != nil {
            print("✅ Thai NFC-normalisering: \(count) ord oppdatert")
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // Kjøres hver oppstart: fjern duplikate frekvensgrupper (samme groupId) som kan
    // ha oppstått fordi FrequencyGroupSeeder sitt "første oppstart"-flagg ligger i
    // lokal UserDefaults og dermed nullstilles ved reinstallering av appen, mens
    // CloudKit-dataene består. Trygt å kjøre gjentatte ganger — gjør ingenting hvis
    // det ikke finnes duplikater.
    private static func dedupeGroupsWithSameGroupId(context: NSManagedObjectContext) {
        let req: NSFetchRequest<Group> = Group.fetchRequest()
        req.predicate = NSPredicate(
            format: "groupId >= %d AND groupId <= %d",
            FrequencyGroupSeeder.frequencyGroupBaseId, FrequencyGroupSeeder.adjectiveGroupId
        )
        guard let seededGroups = try? context.fetch(req), !seededGroups.isEmpty else { return }

        let byGroupId = Dictionary(grouping: seededGroups, by: \.groupId)
        var deletedCount = 0
        for (_, duplicates) in byGroupId where duplicates.count > 1 {
            for duplicate in duplicates.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        guard deletedCount > 0 else { return }
        do {
            try context.save()
            print("✅ dedupeGroupsWithSameGroupId: fjernet \(deletedCount) duplikate frekvensgrupper")
        } catch {
            print("❌ dedupeGroupsWithSameGroupId: feil under lagring: \(error)")
        }
    }

    // One-time migration: classify existing words by English text
    private static func migrateWordTypesIfNeeded(context: NSManagedObjectContext) {
        let key = "wordTypeMigrationDone_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetch.predicate = NSPredicate(format: "wordType == 0")
        guard let words = try? context.fetch(fetch), !words.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        for word in words {
            let eng = word.englishWord ?? ""
            if eng.trimmingCharacters(in: .whitespacesAndNewlines).contains(" ") {
                word.wordType = 1
            }
        }

        if (try? context.save()) != nil {
            print("✅ wordType-migrering fullført: \(words.count) ord behandlet")
        }
        UserDefaults.standard.set(true, forKey: key)
    }
}
