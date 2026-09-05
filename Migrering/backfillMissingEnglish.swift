//
//  backfillMissingEnglish.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/26/25.
//


import CoreData

/// Fyller inn englishWord for rader som mangler. Trygg å kjøre flere ganger.
func backfillMissingEnglish(
    context: NSManagedObjectContext,
    limit: Int = 100,          // 57 → la stå 100 så tar den alt som er igjen
    dryRun: Bool = true,       // start med true for å se hva som skjer
    pauseMs: UInt64 = 150      // snill rate mot API-et
) async {
    // 1) Hent bare tomme rader
    let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    req.predicate = NSPredicate(format: "englishWord == nil OR englishWord == ''")
    req.sortDescriptors = [NSSortDescriptor(key: "insertDate", ascending: true)]
    req.fetchLimit = limit

    var rows: [ThaiWords] = []
    await context.perform { rows = (try? context.fetch(req)) ?? [] }
    guard !rows.isEmpty else {
        print("🏁 Ingen tomme englishWord i denne batchen.")
        return
    }

    print("🔧 GT-backfill: fant \(rows.count) tomme (dryRun=\(dryRun))")

    var written = 0
    for tw in rows {
        // hent thai på context-tråden
        var thai = ""
        await context.perform { thai = tw.thaiWord ?? "" }
        guard !thai.isEmpty else { continue }

        do {
            if let en = try await translateThaiToEnglish(thai)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !en.isEmpty, en != "-", en != "—", en != "?" {

                if dryRun {
                    print("🔎 \(thai) → \(en)")
                } else {
                    await context.perform {
                        // skriv kun hvis fortsatt tom (idempotent)
                        if tw.englishWord == nil || tw.englishWord?.isEmpty == true {
                            tw.englishWord = en
                            written += 1
                        }
                    }
                }
            }
        } catch {
            print("⚠️ Oversettelsesfeil for '\(thai)': \(error)")
        }

        // liten pause for å være snill med kvoten
        try? await Task.sleep(nanoseconds: pauseMs * 1_000_000)
    }

    if !dryRun {
        await context.perform {
            if context.hasChanges {
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                try? context.save()
            }
        }
        print("✅ Skrev \(written) nye oversettelser.")
    }
}