import SwiftUI
import CoreData
import UIKit

// kan du se på hvor mange endringer jeg må gjøre  // var filterThaiWords: [String]? = nil -> var filtrerteId: [NSManagedObjectID] = []
struct GridView: View {
    var groupId: Int16? = nil
    var filtrerteId: [NSManagedObjectID] = []
    // Visningsnavn når vi viser en filtrerteId-basert liste (ordliste/søkeresultat)
    // i stedet for en ekte gruppe — vises i toppteksten så det ikke ser ut som man
    // står i en gruppe.
    var listName: String? = nil
    // Satt til true kun når GridView er appens rot (åpnet direkte ved oppstart) —
    // da finnes det ingenting å gå tilbake til, så tilbakeknappen er overflødig.
    var isRootView: Bool = false

    private let exerciseMode: Bool
    private let useEnhancedLearning: Bool
    var onBack: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var valgtOrd: ThaiWords?
    @State private var moveToPinnedGroup = true
    @State private var sheetInput: WordInput?

    @State private var selectedDatatype: Datatype = .notSet
    @State private var frequencyRange: (min: Int, max: Int)? = nil
    // Fylles av scanForMissingFrequency() EN gang, ETTER at gitteret har fått lastet
    // ferdig med den opprinnelige frequencyRange-verdien — se forklaring der.
    @State private var missingFrequencyWordIDs: Set<NSManagedObjectID> = []
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @State private var containerSize: CGSize = .zero

    @State private var showMenuResult = false
    @State private var menuResultValue: String = ""
    @State private var menuResultWord: String = ""
    @State private var wordPendingGroupChange: ThaiWords?
    @State private var groupYoutubeUrl: String? = nil
    @State private var safariURL: URL? = nil
    @State private var showSafari = false
    @State private var showSlettAlleAlert = false
    @State private var showResetUnexpectedFrequencyAlert = false
    @State private var showSelectGroupFromGrid = false
    @State private var showMainMenu = false
    @State private var showVoiceDictation = false
    @State private var showCreateNewWord = false
    @State private var visSokeGrid = false
    @State private var showExerciseLauncher = false
    @State private var showRecentlyEdited = false
    @State private var showVideoSync = false
    // Enkel, billig valideringssjekk (ingen skanning av ord) — hovedgruppen skal alltid
    // være delelig med 3 (se createNewGroupId() i GLFunctions.swift), med unntak av
    // frekvensgrupper som har en helt egen ID-ordning. Rødt er kun et varsel, ikke en fix.
    @State private var groupIdErrorDetected = false
    @State private var showTranslation = false
    // Flyttet inn fra MainAppView sin hamburger-meny (som nå er utilgjengelig
    // siden Griden er blitt appens rot) — se "Om gNorsk"/"Admin"-punktene i
    // Div-menyen under. Review Due/Læringsliste flyttet videre inn i
    // ExerciseLauncherView (øvingsvinduet).
    @State private var showAbout = false
    @State private var showWordLists = false
    @State private var visBackupSheet = false
    @State private var showGroupWordsList = false
    @State private var visDebug = false
    @State private var admin = AdminManager.shared
    @State private var sortOrder: GridSortOrder = .standard
    // Alltid "Alle" som utgangspunkt — både ved første visning og hver gang gruppen
    // byttes (se onChange(of: appState.sqlGruppeId) under).
    @State private var wordTypeFilter: Int16 = -1  // -1=alle, 0=ord, 1=setning

    enum Datatype: String, CaseIterable {
        case notSet
        case id
        case list
        case objectIDs
    }

    enum GridSortOrder {
        case standard, norsk, engelsk
    }

    @FetchRequest private var words: FetchedResults<ThaiWords>

