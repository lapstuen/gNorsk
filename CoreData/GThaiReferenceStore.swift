//
//  GThaiReferenceStore.swift
//  gNorsk
//

import CoreData

/// Read-only speil av gThai sin CloudKit-database (iCloud.com.lapstuen.gThai), brukt som
/// siste fallback-oppslag når et ord ikke finnes i gNorsk sin egen database ennå.
/// Skjemaet er identisk med gNorsk sitt (gNorsk startet som en kopi av gThai), så vi
/// gjenbruker gNorsk sin egen .xcdatamodeld i stedet for å vedlikeholde en egen kopi.
///
/// ⚠️ Skal ALDRI skrives til — kun leses fra. Lagring hit ville synkronisert tilbake
/// til gThai sin faktiske, delte database.
struct GThaiReferenceStore {
    static let shared = GThaiReferenceStore()

    let container: NSPersistentCloudKitContainer

    private init() {
        guard let modelURL = Bundle.main.url(forResource: "gNorsk", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("❌ Fant ikke gNorsk sin Core Data-modell for gThai-speilet")
        }

        let container = NSPersistentCloudKitContainer(name: "gThaiMirror", managedObjectModel: model)

        if let description = container.persistentStoreDescriptions.first {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.lapstuen.gThai"
            )
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("❌ gThai-speil Core Data-feil: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true

        self.container = container
    }

    var context: NSManagedObjectContext { container.viewContext }

    /// Diagnostikk: antall poster i speilet akkurat nå — brukt i "About gNorsk" for å
    /// bekrefte at CloudKit-synken faktisk har hentet ned data.
    func recordCount() -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
        return (try? context.count(for: request)) ?? 0
    }

    /// Diagnostikk: sjekk om en gitt tekst finnes i speilets `translation1`-felt (case-insensitive
    /// eksakt match) — samme felt/logikk som fallback-oppslaget i DetailWordView bruker. Kun for
    /// bekreftelse i "About gNorsk", ikke del av selve oppslags-logikken.
    func debugLookup(_ text: String) -> (found: Bool, englishWord: String?) {
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "translation1 ==[c] %@", text)
        request.fetchLimit = 1
        guard let match = try? context.fetch(request).first else {
            return (false, nil)
        }
        return (true, match.englishWord)
    }
}
