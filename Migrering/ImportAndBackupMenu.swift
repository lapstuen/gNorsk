//
//  Backup.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/24/25.
import SwiftUI
import Foundation
import CoreData
//import Playgrounds

/// En handling som venter på bekreftelse fra brukeren før den faktisk kjøres.
private struct PendingAdminAction: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let isDangerous: Bool
    let action: () -> Void
}

/// Fullskjerm-bekreftelse: viser tittel + markdown-beskrivelse av hva knappen gjør,
/// med en "Start"-knapp nederst. Er handlingen farlig (endrer databasen), spør vi
/// ekstra én gang til før den faktisk kjøres.
private struct AdminActionConfirmationView: View {
    let pending: PendingAdminAction
    let onCancel: () -> Void
    let onConfirmed: () -> Void

    @State private var showDangerAlert = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(pending.title)
                        .font(.title.bold())
                    if pending.isDangerous {
                        Label("Changes the database", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    Text(LocalizedStringKey(pending.description))
                        .font(.body)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(spacing: 12) {
                Button {
                    if pending.isDangerous {
                        showDangerAlert = true
                    } else {
                        onConfirmed()
                    }
                } label: {
                    Text("Start")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(pending.isDangerous ? .red : .accentColor)

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .alert("Are you sure?", isPresented: $showDangerAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, run it", role: .destructive) {
                onConfirmed()
            }
        } message: {
            Text("This will change the database. This cannot easily be undone.")
        }
    }
}

public struct Backup: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context


    @State private var runFunction1 = false
    @State private var runFunction2 = false
    @Environment(\.dismiss) private var dismiss
    @State private var visDeleteView: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var deleteGroupIdText: String = ""
    @State private var isTranslatingAll = false
    @State private var translateAllProgress = ""
    @State private var showReportsView = false
    @State private var showExportToPublic = false
    @State private var showImportFromPublic = false
    @State private var pendingAction: PendingAdminAction?
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk

    private func requestConfirmation(
        title: String,
        description: String,
        isDangerous: Bool,
        action: @escaping () -> Void
    ) {
        pendingAction = PendingAdminAction(title: title, description: description, isDangerous: isDangerous, action: action)
    }

    // func openInGPoi(word: String) {
    //     let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    //     if let url = URL(string: "gpoi://word?text=\(encoded)") {
    //          UIApplication.shared.open(url, options: [:], completionHandler: nil)
    //      }
    //   }
    func openIngInfo(word: String) {
#if !DEBUG
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        // Del via App Group UserDefaults
        let shared = UserDefaults(suiteName: "group.no.1955.shared")
        shared?.set(encoded, forKey: "pendinggInfoSearch")
        // Åpne appen direkte
        if let appURL = URL(string: "file:///Applications/gInfo.app") {
            UIApplication.shared.open(appURL)
        }
        #endif
    }
    func openginfo() {
        guard let url = URL(string: "ginfo://word?text=test") else {
            print("❌ Ugyldig URL-format")
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            print("✅ ginfo:// kan åpnes – URL-skjemaet fungerer")
        } else {
            print("❌ ginfo:// kan IKKE åpnes – legg inn 'ginfo' i Info.plist > LSApplicationQueriesSchemes")
        }
    }
    // Setter "$" foran navnet på grupper som ikke har noen ord — de blir da
    // automatisk skjult fra standardvisningen i gruppevelgeren (samme mekanisme
    // som allerede skjuler @/#/$-grupper der), uten at gruppen slettes. Reversibelt:
    // fjern "$" fra navnet igjen for å vise gruppen på nytt.
    private func hideEmptyGroups() {
        let wordsReq = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        wordsReq.resultType = .dictionaryResultType
        wordsReq.propertiesToFetch = ["groupId"]
        wordsReq.returnsDistinctResults = true
        let dicts = (try? context.fetch(wordsReq) as? [[String: Any]]) ?? []
        let usedGroupIds = Set(dicts.compactMap { ($0["groupId"] as? NSNumber)?.int16Value })

        let groupsReq: NSFetchRequest<Group> = Group.fetchRequest()
        guard let allGroups = try? context.fetch(groupsReq) else { return }

        var hiddenCount = 0
        for group in allGroups {
            let name = group.groupName ?? ""
            // @ og # skal også behandles (og få $ foran hvis tomme) — kun
            // grupper som allerede ER $-skjult hoppes over, for å unngå
            // dobbel-prefiksing.
            guard !name.hasPrefix("$") else { continue }

            // Sjekk både gruppen selv OG de to knyttede følgegruppene (Word/Ok,
            // groupId+1 og +2) — ord kan ligge der via "Endre gruppetype", selv
            // om selve hovedgruppen har 0 ord direkte tilknyttet.
            let relatedIds: [Int16] = [group.groupId, group.groupId + 1, group.groupId + 2]
            guard !relatedIds.contains(where: { usedGroupIds.contains($0) }) else { continue }

            group.groupName = "$" + name
            hiddenCount += 1
        }

        guard hiddenCount > 0 else {
            Notifier.shared.show(.info, "No empty groups to hide")
            return
        }
        do {
            try context.save()
            Notifier.shared.show(.success, "Hid \(hiddenCount) empty groups")
        } catch {
            print("❌ Kunne ikke skjule tomme grupper: \(error)")
        }
    }

    // Oversetter alle ord i gruppen som for øyeblikket vises i GridView
    // (appState.sqlGruppeId) og som mangler engelsk eller morsmål-oversettelse.
    private func translateAllWords() {
        guard !isTranslatingAll else { return }
        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.predicate = NSPredicate(format: "groupId == %d", appState.sqlGruppeId)
        let groupWords = (try? context.fetch(req)) ?? []

        let wordsToTranslate = groupWords.filter { word in
            let missingEng = (word.englishWord ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let missingNor = (word.translation1 ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return missingEng || missingNor
        }
        guard !wordsToTranslate.isEmpty else {
            Notifier.shared.show(.success, "All words already have a translation")
            return
        }

        isTranslatingAll = true
        translateAllProgress = "0/\(wordsToTranslate.count)"

        Task {
            var done = 0
            for word in wordsToTranslate {
                let thai = word.thaiWord ?? ""
                guard !thai.isEmpty else { done += 1; continue }

                if (word.englishWord ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                   let eng = try? await performGoogleTranslate(text: thai, from: "th", to: "en") {
                    await MainActor.run { word.englishWord = eng }
                }

                if (word.translation1 ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                   let nor = try? await performGoogleTranslate(text: thai, from: "th", to: morsmaalLanguage.translationCode) {
                    await MainActor.run { word.translation1 = nor }
                }

                done += 1
                await MainActor.run {
                    translateAllProgress = "\(done)/\(wordsToTranslate.count)"
                    try? context.save()
                }
            }
            await MainActor.run {
                isTranslatingAll = false
                translateAllProgress = ""
                appState.refreshToken = UUID()
                Notifier.shared.show(.success, "Translated \(done) words")
            }
        }
    }

    /// Tidligere kalte denne funksjonen et uoffisielt Google-endepunkt direkte, med en manuell
    /// 300ms pause mellom hvert kall for å unngå Googles rate-limit (fjernet — unødvendig med
    /// Apple sin on-device Translation, se SwiftGeneral/AppleTranslationService.swift).
    private func performGoogleTranslate(text: String, from: String, to: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppleTranslationService.shared.translate(text: text, fromLanguage: from, toLanguage: to) { result in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                }
            }
        }
    }

    func auditEnglishWordField(context: NSManagedObjectContext, sampleCount: Int = 10) {
        let sampleThaiWords = loadJsonFile()
        var jsonIndex: [String: ThaiWordJSON] = [:]
        for item in sampleThaiWords {
            jsonIndex[item.word] = item
        }
        let total = (try? context.count(for: ThaiWords.fetchRequest())) ?? 0
        let emptyPred = NSPredicate(format: "englishWord == nil OR englishWord == ''")
        let emptyReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        emptyReq.predicate = emptyPred
        let emptyCount = (try? context.count(for: emptyReq)) ?? 0
        let filledCount = max(total - emptyCount, 0)
        print("📊 ThaiWords total=\(total), englishWord tom=\(emptyCount), utfylt(min)=\(filledCount)")
        var couldFill = 0
        if let missing = try? context.fetch(emptyReq) {
            for tw in missing {
                if let thai = tw.thaiWord, let hit = jsonIndex[thai] {
                    couldFill += 1
                    print("   🔎 Kan fylles: \(thai) → \(hit.english)")
                }
            }
        }
        print("📎 JSON-kryssjekk: kan fylles=\(couldFill)")
    }
    /*      gammel kode for oppslag mot g.info
     #if targetEnvironment(macCatalyst)
     guard let url = URL(string: "gInfo://word?text=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
     return
     }
     // Bruk UIApplication – dette virker på Catalyst!
     UIApplication.shared.open(url, options: [:]) { success in
     if !success {
     print("🔴 Feil: Kunne ikke åpne gPoiMac via gpoi:// (Mac Catalyst støtter det kanskje ikke direkte)")
     }
     }
     #else
     // iOS – vanlig åpning
     if let url = URL(string: "gInfo://word?text=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
     UIApplication.shared.open(url)
     }
     #endif
     */
    let thaiWords: [String] = [
        "ไป", "มา", "ดู", "มี", "ให้", "เอา", "อยู่", "เป็น", "ใช้", "รู้",
        "เห็น", "คิด", "ทำ", "บอก", "พูด", "ฟัง", "เขา", "เธอ", "เรา", "ใคร",
        "ไหน", "อะไร", "นี่", "นั่น", "โน่น", "ก็", "ยัง", "แล้ว", "จะ", "เคย",
        "ต้อง", "อย่า", "ไม่", "ใช่", "หรือ", "แต่", "ถ้า", "เพราะ", "กับ", "โดย",
        "จาก", "ให้", "ถึง", "เข้า", "ออก", "ขึ้น", "ลง", "อยู่", "แล้ว", "ที",
        "บน", "ใต้", "ใน", "นอก", "กัน", "ทุก", "บาง", "มาก", "น้อย", "ใหม่",
        "เก่า", "ดี", "เลว", "แรก", "สุด", "จริง", "เท็จ", "สวย", "งาม", "สูง",
        "ต่ำ", "ใหญ่", "เล็ก", "ดำ", "ขาว", "แดง", "น้ำ", "ไฟ", "ลม", "ดิน",
        "ฟ้า", "เดือน", "วัน", "ปี", "ร้อน", "เย็น", "หิว", "อิ่ม", "ตาย", "อยู่",
        "เจ็บ", "ปวด", "รัก", "เกลียด", "กลัว", "หัว", "มือ", "ตา", "หู", "ปาก", "เท้า"
    ]
    // let appDelegate = UIApplication.shared.delegate as! AppDelegate
    // let context = appDelegate.persistentContainer.viewContext
    let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
    public var body: some View {
        VStack {
            Button("exit") {
                dismiss()
            }
            ScrollView {
            VStack {
                Text("Reports").font(Font.title)
                Button("211 frewuent words") {
                    showReportsView = true
                }
                Divider()
                HStack{
                    Spacer()
                    IconTextButton(imageName: "Letters", title: "Empty words?", color: .green) {
                        requestConfirmation(
                            title: "Empty words?",
                            description: "**What it does:** Fetches up to 1000 words missing an English translation, and prints them to the console.\n\n**Why:** Words without an English translation are hard to use in exercises and search. This button lets you quickly see the scope of the problem before fixing it with one of the translation buttons.\n\n**Changes the database:** No — read-only.",
                            isDangerous: false
                        ) {
                        Task{
                            // 1) Hent bare tomme rader
                            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            req.predicate = NSPredicate(format: "englishWord == nil OR englishWord == ''")
                            req.sortDescriptors = [NSSortDescriptor(key: "insertDate", ascending: true)]
                            req.fetchLimit = 1000
                            var rows: [ThaiWords] = []
                            await context.perform { rows = (try? context.fetch(req)) ?? [] }
                            guard !rows.isEmpty else {
                                print("🏁 Ingen tomme englishWord i denne batchen.")
                                return
                            }
                            print("Rader uten english word: \(rows.count)")
                            for x in rows {
                                print("\(x.thaiWord ?? "?") - \(x.englishWord ?? "?")")
                            }
                        }
                        }
                    }


                    IconTextButton(imageName: "Letters", title: "Delete blanks!!", color: .red) {
                        requestConfirmation(
                            title: "Delete blanks!!",
                            description: "**What it does:** Permanently deletes all words where BOTH the Thai word and the English word are completely empty.\n\n**Why:** Failed imports or interrupted saves can sometimes create completely empty rows in the database. These have no value, take up space, and can show up as confusing blank cards in lists — this button cleans them up.\n\n**Changes the database:** Yes — deletes rows.",
                            isDangerous: true
                        ) {
                        Task {
                            // 1) Hent kandidater: begge feltene tomme (uten TRIM)
                            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            req.predicate = NSPredicate(
                                format: "(englishWord == nil OR englishWord == '') AND (thaiWord == nil OR thaiWord == '')"
                            )
                            req.fetchBatchSize = 200

                            var candidates: [ThaiWords] = []
                            await context.perform {
                                candidates = (try? context.fetch(req)) ?? []
                            }
                            guard !candidates.isEmpty else {
                                print("🏁 Ingen kandidater å slette.")
                                return
                            }

                            // 2) Filtrer med trimming og slett
                            var deleted = 0
                            await context.perform {
                                for tw in candidates {
                                    let en = (tw.englishWord ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let th = (tw.thaiWord ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                                    // bare slett hvis virkelig helt tomme
                                    if en.isEmpty && th.isEmpty {
                                        context.delete(tw)
                                        deleted += 1
                                    }
                                }

                                // 3) Lagre
                                if context.hasChanges {
                                    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                                    do {
                                        try context.save()
                                        print("🧹 Slettet \(deleted) tomme rader.")
                                    } catch {
                                        print("🛑 Save-feil ved sletting:", error.localizedDescription)
                                    }
                                } else {
                                    print("ℹ️ Ingen endringer å lagre.")
                                }
                            }

                            // 4) Verifiser etterpå (valgfritt)
                            let verifyReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            verifyReq.predicate = NSPredicate(format: "englishWord == nil OR englishWord == ''")
                            let rest = (try? await context.perform { try context.count(for: verifyReq) }) ?? -1
                            print("🧮 Rader uten englishWord etter slett: \(rest)")
                        }
                        }
                    }
                    Spacer()
                }.padding(20)
                // Flyttet hit fra "Misc"-menyen på gruppekortene i GridView
                HStack {
                    SFTextButton(systemName: "square.grid.2x2", title: "Show all", color: .blue) {
                        requestConfirmation(
                            title: "Show all",
                            description: "**What it does:** Switches the view to show all groups (`sqlGruppeId = -1`).\n\n**Why:** A quick shortcut to get back to a combined overview of all words, without having to navigate through the group picker manually.\n\n**Changes the database:** No.",
                            isDangerous: false
                        ) {
                        appState.sqlGruppeId = -1
                        }
                    }
                    SFTextButton(systemName: "globe",
                                       title: isTranslatingAll ? "Translating… \(translateAllProgress)" : "Translate all",
                                       color: .red) {
                        requestConfirmation(
                            title: "Translate all",
                            description: "**What it does:** Automatically translates (via Google Translate) all words in the current group that are missing an English or \(morsmaalLanguage.label) translation, and saves the result as it goes.\n\n**Why:** Translating many words by hand takes a long time. This button quickly fills in missing translations for a whole group, so the words become ready for use in exercises.\n\n**Changes the database:** Yes — writes `englishWord`/`translation1` and saves for each word.",
                            isDangerous: true
                        ) {
                        translateAllWords()
                        }
                    }
                    .disabled(isTranslatingAll)
                    SFTextButton(systemName: "eye.slash", title: "Hide empty groups", color: .red) {
                        requestConfirmation(
                            title: "Hide empty groups",
                            description: "**What it does:** Adds a `$` prefix to the name of every group (and its Word/Ok companion groups) that has no words, so they're hidden from the group picker.\n\n**Why:** Empty groups accumulate over time (testing, failed migrations). They clutter the group picker without adding anything. Hiding them (instead of deleting) keeps the list tidy while nothing is lost — you can always remove the `$` again to show the group.\n\n**Changes the database:** Yes — changes `groupName` on groups.",
                            isDangerous: true
                        ) {
                        hideEmptyGroups()
                        }
                    }
                }.padding(.horizontal, 20)
                // hstack 1. linje
                HStack {
                    SFTextButton(systemName: "number", title: "Update frequency rank", color: .red) {
                        requestConfirmation(
                            title: "Update frequency rank",
                            description: "**What it does:** Reads a number encoded at the start of the `ipa` field (format `#1234`) and writes that number into `frequencyRank`, for up to 500 words at a time.\n\n**Why:** Frequency data was originally stored temporarily inside the `ipa` field as a shortcut. This button moves that number over to the actual `frequencyRank` field, so frequency-based features (like Reports) actually work correctly.\n\n**Changes the database:** Yes — writes `frequencyRank` on many rows.",
                            isDangerous: true
                        ) {
                        Task {
                            // Først: tell hvor mange som gjenstår TOTALT
                            let countReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            countReq.predicate = NSPredicate(format: "ipa != nil AND ipa BEGINSWITH '#' AND frequencyRank == 0")
                            let gjenstår = (try? context.count(for: countReq)) ?? 0

                            // Tell også hvor mange som allerede ER oppdatert
                            let doneReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            doneReq.predicate = NSPredicate(format: "frequencyRank > 0")
                            let ferdig = (try? context.count(for: doneReq)) ?? 0

                            guard gjenstår > 0 else {
                                await MainActor.run {
                                    alertMessage = "Done! \(ferdig) words have a frequency rank"
                                    showAlert = true
                                }
                                return
                            }

                            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            req.predicate = NSPredicate(format: "ipa != nil AND ipa BEGINSWITH '#' AND frequencyRank == 0")
                            req.fetchLimit = 500
                            var rows: [ThaiWords] = []
                            await context.perform { rows = (try? context.fetch(req)) ?? [] }

                            var oppdatert = 0
                            for x in rows {
                                let ipa = x.ipa ?? ""
                                let femFørste = String(ipa.prefix(5))

                                if femFørste.count == 5, femFørste.first == "#" {
                                    let numberStr = String(femFørste.dropFirst())
                                    if let number = Int(numberStr) {
                                        x.frequencyRank = Int32(number)
                                        oppdatert += 1
                                    }
                                }
                            }

                            do {
                                try context.save()
                                await MainActor.run {
                                    alertMessage = "Updated \(oppdatert) words.\nRemaining: \(gjenstår - oppdatert)\nTotal done: \(ferdig + oppdatert)"
                                    showAlert = true
                                }
                            } catch {
                                await MainActor.run {
                                    alertMessage = "Error: \(error.localizedDescription)"
                                    showAlert = true
                                }
                            }
                        }
                        }
                    }

                    SFTextButton(systemName: "tag", title: "Fix tags format", color: .red) {
                        requestConfirmation(
                            title: "Fix tags format",
                            description: "**What it does:** Converts the old tags format to the new comma-separated format (`,tag1,tag2,`) for all words not already in the new format.\n\n**Why:** The tags format changed during the app's development to make search and filtering reliable. Words added before the change still have the old format, which breaks those features. This button migrates them to the new format.\n\n**Changes the database:** Yes — overwrites `tags` on many rows.",
                            isDangerous: true
                        ) {
                        Task {
                            // Finn alle ord med tags som IKKE starter med komma (gammelt format)
                            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                            req.predicate = NSPredicate(format: "tags != nil AND tags != '' AND NOT (tags BEGINSWITH ',')")

                            var oppdatert = 0
                            await context.perform {
                                if let rows = try? context.fetch(req) {
                                    for word in rows {
                                        if let oldTag = word.tags, !oldTag.isEmpty {
                                            // Konverter til nytt format: ",tag," eller ",tag1,tag2,"
                                            let tags = oldTag.components(separatedBy: ",").filter { !$0.isEmpty }
                                            if !tags.isEmpty {
                                                word.tags = "," + tags.joined(separator: ",") + ","
                                                oppdatert += 1
                                            }
                                        }
                                    }
                                    try? context.save()
                                }
                            }

                            await MainActor.run {
                                alertMessage = "Migrated \(oppdatert) tags to new format"
                                showAlert = true
                            }
                        }
                        }
                    }
                    IconTextButton(imageName: "Letters", title: "Export Python", color: .blue) {
                        requestConfirmation(
                            title: "Export Python",
                            description: "**What it does:** Exports all unique Thai words to a JSON file on disk, for use with PyThaiNLP.\n\n**Why:** Syllable and IPA generation is done with a Python library (PyThaiNLP) that doesn't exist in Swift. This button exports the words the app needs analyzed, so they can be run through Python and imported back with 'Import NLP Data'.\n\n**Changes the database:** No — read-only and writes a local file.",
                            isDangerous: false
                        ) {
                        ThaiWordsExporter.exportAllWords(context: context)
                        }
                    }

                }
                HStack {
                    SFTextButton(systemName: "pencil", title: "fill Missing English", color: .red) {
                        requestConfirmation(
                            title: "fill Missing English",
                            description: "**What it does:** Fetches up to 100 words without an English translation and fills them in automatically via a translation API, permanently (not a test run).\n\n**Why:** Words can come in without an English translation (e.g. via a quick import). Without a translation they're hard to learn from. This button fills in what's missing in bulk, instead of doing it word by word manually.\n\n**Changes the database:** Yes — writes `englishWord` and saves.",
                            isDangerous: true
                        ) {
                        Task {
                            await backfillMissingEnglish(context: context, limit: 100, dryRun: false) }
                        }
                    }
                    IconTextButton(imageName: "sparkles", title: "Import NLP Data", color: .red) {
                        requestConfirmation(
                            title: "Import NLP Data",
                            description: "**What it does:** Migrates old tags into the notes field, and imports syllables and IPA from thai_complete.json into Core Data.\n\n**Why:** The app's pronunciation features are built around syllable-level IPA (not word-level), and this data is generated externally with Python and must be imported. This button pulls the latest result from thai_complete.json into the database.\n\n**Changes the database:** Yes — updates/creates rows.",
                            isDangerous: true
                        ) {
                        // First: Migrate old data from tags → notes
                        let migrated = NLPDataImporter.migrateTagsToNotes(context: context)

                        // Then: Import syllables and IPA from thai_complete.json to Core Data
                        let result = NLPDataImporter.importFromThaiComplete(context: context)

                        // Show result
                        let message = """
                    ✅ NLP Data Import Complete!

                    Migrated: \(migrated)
                    Updated: \(result.updated)
                    Created: \(result.created)
                    Skipped: \(result.skipped)
                    Errors: \(result.errors)
                    """
                        Notifier.shared.show(.success, message)

                        // Show statistics
                        print(NLPDataImporter.getStatistics(context: context))
                        }
                    }
                    SFTextButton(systemName: "checkmark.seal", title: "Fix missing ID (UUID)", color: .red) {
                        requestConfirmation(
                            title: "Fix missing ID (UUID)",
                            description: "**What it does:** Gives all ThaiWords rows missing an `id` a new UUID.\n\n**Why:** A stable UUID is needed for CloudKit sync, editing, and group membership to work reliably. Some older rows may be missing this (e.g. from a migration before UUID was required). This button ensures every word has a valid identity.\n\n**Changes the database:** Yes.",
                            isDangerous: true
                        ) {
                        let fixed = fixMissingThaiWordIDs(context: context)
                        alertMessage = "Assigned an ID to \(fixed) words without one"
                        showAlert = true
                        }
                    }
                }.padding(.horizontal, 20)
                HStack {
                    SFTextButton(systemName: "icloud.and.arrow.up", title: "Export to Public", color: .blue) {
                        showExportToPublic = true
                    }
                    SFTextButton(systemName: "icloud.and.arrow.down", title: "Import from Public", color: .blue) {
                        showImportFromPublic = true
                    }
                    SFTextButton(systemName: "arrow.triangle.2.circlepath.circle", title: "Migrate Learning State", color: .red) {
                        requestConfirmation(
                            title: "Migrate Learning State",
                            description: "**What it does:** Sets `learningState` (new/learning/reviewing) for all words based on existing `dueAt`/`lastReviewedAt`/`repetitions`.\n\n**Why:** The spaced-repetition system uses `learningState` to decide whether a word is new, being learned, or due for review — and thus how it shows up in exercises. Words added before this field existed in the app, or that are missing a value here for other reasons, will be miscategorized (e.g. treated as brand new even though you've actually practiced them before). This button computes the correct state from existing review history, so the review schedule becomes accurate again.\n\n**Changes the database:** Yes — writes `learningState` on all words.",
                            isDangerous: true
                        ) {
                        InitializeLearningState.migrateAllWords(context: context)
                        }
                    }
                }.padding(.horizontal, 20)
                HStack {
                    SFTextButton(systemName: "calendar.badge.clock", title: "Initialize Modified Date", color: .red) {
                        requestConfirmation(
                            title: "Initialize Modified Date",
                            description: "**What it does:** Sets `modifiedDate` (to `insertDate`, or the current time) for all words missing it.\n\n**Why:** Features like the 'Recently edited' list and CloudKit's sync conflict resolution rely on `modifiedDate` always having a value. Older words from before this field was introduced are missing it, which can cause incorrect sorting or unexpected behavior during sync conflicts. This button fills in a sensible value wherever it's missing.\n\n**Changes the database:** Yes — writes `modifiedDate` where it's missing.",
                            isDangerous: true
                        ) {
                        InitializeLearningState.initializeModifiedDate(context: context)
                        }
                    }
                    SFTextButton(systemName: "wrench.and.screwdriver", title: "Fix words marked as sentence", color: .red) {
                        let count = WordTypeFrequencyFix.countMismatched(context: context)
                        requestConfirmation(
                            title: "Fix words marked as sentence (frequency 1–4000)",
                            description: "**What it does:** \(count) words have frequency 1–4000 but are marked as Sentence instead of Word. Corrects them to Word.\n\n**Why:** `wordType` (Word/Sentence) controls how a word is displayed and practiced in the app. The 4000 most frequent words should always be single words, not sentences — if any of them were mistakenly marked as Sentence (e.g. during import), they'll behave incorrectly in exercises. This button corrects such mismarkings.\n\n**Changes the database:** Yes — changes `wordType` on \(count) words.",
                            isDangerous: true
                        ) {
                        let fixed = WordTypeFrequencyFix.fixWordsMismarkedAsSentence(context: context)
                        Notifier.shared.show(.success, "Fixed \(fixed) words from Sentence to Word")
                        }
                    }
                }.padding(.horizontal, 20)
                HStack {
                    SFTextButton(systemName: "textformat.abc", title: "Import strong verbs", color: .red) {
                        requestConfirmation(
                            title: "Import strong verbs (group 1055)",
                            description: "**What it does:** Creates one word per strong verb infinitive (from `strongVerbForms` in DetailWordView.swift) in group 1055, with `thaiWord` set to the infinitive and all its inflected forms (preteritum + perfektum partisipp, e.g. \"drakk, drukket\") listed in `notes`. If a word with that infinitive already exists in the group, only its `notes` field is updated instead of creating a duplicate.\n\n**Why:** Strong verbs don't follow the regular suffix-stripping rules used for word lookup, so their inflected forms need their own entries pointing back to the infinitive, with the inflections kept visible in notes for reference.\n\n**Changes the database:** Yes — creates/updates rows in group 1055.",
                            isDangerous: true
                        ) {
                        let result = importStrongVerbs(context: context, groupId: 1055)
                        Notifier.shared.show(.success, "Strong verbs: created \(result.created), updated \(result.updated)")
                        }
                    }
                }.padding(.horizontal, 20)
            }
            HStack {
                SFTextButton(systemName: "folder.badge.plus", title: "Create group 0 (demo2)", color: .red) {
                    requestConfirmation(
                        title: "Create group 0 (demo2) + delete incorrect Demo group",
                        description: "**What it does:** Deletes the group named 'Demo', and creates a new group 0 named 'demo2' if it doesn't exist.\n\n**Why:** A one-time cleanup after a 'Demo' group was created incorrectly during early development. Corrects the group structure so the demo group has the right name and ID.\n\n**Changes the database:** Yes — deletes and creates groups.",
                        isDangerous: true
                    ) {
                    fixDemoGroups(context: context)
                    }
                }
                VStack(spacing: 4) {
                    SFTextButton(systemName: "trash.fill", title: "Delete single group", color: .red) {
                        guard let gid = Int16(deleteGroupIdText.trimmingCharacters(in: .whitespaces)) else {
                            alertMessage = "Invalid group ID"
                            showAlert = true
                            return
                        }
                        requestConfirmation(
                            title: "Delete single group",
                            description: "**What it does:** Deletes a single group with the given group ID (\(gid)) — but ONLY if the group has no words attached.\n\n**Why:** Groups created by mistake or during testing may need removing. The safety check (refuses if the group has words) prevents you from accidentally deleting a group with real data in it.\n\n**Changes the database:** Yes — deletes a group.",
                            isDangerous: true
                        ) {
                        alertMessage = deleteSingleGroup(groupId: gid, context: context)
                        showAlert = true
                        }
                    }
                    TextField("group ID (e.g. 0)", text: $deleteGroupIdText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }

            Text("Check and Fix").font(.headline)
            VStack(spacing: 8) {
                HStack {
                    SFTextButton(systemName: "magnifyingglass", title: "check duplicate thai words", color: .blue) {
                        requestConfirmation(
                            title: "check duplicate thai words",
                            description: "**What it does:** Counts and lists duplicate Thai words in the console.\n\n**Why:** Duplicates can arise when multiple import sources (Public sync, JSON import, manual entry) add the same word more than once. Duplicates give confusing results in search and detail views, since the app doesn't know which copy is the 'right' one. This button shows the scope of the problem without changing anything, so you know whether cleanup is needed.\n\n**Changes the database:** No — read-only.",
                            isDangerous: false
                        ) {
                        checkForThaiWordDuplicates(context: context)
                        }
                    }
                    SFTextButton(systemName: "trash", title: "DELETE duplicate thai words", color: .red) {
                        requestConfirmation(
                            title: "DELETE duplicate thai words",
                            description: "**What it does:** Permanently deletes duplicate Thai words, keeping only the best copy of each (with notes/image/newest date).\n\n**Why:** After 'check duplicate thai words' has shown that duplicates exist, this cleans them up — but not arbitrarily: it always keeps the copy with the most data (notes, image, or newest date), so you don't lose information in the cleanup.\n\n**Changes the database:** Yes — deletes rows.",
                            isDangerous: true
                        ) {
                        removeDuplicateThaiWords(context: context)
                        }
                    }
                }
            }
            .padding()
            .background(.gray.opacity(0.51))
            .frame(width: 400)
            .cornerRadius(30)
        }
        .sheet(isPresented: $visDeleteView) {
           // DeleteView() // Replace with your actual delete view
        }
        .sheet(isPresented: $showReportsView) {
            WiktionaryFrequencyReportView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showExportToPublic) {
            ExportToPublicView()
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 1000)
                #endif
        }
        .sheet(isPresented: $showImportFromPublic) {
            ImportFromPublicView()
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 1000)
                #endif
        }
        .fullScreenCover(item: $pendingAction) { pending in
            AdminActionConfirmationView(
                pending: pending,
                onCancel: { pendingAction = nil },
                onConfirmed: {
                    pending.action()
                    pendingAction = nil
                }
            )
        }
        .alert("Result", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        }
    }
}
func checkForThaiWordDuplicates(context: NSManagedObjectContext) {
    // Hent ALLE ThaiWords records
    let fetchRequest = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "thaiWord", ascending: true)]

    do {
        let allWords = try context.fetch(fetchRequest)

        // Tell forekomster av hver thaiWord
        var wordCount: [String: Int] = [:]
        for word in allWords {
            if let thai = word.thaiWord, !thai.isEmpty {
                wordCount[thai, default: 0] += 1
            }
        }

        // Finn duplikater (ord som forekommer mer enn én gang)
        let duplicates = wordCount.filter { $0.value > 1 }

        if duplicates.isEmpty {
            print("✅ Ingen duplikater funnet")
        } else {
            print("❗️Fant \(duplicates.count) duplikater:")
            for (word, count) in duplicates.sorted(by: { $0.value > $1.value }) {
                print("🔁 '\(word)' forekommer \(count) ganger")

                // Vis detaljer for hver duplikat
                let detailRequest = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
                detailRequest.predicate = NSPredicate(format: "thaiWord == %@", word)
                if let instances = try? context.fetch(detailRequest) {
                    for (index, instance) in instances.enumerated() {
                        let hasImage = instance.image != nil ? "🖼️" : "  "
                        let english = instance.englishWord ?? "—"
                        let date = instance.insertDate?.formatted() ?? "ukjent dato"
                        print("   \(index + 1). \(hasImage) engelsk: '\(english)', dato: \(date)")
                    }
                }
            }
        }
    } catch {
        print("❌ Feil ved sjekk av duplikater: \(error)")
    }
}

/// Sletter duplikate ThaiWords på tvers av ALLE grupper.
/// Designregel: Et thai-ord skal kun finnes én gang i databasen uansett hvilken gruppe det tilhører.
/// Samme ord i frekvensgruppe og Demo er et duplikat og skal ryddes opp.
/// Prioritet for hva som beholdes: notes > bilde > nyeste insertDate
func removeDuplicateThaiWords(context: NSManagedObjectContext) {
    print("🔍 Søker etter duplikater...")

    // 1. Hent ALLE ThaiWords for å telle duplikater korrekt
    let allWordsFetch = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
    allWordsFetch.sortDescriptors = [NSSortDescriptor(key: "thaiWord", ascending: true)]

    do {
        let allWords = try context.fetch(allWordsFetch)

        // Tell forekomster
        var wordCount: [String: Int] = [:]
        for word in allWords {
            if let thai = word.thaiWord, !thai.isEmpty {
                wordCount[thai, default: 0] += 1
            }
        }

        let duplicates = wordCount.filter { $0.value > 1 }

        if duplicates.isEmpty {
            print("✅ Ingen duplikater å slette")
            return
        }

        print("❗️Fant \(duplicates.count) duplikater som skal ryddes opp")
        var totalDeleted = 0

        // 2. For hvert duplikat, prioriter den med notes (Python NLP data)
        for (thaiWord, count) in duplicates {
            let wordFetch = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            wordFetch.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)

            guard let words = try? context.fetch(wordFetch), words.count > 1 else { continue }

            // Sorter etter prioritet: notes > bilde > nyeste dato
            let sorted = words.sorted { (a, b) -> Bool in
                let aHasNotes = !(a.notes?.isEmpty ?? true)
                let bHasNotes = !(b.notes?.isEmpty ?? true)

                if aHasNotes != bHasNotes {
                    return aHasNotes // Behold den med notes
                }

                let aHasImage = a.image != nil
                let bHasImage = b.image != nil

                if aHasImage != bHasImage {
                    return aHasImage // Behold den med bilde
                }

                // Behold nyeste
                return (a.insertDate ?? Date.distantPast) > (b.insertDate ?? Date.distantPast)
            }

            let toKeep = sorted[0]
            let toDelete = Array(sorted.dropFirst())

            print("🗑️ '\(thaiWord)': Beholder 1, sletter \(toDelete.count)")

            // Vis info om den vi beholder
            let hasNotes = !(toKeep.notes?.isEmpty ?? true) ? "📝 med notes" : "   uten notes"
            let hasImage = toKeep.image != nil ? "🖼️" : "  "
            let english = toKeep.englishWord ?? "—"
            print("   📌 Beholder: \(hasNotes) \(hasImage) engelsk: '\(english)'")

            // Slett resten
            for word in toDelete {
                let delNotes = !(word.notes?.isEmpty ?? true) ? "📝" : "  "
                let delImage = word.image != nil ? "🖼️" : "  "
                let delEnglish = word.englishWord ?? "—"
                print("   🗑️ Sletter: \(delNotes) \(delImage) engelsk: '\(delEnglish)'")
                context.delete(word)
                totalDeleted += 1
            }
        }

        // 3. Lagre endringer
        if context.hasChanges {
            try context.save()
            print("✅ Slettet totalt \(totalDeleted) duplikater")
            print("🎉 Database ryddet! Kjør 'sjekk duplikate thai word' for å verifisere")
        }

    } catch {
        print("❌ Feil ved sletting av duplikater: \(error)")
    }
}
/// Sletter ÉN enkelt gruppe (ikke hele tripletten) — for opprydding av feilaktige/foreldreløse
/// grupper (f.eks. gruppe 0). Trygghetssjekk: nekter hvis gruppen faktisk har ord på seg.
func deleteSingleGroup(groupId: Int16, context: NSManagedObjectContext) -> String {
    let wordsReq = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
    wordsReq.predicate = NSPredicate(format: "groupId == %d", groupId)
    let wordCount = (try? context.count(for: wordsReq)) ?? 0
    guard wordCount == 0 else {
        return "❌ Cannot delete group \(groupId) — it has \(wordCount) words."
    }

    let groupReq = NSFetchRequest<Group>(entityName: "Group")
    groupReq.predicate = NSPredicate(format: "groupId == %d", groupId)
    groupReq.fetchLimit = 1
    guard let group = try? context.fetch(groupReq).first else {
        return "ℹ️ No group found with id \(groupId)."
    }
    let name = group.groupName ?? "?"
    context.delete(group)
    do {
        try context.save()
        return "✅ Deleted group \(groupId) (\"\(name)\")."
    } catch {
        return "❌ Error while deleting: \(error.localizedDescription)"
    }
}

/// Oppretter gruppe 0 kalt "demo2" og sletter feil-opprettet gruppe med navn "Demo" (ID 1).
/// Gruppen "$1" (ID 1) skal beholdes — den er korrekt.
/// Gruppestruktur: viktige grupper er multiplum av 3 (3, 6, 9...).
/// Gruppe 0/1/2 er midlertidige/system-grupper. Ord i disse kan ryddes manuelt.
func fixDemoGroups(context: NSManagedObjectContext) {
    // 1. Slett gruppe med navn "Demo" eller "demo" (groupId=1 feil-opprettet)
    let delReq = NSFetchRequest<NSManagedObject>(entityName: "Group")
    delReq.predicate = NSPredicate(format: "groupName ==[c] 'demo'")
    do {
        let toDelete = try context.fetch(delReq)
        if toDelete.isEmpty {
            print("ℹ️ Ingen gruppe med navn 'Demo' funnet — ingenting å slette")
        } else {
            for g in toDelete {
                let gid = g.value(forKey: "groupId") ?? "?"
                let gname = g.value(forKey: "groupName") ?? "?"
                print("🗑️ Sletter gruppe: id=\(gid) navn=\(gname)")
                context.delete(g)
            }
        }
    } catch {
        print("❌ Feil ved henting av Demo-gruppe: \(error)")
        return
    }

    // 2. Opprett gruppe 0 = "demo2" hvis den ikke finnes
    let checkReq = NSFetchRequest<NSManagedObject>(entityName: "Group")
    checkReq.predicate = NSPredicate(format: "groupId == 0")
    checkReq.fetchLimit = 1
    do {
        if let existing = try context.fetch(checkReq).first {
            let name = existing.value(forKey: "groupName") ?? "?"
            print("ℹ️ Gruppe 0 finnes allerede: '\(name)' — hopper over opprettelse")
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "Group", in: context)!
            let newGroup = NSManagedObject(entity: entity, insertInto: context)
            newGroup.setValue(Int16(0), forKey: "groupId")
            newGroup.setValue("demo2", forKey: "groupName")
            newGroup.setValue(Int16(-1), forKey: "groupType")
            print("✅ Opprettet gruppe 0 'demo2'")
        }

        try context.save()
        print("💾 Lagret. Gruppe-opprydding fullført.")
    } catch {
        print("❌ Feil ved oppretting av gruppe 0: \(error)")
    }
}

//
//  backfillMissingEnglish.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/26/25.
//
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

/// Oppretter ett ord per infinitiv i strongVerbForms (se DetailWordView.swift), med alle bøyde
/// former (preteritum + perfektum partisipp) samlet i notes-feltet, i den oppgitte gruppen.
/// Idempotent: hvis ordet allerede finnes i gruppen, oppdateres bare notes-feltet i stedet for
/// å opprette en duplikat — trygt å kjøre flere ganger.
@discardableResult
func importStrongVerbs(context: NSManagedObjectContext, groupId: Int16) -> (created: Int, updated: Int) {
    var inflectionsByInfinitive: [String: [String]] = [:]
    for (form, infinitive) in strongVerbForms {
        inflectionsByInfinitive[infinitive, default: []].append(form)
    }

    var created = 0
    var updated = 0
    for (infinitive, forms) in inflectionsByInfinitive {
        let notesValue = forms.sorted().joined(separator: ", ")

        let checkReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        checkReq.predicate = NSPredicate(format: "thaiWord ==[c] %@ AND groupId == %d", infinitive, groupId)
        checkReq.fetchLimit = 1
        if let existing = try? context.fetch(checkReq).first {
            existing.notes = notesValue
            existing.modifiedDate = Date()
            updated += 1
            continue
        }

        let word = ThaiWords(context: context)
        word.id = UUID()
        word.thaiWord = infinitive
        word.notes = notesValue
        word.groupId = groupId
        word.wordType = 0
        word.insertDate = Date()
        word.modifiedDate = Date()
        created += 1
    }

    do {
        try context.save()
    } catch {
        print("❌ Feil ved lagring av sterke verb: \(error)")
    }
    return (created, updated)
}

/// Assign UUIDs to all ThaiWords that are missing an ID.
/// Returns the number of records updated.
@discardableResult
func fixMissingThaiWordIDs(context: NSManagedObjectContext) -> Int {
    let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    request.predicate = NSPredicate(format: "id == nil")
    do {
        let missing = try context.fetch(request)
        guard !missing.isEmpty else {
            print("✅ No ThaiWords missing IDs.")
            return 0
        }
        var updated = 0
        for w in missing {
            w.id = UUID()
            updated += 1
        }
        try context.save()
        print("✅ Assigned UUIDs to \(updated) ThaiWords that were missing IDs.")
        return updated
    } catch {
        print("❌ Failed to fix missing ThaiWord IDs: \(error)")
        return 0
    }
}

#Preview {
    // In-memory Core Data (trygt i preview)
    let container = NSPersistentContainer(name: "gNorsk")
    let desc = NSPersistentStoreDescription(); desc.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [desc]
    container.loadPersistentStores(completionHandler: {_,_ in})
    let ctx = container.viewContext
    let appState = AppState()

    return NavigationStack {
        Backup()
            .environment(\.managedObjectContext, ctx)
            .environment(appState)
            .background(Color(.systemBackground)) // unngå “grå” blank canvas
    }
    .frame(width: 430, height: 932) // iPhone 14/15
}