    init(
            groupId: Int16? = nil,
            filtrerteId: [NSManagedObjectID] = [],
            listName: String? = nil,
            exerciseMode: Bool = false,
            useEnhancedLearning: Bool = true,
            isRootView: Bool = false,
            onBack: (() -> Void)? = nil
        ) {
            self.groupId = groupId
            self.filtrerteId = filtrerteId
            self.listName = listName
            self.exerciseMode = exerciseMode
            self.useEnhancedLearning = useEnhancedLearning
            self.isRootView = isRootView
            self.onBack = onBack

            let now = Date()
            var predicates: [NSPredicate] = []

            if let gid = groupId {
                predicates.append(NSPredicate(format: "groupId == %d", gid))
                // behold din tidligere semantikk for selectedDatatype
                // (om du ønsker å sette @State i init, gjør det trygt slik:)
                _selectedDatatype = State(initialValue: .id)
            } else if !filtrerteId.isEmpty {
                predicates.append(NSPredicate(format: "self IN %@", filtrerteId))
                _selectedDatatype = State(initialValue: .objectIDs)
            } else {
                _selectedDatatype = State(initialValue: .notSet)
                // ingen ekstra predicate
            }

            if exerciseMode {
                // Øvelses-modus: bare kort som er due (eller nye uten dueAt)
                predicates.append(NSPredicate(format: "dueAt == nil OR dueAt <= %@", now as NSDate))
            }

            let predicate: NSPredicate = predicates.isEmpty
                ? NSPredicate(value: true)
                : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let sortDescriptors: [NSSortDescriptor] = exerciseMode
            ? [
                NSSortDescriptor(key: #keyPath(ThaiWords.dueAt), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.repetitions), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.thaiWord), ascending: true)
              ]
            : [
                NSSortDescriptor(key: #keyPath(ThaiWords.notes),     ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.thaiWord), ascending: true)
              ]

            _words = FetchRequest(
                entity: ThaiWords.entity(),
                sortDescriptors: sortDescriptors,
                predicate: predicate
            )
        }

    private func startLearningAllNew() {
        let now = Date()
        var count = 0
        for word in aktiveOrd where word.learningState == LearningState.new.rawValue {
            word.learningState = LearningState.learning.rawValue
            word.learningStep = 0
            word.dueAt = now
            word.lastReviewedAt = now
            count += 1
        }
        guard count > 0 else {
            Notifier.shared.show(.info, "All words already started")
            return
        }
        do {
            try context.save()
            Notifier.shared.show(.success, "Started practicing \(count) words")
        } catch {
            print("❌ Kunne ikke starte øving: \(error)")
        }
    }

    // Nullstiller frequencyRank for ord som er markert røde i gitteret (se
    // isMissingFrequency/hasUnexpectedFrequency i GridItem.swift) — ord som har en registrert
    // frekvens selv om vi IKKE står i en frekvensgruppe (datakontaminering, se undersøkelsen av
    // PublicImportService/ExportToPublicView). Kjøres kun på de ordene som faktisk vises akkurat
    // nå (aktiveOrd) — gruppe for gruppe, bevisst IKKE en global operasjon over hele databasen.
    private func resetUnexpectedFrequencyForVisibleWords() {
        guard frequencyRange == nil else {
            Notifier.shared.show(.info, "This is a frequency group — nothing to reset here")
            return
        }
        var count = 0
        for word in aktiveOrd where word.getFrequencyRank() != nil {
            word.frequencyRank = 0
            count += 1
        }
        guard count > 0 else {
            Notifier.shared.show(.info, "No words with unexpected frequency found")
            return
        }
        do {
            try context.save()
            appState.refreshToken = UUID()
            Notifier.shared.show(.success, "Reset frequency to 0 for \(count) word(s)")
        } catch {
            Notifier.shared.show(.error, "Could not save: \(error.localizedDescription)")
        }
    }

    private func slettAlleOrd() {
        let thaiTexts = aktiveOrd.compactMap { $0.thaiWord }.filter { !$0.isEmpty }

        // Fjern referanser til disse ordene fra tags-feltet i alle andre ThaiWords
        if !thaiTexts.isEmpty {
            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            // Søk med komma på begge sider for å sikre eksakt ord-match, ikke delstreng
            // Tags er lagret som ",กิน,นอน," så ",กิน," matcher kun det komplette ordet
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
                thaiTexts.map { NSPredicate(format: "tags CONTAINS %@", ",\($0),") }
            )
            if let references = try? context.fetch(req) {
                for ref in references {
                    for thai in thaiTexts {
                        ref.removeTag(thai)
                    }
                }
            }
        }

        aktiveOrd.forEach { context.delete($0) }
        do {
            try context.save()
            appState.refreshToken = UUID()
        } catch {
            print("❌ Kunne ikke slette alle ord: \(error)")
        }
    }

    // Tvinger hele gruppen til å hente ferske verdier fra persistent store —
    // brukes når CloudKit har synket data (f.eks. bilder) på en annen enhet,
    // men denne enhetens NSManagedObject-cache fortsatt viser gamle verdier.
    private func reloadGroup() {
        context.refreshAllObjects()
        appState.refreshToken = UUID()
    }

    // Ren lesing — skriver ALDRI noe til frequencyRank. Kjøres i egen render-runde
    // (DispatchQueue.main.async) etter at gitteret har lastet, for å markere ord som
    // mangler frekvens helt (word.getFrequencyRank() == nil), basert utelukkende på det
    // som faktisk ligger lagret i databasen.
    private func scanForMissingFrequency() {
        if showPrint { print("🟢 scanForMissingFrequency() CALLED — frequencyRange=\(String(describing: frequencyRange)), words.count=\(words.count), refreshToken=\(appState.refreshToken)") }
        guard frequencyRange != nil else {
            missingFrequencyWordIDs = []
            if showPrint { print("🟢 scanForMissingFrequency() — frequencyRange er nil, missingFrequencyWordIDs tømt") }
            return
        }
        var result: Set<NSManagedObjectID> = []
        for word in words {
            // context.refreshAllObjects() har vist seg upålitelig for å hente ferske verdier fra
            // persistent store (kjent, dokumentert Core Data-begrensning — se også den lignende,
            // udokumenterte buggen i shouldRefreshRefetchedObjects, FB6161838). Eksplisitt
            // per-objekt refresh(_:mergeChanges:false) er den anbefalte, pålitelige måten å tvinge
            // et objekt til å hente fra persistent store på nytt, i stedet for å stole på en
            // potensielt foreldet verdi som allerede ligger i minnet/radbufferen.
            context.refresh(word, mergeChanges: false)
            let rank = word.getFrequencyRank()
            let isMissing = rank == nil
            if showPrint { print("🟢   word=\(word.thaiWord ?? "?") objectID=\(word.objectID) frequencyRank(raw)=\(word.frequencyRank) getFrequencyRank()=\(String(describing: rank)) isMissing=\(isMissing)") }
            if isMissing {
                result.insert(word.objectID)
            }
        }
        missingFrequencyWordIDs = result
        if showPrint { print("🟢 scanForMissingFrequency() DONE — markerte \(result.count) av \(words.count) ord som missing. IDs: \(result)") }
    }

    private func groupExists(_ groupId: Int16) -> Bool {
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        return (try? context.fetch(req).first) != nil
    }

    // Enkel algoritme, ingen skanning av ord: hovedgruppen (valgtGruppeId) skal alltid
    // være delelig med 3, unntatt for frekvensgrupper (helt egen ID-ordning). Kalles kun
    // når valgtGruppeId endres, ikke ved hver re-render.
    private func checkGroupIdValidity() {
        guard appState.valgtGruppeId % 3 != 0 else {
            groupIdErrorDetected = false
            return
        }
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", appState.valgtGruppeId)
        req.fetchLimit = 1
        if let group = try? context.fetch(req).first, group.isFrequencyGroup {
            groupIdErrorDetected = false
        } else {
            groupIdErrorDetected = true
        }
    }

    @ViewBuilder
    private func groupTypeMenuItems(for word: ThaiWords) -> some View {
        let currentGroupId: Int16 = word.groupId
        let baseGroupId: Int16 = Int16((Int(currentGroupId) / 3) * 3)
        let groupType: Int = Int(currentGroupId % 3)
        let venteGroupId: Int16 = baseGroupId + 1
        let okGroupId: Int16 = baseGroupId + 2

        Button {
            word.groupId = baseGroupId
            do { try context.save() } catch { print("❌ Kunne ikke endre gruppe: \(error)") }
            appState.refreshToken = UUID()
        } label: {
            HStack {
                Text("Normal group (ID: \(baseGroupId))")
                if groupType == 0 { Image(systemName: "checkmark") }
            }
        }
        .disabled(groupType == 0)

        if groupExists(venteGroupId) {
            Button {
                word.groupId = venteGroupId
                do { try context.save() } catch { print("❌ Kunne ikke endre gruppe: \(error)") }
                appState.refreshToken = UUID()
            } label: {
                HStack {
                    Text("Waiting group (ID: \(venteGroupId))")
                    if groupType == 1 { Image(systemName: "checkmark") }
                }
            }
            .disabled(groupType == 1)
        }

        if groupExists(okGroupId) {
            Button {
                word.groupId = okGroupId
                do { try context.save() } catch { print("❌ Kunne ikke endre gruppe: \(error)") }
                appState.refreshToken = UUID()
            } label: {
                HStack {
                    Text("OK group (ID: \(okGroupId))")
                    if groupType == 2 { Image(systemName: "checkmark") }
                }
            }
            .disabled(groupType == 2)
        }
    }

    private func openYouTube(baseUrl: String, seconds: Int? = nil) {
        #if targetEnvironment(macCatalyst)
        Group.openYouTube(baseUrl: baseUrl, seconds: seconds)
        #else
        if let u = Group.youtubeURL(baseUrl: baseUrl, seconds: seconds) {
            safariURL = u
            showSafari = true
        }
        #endif
    }
    
/*
    init(groupId: Int16? = nil, filtrerteId: [NSManagedObjectID] = []) {
        self.groupId = groupId
        self.filtrerteId = filtrerteId

        print("🔍 GridView init: groupId=\(String(describing: groupId)), filtrerteId=\(filtrerteId.count)")

        if let groupId = groupId {
            selectedDatatype = .id
            _words = FetchRequest(
                entity: ThaiWords.entity(),
                sortDescriptors: [
                    NSSortDescriptor(keyPath: \ThaiWords.sentence, ascending: true),
                    NSSortDescriptor(keyPath: \ThaiWords.thaiWord, ascending: true)
                ],
                predicate: NSPredicate(format: "groupId == %d", groupId)
            )
        } else if !filtrerteId.isEmpty {
            selectedDatatype = .objectIDs
            _words = FetchRequest(
                entity: ThaiWords.entity(),
                sortDescriptors: [],
                predicate: NSPredicate(value: false)
            )
        } else {
            selectedDatatype = .notSet
            _words = FetchRequest(
                entity: ThaiWords.entity(),
                sortDescriptors: [],
                predicate: NSPredicate(value: false)
            )
        }
    }
*/
    /// Viser alltid riktige ord avhengig av om det er gruppe-id eller thai-ord-filtrering
    private var aktiveOrd: [ThaiWords] {
        var base: [ThaiWords]
        switch selectedDatatype {
        case .id, .list:
            base = Group.sortedChronologically(Array(words))
        case .objectIDs:
            base = filtrerteId.compactMap { oid in
                (try? context.existingObject(with: oid) as? ThaiWords)
            }
        case .notSet:
            return []
        }
        switch sortOrder {
        case .norsk:
            base.sort { ($0.translation1 ?? "").localizedStandardCompare($1.translation1 ?? "") == .orderedAscending }
        case .engelsk:
            base.sort { ($0.englishWord ?? "").localizedStandardCompare($1.englishWord ?? "") == .orderedAscending }
        case .standard:
            break
        }
        guard wordTypeFilter >= 0 else { return base }
        return base.filter { $0.wordType == wordTypeFilter }
    }

    /// Kopierer thai-ordene som er synlige akkurat nå (etter gjeldende filtrering,
    /// uansett om kilden er en gruppe, søkeresultater eller en annen ordliste) til
    /// utklippstavlen som en JSON-array — samme format som Word Lists-filene, slik
    /// at det kan limes rett inn i "Words (one per line)"-feltet der.
    private func copyVisibleWordsAsJSON() {
        let words = aktiveOrd.compactMap { $0.thaiWord }
        guard !words.isEmpty else {
            Notifier.shared.show(.info, "No words to copy")
            return
        }
        guard let data = try? JSONEncoder().encode(words),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UIPasteboard.general.string = json
        Notifier.shared.show(.success, "Copied \(words.count) words")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: groupIdErrorDetected
                    ? Gradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)])
                    : Gradient(colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.9), Color.indigo.opacity(0.9)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea()

            GeometryReader { geo in
                let spacing: CGFloat = 8
                let hasYouTube = groupYoutubeUrl != nil && !(groupYoutubeUrl?.isEmpty ?? true)
                // Må stemme eksakt med .padding(.horizontal, spacing) på LazyVGrid lenger
                // ned (samme variabel, ikke en gjettet/hardkodet verdi som kan komme ut av
                // synk med den faktiske paddingen igjen).
                let horizontalPadding = spacing * 2
                let availableWidth = geo.size.width - horizontalPadding
                // iPhone: fast 3 i bredden (bekreftet stabilt etter fiksen over).
                // iPad/Mac: adaptivt som før — flere kolonner når vinduet gjøres bredere.
                let cardWidth: CGFloat = 200
                let isPhone = UIDevice.current.userInterfaceIdiom == .phone
                let numberOfColumns: Int = {
                    if hasYouTube { return 2 }
                    if isPhone { return 3 }
                    return max(2, Int(availableWidth / (cardWidth + spacing)))
                }()
                let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: numberOfColumns)
                // Eksakt bredde per kolonne. Håndheves strengt (fast bredde + clipping) i
                // ThaiGridItem, slik at internt innhold (lang tekst osv.) som ellers ikke
                // ville krympet, aldri kan tvinge kortet bredere enn kolonnen — det var
                // nettopp det "maxWidth: .infinity" IKKE hindret.
                let actualCardWidth = (availableWidth - CGFloat(numberOfColumns - 1) * spacing) / CGFloat(numberOfColumns)

                VStack(spacing: 10) {
                    // Toppmeny med tilbakeknapp og gruppe-info
                    HStack {
                        if !isRootView {
                            Button("←") {
                                if let onBack { onBack() } else { dismiss() }
                            }
                            .foregroundStyle(.black)
                            .keyboardShortcut(.escape, modifiers: [])
                        }

                        if let url = groupYoutubeUrl, !url.isEmpty {
                            Button {
                                openYouTube(baseUrl: url)
                            } label: {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.red)
                                    .imageScale(.large)
                            }
                        }

                        Spacer()

                        if selectedDatatype != .objectIDs {
                            Button {
                                showSelectGroupFromGrid = true
                            } label: {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }.keyboardShortcut(.escape, modifiers: [])
                        }

                        Button {
                            visSokeGrid = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }

                        Button {
                            showExerciseLauncher = true
                        } label: {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.red)
                                .clipShape(Circle())
                        }

                        Button {
                            showRecentlyEdited = true
                        } label: {
                            Image(systemName: "doc.badge.clock")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }

                        if hasYouTube {
                            Button {
                                showVideoSync = true
                            } label: {
                                Image(systemName: "list.bullet.below.rectangle")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        }

                        Menu {
                            Button {
                                showAbout = true
                            } label: {
                                Label("About gNorsk", systemImage: "info.circle")
                            }

                            if admin.isAdmin {
                                Button {
                                    visBackupSheet = true
                                } label: {
                                    Label("Admin", systemImage: "lock.shield")
                                }
                            }

                            Button {
                                visDebug = true
                            } label: {
                                Label("Syllable tests", systemImage: "ladybug")
                            }

                            Button {
                                showWordLists = true
                            } label: {
                                Label("Word Lists", systemImage: "list.bullet.rectangle.portrait")
                            }

                            Divider()
                            Menu {
                                Toggle(isOn: Binding(
                                    get: { appState.sqlGruppeId == appState.valgtGruppeId },
                                    set: { isOn in
                                        guard isOn else { return }
                                        let gid = appState.valgtGruppeId
                                        words.nsPredicate = NSPredicate(format: "groupId == %d", gid)
                                        appState.sqlGruppeId = gid
                                        let req: NSFetchRequest<Group> = Group.fetchRequest()
                                        req.predicate = NSPredicate(format: "groupId == %d", gid)
                                        req.fetchLimit = 1
                                        if let group = try? context.fetch(req).first {
                                            groupYoutubeUrl = group.youtubeUrl
                                        }
                                    }
                                )) {
                                    Text("Main group")
                                }
                                Toggle(isOn: Binding(
                                    get: { appState.sqlGruppeId == appState.valgtGruppeId + 1 },
                                    set: { if $0 { appState.sqlGruppeId = appState.valgtGruppeId + 1 } }
                                )) {
                                    Text("Word")
                                }
                                Toggle(isOn: Binding(
                                    get: { appState.sqlGruppeId == appState.valgtGruppeId + 2 },
                                    set: { if $0 { appState.sqlGruppeId = appState.valgtGruppeId + 2 } }
                                )) {
                                    Text("Ok")
                                }
                            } label: {
                                if groupIdErrorDetected {
                                    Label("Group type", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                } else {
                                    Text("Group type")
                                }
                            }
                            Menu("Type") {
                                Toggle(isOn: Binding(
                                    get: { wordTypeFilter == -1 },
                                    set: { if $0 { wordTypeFilter = -1 } }
                                )) {
                                    Text("All")
                                }
                                Toggle(isOn: Binding(
                                    get: { wordTypeFilter == 0 },
                                    set: { if $0 { wordTypeFilter = 0 } }
                                )) {
                                    Text("Word")
                                }
                                Toggle(isOn: Binding(
                                    get: { wordTypeFilter == 1 },
                                    set: { if $0 { wordTypeFilter = 1 } }
                                )) {
                                    Text("Sentence")
                                }
                            }

                            if appState.pinnedGruppeId > 0 {
                                Button("Remove pinned group") {
                                    appState.pinnedGruppeId = -1
                                    appState.refreshToken = UUID()
                                }
                            }
                            Divider()
                            Button {
                                appState.visAlleDetaljer.toggle()
                            } label: {
                                Label(appState.visAlleDetaljer ? "Show images only" : "Show all information",
                                      systemImage: appState.visAlleDetaljer ? "checkmark" : "")
                                    .foregroundColor(appState.visAlleDetaljer ? .blue : .primary)
                            }
                            Divider()
                            Menu("Sort") {
                                Button {
                                    sortOrder = .norsk
                                } label: {
                                    Label("Sort \(morsmaalLanguage.label)", systemImage: sortOrder == .norsk ? "checkmark" : "")
                                        .foregroundColor(sortOrder == .norsk ? .blue : .primary)
                                }
                                Button {
                                    sortOrder = .engelsk
                                } label: {
                                    Label("Sort English", systemImage: sortOrder == .engelsk ? "checkmark" : "")
                                        .foregroundColor(sortOrder == .engelsk ? .blue : .primary)
                                }
                                if sortOrder != .standard {
                                    Divider()
                                    Button("Reset sorting") { sortOrder = .standard }
                                }
                            }
                            Divider()
                            
                            
                            
                            
                            
                            
                            Menu("Misc") {
                                
                                
                                
                                
                                Button {
                                    showGroupWordsList = true
                                } label: {
                                    Label("List words in group", systemImage: "list.bullet.rectangle")
                                }

                                Button {
                                    copyVisibleWordsAsJSON()
                                } label: {
                                    Label("Copy word list (JSON)", systemImage: "doc.on.doc")
                                }

                                Button {
                                    startLearningAllNew()
                                } label: {
                                    Label("Start practicing all", systemImage: "brain.head.profile")
                                }

                                Button("Delete all cards", role: .destructive) {
                                    showSlettAlleAlert = true
                                }

                                Button(role: .destructive) {
                                    showResetUnexpectedFrequencyAlert = true
                                } label: {
                                    Label("Reset unexpected frequency (red cards)", systemImage: "arrow.counterclockwise.circle")
                                }

                                Divider()

                                Button {
                                    if let url = URL(string: "galpha://") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Label("Letters", systemImage: "textformat.abc")
                                }
                            }
                        } label: {
                            Image(systemName: "line.horizontal.3")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }
                        .menuIndicator(.hidden)

                    }
                    .padding(.horizontal)

                    HStack {
                        Spacer()
                        if selectedDatatype == .id {
                            Text("[\(g.getGroupname(groupId: appState.sqlGruppeId)) #\(appState.sqlGruppeId)📌\(g.getGroupname(groupId: appState.pinnedGruppeId))] count: \(words.count)")
                                .font(.headline)
                                .foregroundStyle(.black)
                        }
                        if selectedDatatype == .objectIDs {
                            Text("[\(listName ?? "List")] count: \(aktiveOrd.count)")
                                .font(.headline)
                                .foregroundStyle(.black)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    // Veldig liten avstand til raden over og til griden under.
                    .padding(.top, -6)
                    .padding(.bottom, -6)

                    // Grid
                    ScrollView {
                        if aktiveOrd.isEmpty {
                            Text("🔍 No words found")
                                .padding()
                        } else {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                ForEach(aktiveOrd, id: \.objectID) { word in
                                    ThaiGridItem(word: word, moveToPinnedGroup: $moveToPinnedGroup, frequencyRange: frequencyRange, isMissingFrequency: missingFrequencyWordIDs.contains(word.objectID), hideImage: hasYouTube, cardWidth: actualCardWidth)
                                        // Tvinger SwiftUI til å lage kortet HELT på nytt (ikke bare oppdatere
                                        // det eksisterende) hver gang missing-status endrer seg for akkurat
                                        // dette ordet — vanlig state-propagering til denne parameteren har
                                        // vist seg upålitelig (fargen endret seg tidvis uten at dataen gjorde
                                        // det, og omvendt), så vi tvinger fram et helt friskt view i stedet.
                                        .id("\(word.objectID)-\(missingFrequencyWordIDs.contains(word.objectID))")
                                        .environment(appState)
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            if let url = groupYoutubeUrl, !url.isEmpty {
                                                Button {
                                                    let secs = word.notes.flatMap { Group.timestampToSeconds($0) }
                                                    openYouTube(baseUrl: url, seconds: secs)
                                                } label: {
                                                    Label("Start video", systemImage: "play.rectangle.fill")
                                                }
                                                Divider()
                                            }
                                            Button {
                                                reloadGroup()
                                            } label: {
                                                Label("Reload group", systemImage: "arrow.clockwise")
                                            }

                                            Divider()

                                            Button("Copy word") {
                                                let t = word.thaiWord ?? ""
                                                #if canImport(UIKit)
                                                UIPasteboard.general.string = t
                                                #endif
                                                if showPrint { print("📋 Copied to clipboard: \(t)") }
                                            }

                                            Button("menu two") {
                                                menuResultValue = "menu two"
                                                menuResultWord = word.thaiWord ?? ""
                                                showMenuResult = true
                                            }

                                            Button("menu three") {
                                                menuResultValue = "menu three"
                                                menuResultWord = word.thaiWord ?? ""
                                                showMenuResult = true
                                            }

                                            Divider()

                                            Menu("Change group type") {
                                                groupTypeMenuItems(for: word)
                                            }

                                            Divider()

                                            Button("Change group…") {
                                                wordPendingGroupChange = word
                                            }
                                        }
                                        .onTapGesture {
                                            valgtOrd = word
                                        }
                                }
                            }
                            .id(appState.visAlleDetaljer ? 1 : 0) // tving re-render
                            // Tving selve griden til nøyaktig den målte bredden. Uten
                            // dette beregner LazyVGrid sine egne kolonnegrenser ut fra
                            // hva DEN får tildelt av omgivelsene (kan avvike fra det jeg
                            // regner ut), uavhengig av bredden jeg tvinger på kortene.
                            .frame(width: availableWidth)
                            .padding(.horizontal, spacing)
                            .padding(.vertical)
                        }
                    }
                }
                // Verktøylinjeraden øverst (tilbake-knapp, chunk-knapper, hamburger,
                // gruppevelger-knapp) har for mye fast bredde til sammen til å få plass
                // på iPhone. VStack tilpasser seg da til det bredeste barnet sitt, og
                // "maxWidth: .infinity" hindrer IKKE det (samme feil som med kortene) —
                // den setter bare en øvre grense, ikke en nedre. Tving derfor hele siden
                // til nøyaktig skjermbredden, med clipping som sperre.
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { containerSize = geo.size }
                .onChange(of: geo.size) { _, newSize in containerSize = newSize }
            }
            .id(appState.refreshToken)
            .navigationBarBackButtonHidden(true)
            .sheet(item: $valgtOrd) { word in
                let input = WordInput(from: word)
                DetailWordView(initialWord: input, isNested: false, allowVideoNavigation: filtrerteId.isEmpty)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .catalystSheetFrame(width: 1000, height: 1300)
                    #else
                    .presentationSizing(.page)
                    #endif
            }
            .sheet(isPresented: $showMenuResult) {
                PressedValueView(value: menuResultValue, word: menuResultWord)
            }
