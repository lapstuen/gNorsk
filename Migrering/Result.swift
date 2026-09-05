//
//  Result.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/26/25.
//


import CoreData

/// Fyller inn englishWord for rader som mangler, ved å kalle `translate("th"->"en")`.
/// - Parameters:
///   - limit: hvor mange rader per kjøring (batch)
///   - concurrency: maks samtidige nettverkskall
///   - dryRun: true = bare tell/print, false = skriv til Core Data
///   - translate: din Google Translate-funksjon
func backfillEnglishWithTranslator(
    context: NSManagedObjectContext,
    limit: Int = 25,
    concurrency: Int = 3,
    dryRun: Bool = true,
    translate: @Sendable @escaping (_ thai: String) async throws -> String?
) async {
    // ...

    // 1) Hent bare tomme rader
    let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    fetch.predicate = NSPredicate(format: "englishWord == nil OR englishWord == ''")
    fetch.sortDescriptors = [NSSortDescriptor(key: "insertDate", ascending: true)]
    fetch.fetchLimit = limit

    var items: [ThaiWords] = []
    await context.perform {
        items = (try? context.fetch(fetch)) ?? []
    }
    guard !items.isEmpty else {
        print("🏁 Ingen mangler i denne batchen.")
        return
    }

    print("🔧 Backfill via Google Translate — batch=\(items.count), dryRun=\(dryRun)")

    // 2) Oversett i parallell, men begrens concurrency
    struct Result { let objectID: NSManagedObjectID; let value: String? }
    var results = [Result]()
    results.reserveCapacity(items.count)
    await withTaskGroup(of: Result?.self) { group in
        let semaphore = AsyncSemaphore(value: concurrency)

        for tw in items {
            let objectID = tw.objectID
            await semaphore.wait()

            group.addTask {
                // jobb ...
                var thai = ""
                await context.perform {
                    thai = (try? context.existingObject(with: objectID) as? ThaiWords)?
                        .flatMap { $0.thaiWord } ?? ""
                }
                guard !thai.isEmpty else {
                    await semaphore.signal()            // <— FLYTTET HIT
                    return Result(objectID: objectID, value: nil)
                }

                var value: String? = nil
                do {
                    value = try await translate(thai)?.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    // logg ev. feil
                }

                await semaphore.signal()                // <— OG HIT
                return Result(objectID: objectID, value: value?.isEmpty == false ? value : nil)
            }
        }

        for await r in group { if let r { results.append(r) } }
    }
    // 3) Skriv tilbake (idempotent)
    var written = 0, canFill = 0
    await context.perform {
        for r in results {
            guard let value = r.value else { continue }
            canFill += 1
            if dryRun { continue }

            if let tw = try? context.existingObject(with: r.objectID) as? ThaiWords {
                // skriv kun hvis fortsatt tom
                if (tw.englishWord == nil) || (tw.englishWord?.isEmpty == true) {
                    tw.englishWord = value
                    written += 1
                }
            }
        }
        if !dryRun, context.hasChanges {
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            try? context.save()
        }
    }

    print("✅ GT-backfill: kan fylles=\(canFill) | skrevet=\(written) | dryRun=\(dryRun)")
}

/// Enkel async semafor
actor AsyncSemaphore {
    private var value: Int
    init(value: Int) { self.value = value }
    func wait() async {
        while value == 0 { await Task.yield() }
        value -= 1
    }
    func signal() { value += 1 }
}