#if targetEnvironment(macCatalyst)
            .sheet(item: $wordPendingGroupChange) { w in
                let content = SelectGroup(appState: appState) { selected in
                    w.groupId = selected.groupId
                    do {
                        try context.save()
                    } catch {
                        print("❌ Kunne ikke endre gruppe: \(error)")
                    }
                    appState.refreshToken = UUID()
                }
                .environment(\.managedObjectContext, context)

                content
                    .frame(
                        width: (containerSize.width > 0 ? containerSize.width : 800) * 0.9,
                        height: (containerSize.height > 0 ? containerSize.height : 700) * 0.9
                    )
                    .presentationSizing(.form)
            }
#else
            .fullScreenCover(item: $wordPendingGroupChange) { w in
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    SelectGroup(appState: appState) { selected in
                        w.groupId = selected.groupId
                        do {
                            try context.save()
                        } catch {
                            print("❌ Kunne ikke endre gruppe: \(error)")
                        }
                        appState.refreshToken = UUID()
                    }
                    .environment(\.managedObjectContext, context)
                    .frame(
                        width: min(((containerSize.width == .zero ? UIScreen.main.bounds.size : containerSize).width) * 0.9, 900),
                        height: min(((containerSize.height == .zero ? UIScreen.main.bounds.size : containerSize).height) * 0.9, 900)
                    )
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                }
            }
#endif

            // ── Flytende knapper (bottom): oversett / legg til ord / mic ──
            VStack {
                Spacer()
                HStack {
                    Button {
                        showTranslation = true
                    } label: {
                        Image(systemName: "translate")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.blue))
                            .shadow(color: Color.blue.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 24)

                    Spacer()

                    Button {
                        showCreateNewWord = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.blue))
                            .shadow(color: Color.blue.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showVoiceDictation = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.red))
                            .shadow(color: Color.red.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 28)
            }
            .allowsHitTesting(true)
        }
        #if !targetEnvironment(macCatalyst)
        // Swipe ned for å gå tilbake — kun iOS/touch. På Mac Catalyst tolker denne
        // gesten musebevegelsen når man velger et menyvalg langt nede i en dropdown
        // (f.eks. "Ok") som en ekte swipe-ned, og lukker vinduet ved en feiltakelse.
        // Mac har uansett tilbake-knapp + Escape-snarvei, så gesten er overflødig der.
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // Swipe ned for å gå tilbake - må være rask og tydelig nedover
                    if value.translation.height > 120 &&
                       abs(value.translation.width) < 50 &&
                       value.predictedEndTranslation.height > 200 {
                        if let onBack { onBack() } else { dismiss() }
                    }
                }
        )
        #endif
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                SafariView(url: url)
            }
        }
        .fullScreenCover(isPresented: $showSelectGroupFromGrid) {
            SelectGroup(appState: appState) { group in
                appState.valgtGruppeId = group.groupId
                appState.valgtGruppeNavn = group.groupName ?? "?"
                appState.sqlGruppeId = group.groupId
                showSelectGroupFromGrid = false
            }
        }
        .fullScreenCover(isPresented: $showMainMenu) {
            MainAppView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 600, minHeight: 500)
                #elseif os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .fullScreenCover(isPresented: $showWordLists) {
            CustomWordListsView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $visBackupSheet) {
            Backup()
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .presentationSizing(.fitted)
                .frame(minWidth: 500, idealWidth: 600, maxWidth: 1000,
                       minHeight: 600, idealHeight: 800, maxHeight: 1200)
                #elseif os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(isPresented: $showGroupWordsList) {
            NavigationStack {
                GroupWordsListView(
                    groupId: appState.sqlGruppeId,
                    groupName: g.getGroupname(groupId: appState.sqlGruppeId)
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showGroupWordsList = false }
                    }
                }
            }
            .environment(appState)
            .environment(\.managedObjectContext, context)
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 800, minHeight: 1000)
            #elseif os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .followWindowOverlay(isPresented: $visDebug) { close, size in
            QuickThaiSyllableTestsView()
                .frame(width: min(900, size.width - 80),
                       height: min(1100, size.height - 80))
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 20)
                .overlay(alignment: .topTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                }
        }
        .sheet(isPresented: $showCreateNewWord) {
            CreateWordView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minHeight: 900, idealHeight: 900, maxHeight: .infinity)
                #elseif os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .fullScreenCover(isPresented: $visSokeGrid) {
            SearchView()
                .background(Color.white.ignoresSafeArea())
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .onChange(of: appState.pendingSearchText) { _, newValue in
            // Samme mønster som MainAppView tidligere brukte for å åpne søk med forhåndsutfylt
            // tekst — men GridView er nå appens rot, så MainAppView sin tilsvarende lytting kjører
            // ikke lenger.
            if newValue != nil {
                visSokeGrid = true
            }
        }
        .sheet(isPresented: $showExerciseLauncher) {
            ExerciseLauncherView(
                filtrerteId: selectedDatatype == .objectIDs ? filtrerteId : [],
                listName: listName
            )
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $showRecentlyEdited) {
            RecentlyEditedView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
       // .sheet(isPresented: $showVideoSync) {
       //     VideoSyncedTranscriptView(groupId: appState.sqlGruppeId)
       //         .environment(appState)
       //         .environment(\.managedObjectContext, context)
       //         #if targetEnvironment(macCatalyst)
       //         .catalystSheetFrame(width: 2000, height: 1800)
       //         #else
       //         .presentationDetents([.large])
       //         .presentationDragIndicator(.visible)
       //         #endif
       // }
        
        .fullScreenCover(isPresented: $showVideoSync) {
            VideoSyncedTranscriptView(groupId: appState.sqlGruppeId)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showTranslation) {
            TranslationView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minHeight: 900, idealHeight: 900, maxHeight: .infinity)
                #elseif os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(isPresented: $showVoiceDictation) {
            NavigationStack {
                VoiceDictationView()
            }
           #if targetEnvironment(macCatalyst) || os(iPad)
            .frame(minWidth: 1600, minHeight: 1000)
            #endif
            
            
        }
        .alert("Delete all \(aktiveOrd.count) visible cards?", isPresented: $showSlettAlleAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete all cards", role: .destructive) { slettAlleOrd() }
        } message: {
            Text("Deletes only the cards currently shown. This action cannot be undone.")
        }
        .alert("Reset unexpected frequency for visible cards?", isPresented: $showResetUnexpectedFrequencyAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset to 0", role: .destructive) { resetUnexpectedFrequencyForVisibleWords() }
        } message: {
            Text("Sets frequencyRank to 0 for words shown here that have a frequency value even though this isn't a frequency group. Only applies to the cards currently visible in this list. This cannot be undone.")
        }
        .wireNotifications()
        .onAppear {
            if showPrint { print("🟣 GridView.onAppear START — groupId=\(String(describing: groupId)), refreshToken=\(appState.refreshToken)") }
            Notifier.shared.hide()
            checkGroupIdValidity()
            if let gid = groupId {
                let request: NSFetchRequest<Group> = Group.fetchRequest()
                request.predicate = NSPredicate(format: "groupId == %d", gid)
                request.fetchLimit = 1
                if let group = try? context.fetch(request).first {
                    frequencyRange = group.getFrequencyRange()
                    groupYoutubeUrl = group.youtubeUrl
                    if showPrint { print("🟣 GridView.onAppear — frequencyRange satt til \(String(describing: frequencyRange))") }
                    // Tving full omtegning av kort-gitteret (samme mekanisme som .id(appState.refreshToken)
                    // på LazyVGrid lenger ned) — uten dette blir "mangler frekvens"-fargen først riktig
                    // etter at man har besøkt og forlatt et kort, siden frequencyRange settes for sent
                    // til at gitteret tegner om seg selv med korrekt farge ved første visning.
                    appState.refreshToken = UUID()
                    if showPrint { print("🟣 GridView.onAppear — bumpet refreshToken til \(appState.refreshToken)") }
                } else {
                    if showPrint { print("🟣 GridView.onAppear — fant IKKE Group for groupId=\(gid)") }
                }
            } else {
                if showPrint { print("🟣 GridView.onAppear — groupId er nil, hopper over frequencyRange-oppslag") }
            }
            if showPrint { print("🟣 GridView.onAppear — planlegger scanForMissingFrequency() via DispatchQueue.main.async") }
            DispatchQueue.main.async {
                if showPrint { print("🟣 GridView.onAppear async — FØR scanForMissingFrequency()") }
                scanForMissingFrequency()
                if showPrint { print("🟣 GridView.onAppear async — ETTER scanForMissingFrequency(), missingFrequencyWordIDs.count=\(missingFrequencyWordIDs.count)") }
            }
        }
        .onChange(of: appState.valgtGruppeId) { _, _ in
            checkGroupIdValidity()
        }
        .onChange(of: appState.sqlGruppeId) { oldId, newId in
            if showPrint { print("🐛 onChange sqlGruppeId: \(oldId) -> \(newId)") }
            wordTypeFilter = -1
            if newId == -1 {
                words.nsPredicate = nil
                frequencyRange = nil
                missingFrequencyWordIDs = []
                if showPrint { print("🟣 onChange sqlGruppeId — newId==-1, tømte frequencyRange/missingFrequencyWordIDs") }
            } else {
                words.nsPredicate = NSPredicate(format: "groupId == %d", newId)
                let req: NSFetchRequest<Group> = Group.fetchRequest()
                req.predicate = NSPredicate(format: "groupId == %d", newId)
                req.fetchLimit = 1
                if let group = try? context.fetch(req).first {
                    groupYoutubeUrl = group.youtubeUrl
                    frequencyRange = group.getFrequencyRange()
                    if showPrint { print("🟣 onChange sqlGruppeId — frequencyRange satt til \(String(describing: frequencyRange)) for newId=\(newId)") }
                } else {
                    frequencyRange = nil
                    if showPrint { print("🟣 onChange sqlGruppeId — fant IKKE Group for newId=\(newId)") }
                }
                // Se forklaring i .onAppear over.
                appState.refreshToken = UUID()
                if showPrint { print("🟣 onChange sqlGruppeId — bumpet refreshToken til \(appState.refreshToken), planlegger scanForMissingFrequency()") }
                DispatchQueue.main.async {
                    if showPrint { print("🟣 onChange sqlGruppeId async — FØR scanForMissingFrequency()") }
                    scanForMissingFrequency()
                    if showPrint { print("🟣 onChange sqlGruppeId async — ETTER scanForMissingFrequency(), missingFrequencyWordIDs.count=\(missingFrequencyWordIDs.count)") }
                }
            }
        }
        .onChange(of: appState.refreshToken) { oldToken, newToken in
            // scanForMissingFrequency() ble tidligere KUN kjørt én gang, ved gruppe-åpning
            // (.onAppear/.onChange(of: appState.sqlGruppeId)) — men refreshToken endres langt
            // oftere enn det (f.eks. hver gang man besøker og forlater et kort), og HELE
            // kort-gitteret bygges da på nytt via .id(appState.refreshToken). Uten å skanne på
            // nytt her, bygges gitteret om med et UTDATERT missingFrequencyWordIDs-sett.
            if showPrint { print("🟣 onChange refreshToken: \(oldToken) -> \(newToken), planlegger scanForMissingFrequency()") }
            DispatchQueue.main.async {
                if showPrint { print("🟣 onChange refreshToken async — FØR scanForMissingFrequency()") }
                scanForMissingFrequency()
                if showPrint { print("🟣 onChange refreshToken async — ETTER scanForMissingFrequency(), missingFrequencyWordIDs.count=\(missingFrequencyWordIDs.count)") }
            }
        }
        .onDisappear {
            if showPrint { print("🐛 GridView.onDisappear") }
        }
    }
}


// Preview help views ////
private struct ThaiWordsMock: Identifiable {
    let id = UUID()
    let thaiWord: String
    let sentence: String
    let groupId: Int16
}

private struct ThaiGridItemMock: View {
    let word: ThaiWordsMock
    @Binding var moveToPinnedGroup: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(word.thaiWord)
                .font(.title2).bold()
            Text(word.sentence)
                .font(.subheadline)
                .foregroundColor(.gray)
            if moveToPinnedGroup {
                Text("📌 moves to pinned")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.red.opacity(0.2))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct GridViewMockStandalone: View {
    @State private var moveToPinnedGroup = true

    private let mockWords: [ThaiWordsMock] = [
        ThaiWordsMock(thaiWord: "ออกกำลังกาย", sentence: "Trener hver morgen", groupId: 1),
        ThaiWordsMock(thaiWord: "ขอบคุณ", sentence: "Takk!", groupId: 2),
        ThaiWordsMock(thaiWord: "สวัสดี", sentence: "Hei!", groupId: 2)
    ]

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(mockWords) { word in
                    ThaiGridItemMock(word: word, moveToPinnedGroup: $moveToPinnedGroup)
                }
            }
            .padding()
        }
    }
}

private enum PreviewCoreData {
    static let container: NSPersistentContainer = {
        let c = NSPersistentContainer(name: "Model") // bruk ditt faktiske navn
        let d = NSPersistentStoreDescription()
        d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        c.loadPersistentStores { _, _ in
            seed(c.viewContext)   // ← fyll inn litt demo-data for preview
        }
        return c
    }()

    private static func seed(_ ctx: NSManagedObjectContext) {
        let w1 = ThaiWords(context: ctx)
        w1.thaiWord = "สวัสดี"
        w1.sentence = "Hei!"
        w1.groupId  = 1

        let w2 = ThaiWords(context: ctx)
        w2.thaiWord = "ขอบคุณ"
        w2.sentence = "Takk!"
        w2.groupId  = 2

        try? ctx.save()
    }
}

#Preview("GridView (10 words)") {
    GridView(groupId: 1, exerciseMode: true)
        .environment(AppState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("GridView - All details") {
    GridView(groupId: 1, exerciseMode: false)
        .environment(AppState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}


// MARK: - Skeleton Preview (Isolated)
private struct GridViewSkeleton: View {
    @State private var moveToPinnedGroup = true
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.9), Color.indigo.opacity(0.9)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                // Top bar mock
                HStack {
                    Text("←")
                        .font(.headline)
                        .foregroundStyle(.black)

                    HStack(spacing: 12) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 28)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 36, height: 28)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange)
                            .frame(width: 36, height: 28)
                    }

                    Spacer()

                    Image(systemName: "line.horizontal.3")
                        .imageScale(.large)
                        .padding(.horizontal)
                }
                .padding(.horizontal)

                HStack {
                    Text("[ExampleGroup📌Pinned] count: 12")
                        .font(.headline)
                        .foregroundStyle(.black)
                    Spacer()
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(0..<12, id: \.self) { idx in
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 22)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 14)
                                if moveToPinnedGroup {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.25))
                                        .frame(height: 10)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 2)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview("GridView – Skeleton") {
    GridViewSkeleton()
}

// MARK: - GroupWordsListView
// Enkel oversikt over alle ord i én lokal gruppe, i samme stil som PublicWordsListView —
// men uten CloudKit og uten seksjonen for linkede setninger.
struct GroupWordsListView: View {
    let groupId: Int16
    let groupName: String

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var words: FetchedResults<ThaiWords>
    @State private var selectedWord: ThaiWords?
    @State private var pdfURL: URL?
    @State private var showShareSheet = false
    @State private var isGeneratingPDF = false

    init(groupId: Int16, groupName: String) {
        self.groupId = groupId
        self.groupName = groupName
        _words = FetchRequest<ThaiWords>(
            sortDescriptors: [NSSortDescriptor(keyPath: \ThaiWords.frequencyRank, ascending: true)],
            predicate: NSPredicate(format: "groupId == %d", groupId)
        )
    }

    var body: some View {
        List {
            Section("Words (\(words.count))") {
                if words.isEmpty {
                    Text("No words in this group.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(words, id: \.objectID) { word in
                        groupWordRow(for: word)
                    }
                }
            }
        }
        .navigationTitle(groupName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    generateAndSharePDF()
                } label: {
                    if isGeneratingPDF {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isGeneratingPDF)
            }
        }
        .sheet(item: $selectedWord) { word in
            DetailWordView(initialWord: WordInput(from: word), isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #else
                // Manglet på iPad — uten denne falt sheet-en tilbake til SwiftUI sin
                // standard "form sheet"-størrelse (liten, sentrert kort), i stedet for å
                // fylle skjermen slik den gjør på Mac Catalyst. .presentationSizing(.page)
                // ble forsøkt først, men gjorde at arket ikke åpnet seg i det hele tatt —
                // .presentationDetents([.large]) er en eldre, mer velprøvd API.
                .presentationDetents([.large])
                #endif
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL {
                ActivityShareSheet(items: [pdfURL])
            }
        }
    }

    /// Genererer en PDF-rapport (miniatyrbilde + thai + engelsk per ord) og åpner del-arket —
    /// slik at noen som skal finne gode bilder faktisk kan SE hva som er der i dag, ikke bare lese tekst.
    private func generateAndSharePDF() {
        isGeneratingPDF = true
        let snapshot = words.map { (thai: $0.thaiWord ?? "?", english: $0.englishWord ?? "", rank: $0.frequencyRank, imageData: $0.image) }
        let title = groupName
        DispatchQueue.global(qos: .userInitiated).async {
            let url = GroupWordsPDFBuilder.build(title: title, rows: snapshot)
            DispatchQueue.main.async {
                isGeneratingPDF = false
                pdfURL = url
                showShareSheet = (url != nil)
            }
        }
    }

    @ViewBuilder
    private func groupWordRow(for word: ThaiWords) -> some View {
        HStack(spacing: 10) {
            groupWordThumbnail(for: word)

            VStack(alignment: .leading) {
                Text(word.thaiWord ?? "?")
                    .font(.headline)
                Text(word.englishWord ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if word.frequencyRank > 0 {
                    Text("#\(word.frequencyRank)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(word.wordType == 1 ? "Sentence" : "Word")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(word.wordType == 1 ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Button {
                selectedWord = word
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func groupWordThumbnail(for word: ThaiWords) -> some View {
        if let data = word.image, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview("GroupWordsListView") {
    NavigationStack {
        GroupWordsListView(groupId: 1, groupName: "Preview")
            .environment(AppState())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

/// Wrapper rundt UIActivityViewController — brukes til å dele PDF-rapporten fra GroupWordsListView.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Tegner en enkel PDF-rapport (miniatyrbilde + thai + engelsk per ord) for GroupWordsListView,
/// slik at noen som skal finne gode bilder faktisk kan SE hva som ligger inne i dag.
/// Kjøres på bakgrunnstråd fra en ren snapshot av dataene (ingen NSManagedObject-tilgang her).
enum GroupWordsPDFBuilder {
    static func build(title: String, rows: [(thai: String, english: String, rank: Int32, imageData: Data?)]) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let rowHeight: CGFloat = 64
        let thumbSize: CGFloat = 48

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let safeName = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).pdf")

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var y = drawHeader(title: title, count: rows.count, margin: margin, y: margin)

                for row in rows {
                    if y + rowHeight > pageHeight - margin {
                        context.beginPage()
                        y = margin
                    }
                    y = drawRow(row, pageWidth: pageWidth, margin: margin, thumbSize: thumbSize, rowHeight: rowHeight, y: y, cgContext: context.cgContext)
                }
            }
            return url
        } catch {
            print("📄 GroupWordsPDFBuilder: FEIL — \(error)")
            return nil
        }
    }

    private static func drawHeader(title: String, count: Int, margin: CGFloat, y: CGFloat) -> CGFloat {
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
        let subAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.gray]
        (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        ("\(count) words" as NSString).draw(at: CGPoint(x: margin, y: y + 26), withAttributes: subAttrs)
        return y + 50
    }

    private static func drawRow(
        _ row: (thai: String, english: String, rank: Int32, imageData: Data?),
        pageWidth: CGFloat, margin: CGFloat, thumbSize: CGFloat, rowHeight: CGFloat, y: CGFloat,
        cgContext: CGContext
    ) -> CGFloat {
        let thumbRect = CGRect(x: margin, y: y, width: thumbSize, height: thumbSize)
        cgContext.saveGState()
        if let data = row.imageData, let image = UIImage(data: data) {
            UIBezierPath(roundedRect: thumbRect, cornerRadius: 6).addClip()
            image.draw(in: thumbRect)
        } else {
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: thumbRect, cornerRadius: 6).fill()
        }
        cgContext.restoreGState()

        let textX = margin + thumbSize + 14
        let thaiAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 16)]
        let engAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.darkGray]

        (row.thai as NSString).draw(at: CGPoint(x: textX, y: y), withAttributes: thaiAttrs)
        (row.english as NSString).draw(at: CGPoint(x: textX, y: y + 22), withAttributes: engAttrs)

        if row.rank > 0 {
            let rankAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.gray]
            let rankText = "#\(row.rank)"
            let size = (rankText as NSString).size(withAttributes: rankAttrs)
            (rankText as NSString).draw(at: CGPoint(x: pageWidth - margin - size.width, y: y), withAttributes: rankAttrs)
        }

        UIColor.systemGray4.setStroke()
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: margin, y: y + rowHeight - 8))
        separator.addLine(to: CGPoint(x: pageWidth - margin, y: y + rowHeight - 8))
        separator.lineWidth = 0.5
        separator.stroke()

        return y + rowHeight
    }
}
