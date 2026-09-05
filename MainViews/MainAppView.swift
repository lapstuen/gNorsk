import SwiftUI
import CoreData

// typealias CDGroup = Group

struct MainAppView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSelectGroup = false
    @State private var showVocabularyView = false
    @State private var showGoogleView = false
    @State private var showWordView = false
    @State private var showGridView = false
    // Egen state for grid åpnet FRA gruppevelgeren: GridView nøstes oppå SelectGroup
    // (i stedet for å lukke den), slik at Escape/tilbake i Griden går til velgeren
    // først, og til hovedmenyen først ved en ny lukking derfra.
    @State private var showGridViewFromPicker = false
    @State private var visBackupSheet = false
    @State private var visExportToPublicSheet = false
    @State private var visImportFromPublicSheet = false
    @State private var showWordTypeFixConfirm = false
    @State private var wordTypeFixPreviewCount = 0
    @State private var visSelectGroup = false
    @State private var visSokeGrid = false
    @State private var show100WordsGrid = false
    @State private var showCreateNewWord = false
    @State private var visPhoneticView = false
    
    @State private var visDebug = false
    @State private var visSyllableTest = false
    @State private var valgtOrd: ThaiWords?
    @State private var showAbout = false
    @State private var showMainMenu = false
    @State private var showReviewDue = false
    @State private var showRecentlyEdited = false
    @State private var showActiveLearning = false
    @State private var showExerciseLauncher = false
    @State private var showTranslation = false
    @State private var showVoiceDictation = false
    @State private var currentGroupImage: UIImage? = nil
    @State private var gridFilteredIDs: [NSManagedObjectID] = []
    @State private var editCurrentGroup: Group? = nil
    @State private var redigeringsmodus = true

    @State private var show4000WordsGrid = false

    @State private var hasLoaded = false
    @State private var admin = AdminManager.shared
    @State private var words: [ThaiWords] = []
    @State private var selectedGroup = ""
    @State private var sokTekst = ""
    @State private var a = "a"
    @State private var b = "b"
    @State private var c = 0
    @State private var d = 0
    @State private var filtrerteOrd: [String] = []
    
    @State private var ThaiWordJson: [String] = []
    @State private var thaiWordIDs: [NSManagedObjectID] = []
    
    @State private var sampleThaiWords: [ThaiWordJSON] = []
    
    private func loadCurrentGroupImage(groupId: Int16) {
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        currentGroupImage = (try? context.fetch(req))?.first?.groupUIImage
    }

    private func fetchCurrentGroup() -> Group? {
        guard appState.valgtGruppeId > 0 else { return nil }
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", appState.valgtGruppeId)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    private func rebuildThaiWordIDs() {
        thaiWordIDs = objectIDs(forThaiWords: ThaiWordJson, in: context)
    }
    
    private func objectIDs(forThaiWords words: [String], in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        guard !words.isEmpty else { return [] }
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "thaiWord IN %@", words)
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        do {
            return try context.fetch(req)
        } catch {
            print("🛑 map ThaiWordJson → objectIDs feilet: \(error.localizedDescription)")
            return []
        }
    }
    
    
    var body: some View {
        GeometryReader { geo in
        ZStack {
            
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.cyan.opacity(0.7), Color.indigo.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea()
            
            VStack {
                Spacer(minLength: 8)
                
                HStack{
                    
                }

                VStack(spacing: 10) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        Spacer()

                        // Hamburger menu button
                        Menu {
                            Button(action: { showAbout = true }) {
                                Label("About gNorsk", systemImage: "info.circle")
                            }

                            Divider()

                            /* Midlertidig skjult — kommentert ut, ikke slettet (kan settes tilbake senere)
                            Button(action: { showSelectGroup = true }) {
                                Label("Groups", systemImage: "person.3")
                            }

                            Button(action: {
                                appState.visAlleDetaljer = true
                                showGridView = true
                            }) {
                                Label("Grid", systemImage: "rectangle.grid.3x3")
                            }
                            */

                            Button(action: {
                                appState.visAlleDetaljer = false
                                showGridView = true
                            }) {
                                Label("Exercise", systemImage: "checkmark.circle.badge.questionmark.fill")
                            }

                            Button(action: { showReviewDue = true }) {
                                Label("Review Due", systemImage: "clock.arrow.circlepath")
                            }

                            /* Midlertidig skjult — kommentert ut, ikke slettet (kan settes tilbake senere)
                            Button(action: { showRecentlyEdited = true }) {
                                Label("Recently edited", systemImage: "doc.text.fill")
                            }
                            */

                            Button(action: { showActiveLearning = true }) {
                                Label("Learning List", systemImage: "brain.head.profile")
                            }

                          // Spacer()

                            // Add new word / Translation / Tale-diktering har allerede egne
                            // hurtigknapper på hovedskjermen — duplisert her.
                            Button(action: { showCreateNewWord = true }) {
                                Label("Add new word", systemImage: "plus.circle")
                            }

                            Button(action: { showTranslation = true }) {
                                Label("Translation", systemImage: "globe")
                            }

                            Button(action: { showVoiceDictation = true }) {
                                Label("Tale-diktering", systemImage: "mic.badge.plus")
                            }

                            Button(action: {
                                if let url = URL(string: "galpha://") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Label("Letters", systemImage: "textformat.abc")
                            }

                            Button(action: { visPhoneticView = true }) {
                                Label("Fonetic", systemImage: "waveform")
                            }

                           Divider()

                            Button(action: { visSokeGrid = true }) {
                                Label("Search", systemImage: "magnifyingglass.circle.fill")
                            }

                            if admin.isAdmin {
                                Divider()

                                Menu {
                                    Button(action: { visBackupSheet = true }) {
                                        Label("Scrips div!", systemImage: "hand.raised.app")
                                    }

                                    Button(action: { visExportToPublicSheet = true }) {
                                        Label("Export to Public", systemImage: "icloud.and.arrow.up")
                                    }

                                    Button(action: { visImportFromPublicSheet = true }) {
                                        Label("Import from Public", systemImage: "icloud.and.arrow.down")
                                    }

                                    Button(action: {
                                        InitializeLearningState.migrateAllWords(context: context)
                                    }) {
                                        Label("Migrate Learning State", systemImage: "arrow.triangle.2.circlepath.circle")
                                    }

                                    Button(action: {
                                        InitializeLearningState.initializeModifiedDate(context: context)
                                    }) {
                                        Label("Initialize Modified Date", systemImage: "calendar.badge.clock")
                                    }

                                    Button(action: {
                                        wordTypeFixPreviewCount = WordTypeFrequencyFix.countMismatched(context: context)
                                        showWordTypeFixConfirm = true
                                    }) {
                                        Label("Fix words marked as sentence (frequency 1–4000)", systemImage: "wrench.and.screwdriver")
                                    }

                                    Button(action: { visDebug = true }) {
                                        Label("Testing", systemImage: "ladybug")
                                    }
                                } label: {
                                    Label("Admin", systemImage: "lock.shield")
                                }
                            }

                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .padding()
                        }
                    }
                   // .padding(.horizontal)
                    
               
                    
                  //  Text("Hovedmeny")
                  //      .font(.largeTitle).bold()
  

                    Spacer(minLength: 4)

                  //  Text("Pinned group: \(g.getGroupname(groupId: appState.pinnedGruppeId))")

                    // Text("Antall gloser: \(words.count)   Repetisjonsfaktor: 3")
                        .font(.caption)

                    HStack(spacing: 12) {

                        SFButtonColor(name: "plus.circle", title: "add new word", color: .blue) {
                            showCreateNewWord = true
                        }

                     //   SFButton(name: "brain.head.profile", title: "Øv nå", color: .orange) {
                     //       showDirectExercise = true
                     //   }

                    }
                    
                    HStack(spacing: 12) {
                        
                        
                       
                        
                        
                        
                        SFButton(name: "magnifyingglass.circle.fill", title: "Search", color: .blue) {
                            visSokeGrid = true
                        }
                        
                        SFButton(name: "brain.head.profile", title: "Practice all", color: .red) {
                            showExerciseLauncher = true
                        }

                        SFButton(name: "doc.badge.clock", title: "Recently edited", color: .blue) {
                            showRecentlyEdited = true
                        }


                       
                    }

                    HStack(spacing: 12) {

                   
                        SFButton(name: "translate", title: "Translation", color: .blue) {
                            showTranslation = true
                        }
                     //   SFButtonColor(name: "plus.circle", title: "add new word", color: .blue) {
                     //       showCreateNewWord = true
                     //   }
 
                  
                    
             //       SFButton(name: "ellipsis.circle.fill", title: "Backup", color: .orange) {
             //           visBackupSheet = true
             //       }
                //       SFButtonColor(name: "wifi.router", title: "Test orddeling", color: .green) //{
                //           visSyllableTest = true
                //        }


                     //   SFButtonColor(name: "wifi.router", title: "500 words", color: .red) {
                          // SyllableTestView()
                   //     }


                   //     SFButtonColor(name: "wifi.router", title: "4000 words x", color: .blue) {
                            //  load4000Words()
                   //     }
                    }


                    Spacer()


                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

                Spacer()
            }.wireNotifications()
            
            // onAppear for lasting av data
            .onAppear {
                Notifier.shared.hide()
                Logger.info("onAppear , MainAppView")

                // Initialize learning state for all words (run once)
                let hasRunMigration = UserDefaults.standard.bool(forKey: "hasRunLearningStateMigration")
                if !hasRunMigration {
                    InitializeLearningState.migrateAllWords(context: context)
                    UserDefaults.standard.set(true, forKey: "hasRunLearningStateMigration")
                    print("✅ Kjørte learningState migrering for første gang")
                }

                // Bare initialiser gruppe og ord ved første lasting — ikke ved retur fra sheet/navigasjon
                guard !hasLoaded else { return }
                hasLoaded = true

                // Følgegrupper (Word/Ok) skal aldri gjenopprettes som aktiv hovedgruppe ved
                // oppstart — normaliser og lagre korrigert verdi tilbake, slik at eldre,
                // lagret tilstand fra før denne regelen fantes retter seg selv (self-healing).
                var groupId = g.getCurrentGroupID()
                let resolvedGroupId = Group.resolvedBaseGroupId(for: groupId)
                if resolvedGroupId != groupId {
                    groupId = resolvedGroupId
                    g.deleteCurrentGroupCoreData()
                    g.insertCurrentGroupIntoCoreData(groupId: groupId, number: 0)
                }
                appState.sqlGruppeId = Int16(groupId)

                let groupName = g.getCurrentGroupName(groupId: groupId)
                appState.valgtGruppeNavn = groupName
                appState.valgtGruppeId = groupId
                loadCurrentGroupImage(groupId: Int16(groupId))

                // Hent ord fra Core Data
                let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                req.predicate = NSPredicate(format: "groupId == %d", groupId)
                req.sortDescriptors = [
                    NSSortDescriptor(key: "insertDate", ascending: false),
                    NSSortDescriptor(key: "dateTwo", ascending: true)
                ]
                req.fetchLimit = 2000

                do {
                    words = try context.fetch(req)
                } catch {
                    print("❌ fetch words error:", error.localizedDescription)
                    words = []
                }

            }
            .sheet(isPresented: $showCreateNewWord) {
                CreateWordView().environment(appState)
                    .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                    .frame(minHeight: 900, idealHeight: 900, maxHeight: .infinity)
                #elseif os(iOS)
                    // iPad-specific presentation (non-Catalyst)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif

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
                #if targetEnvironment(macCatalyst)
                
               
                .frame(minWidth: 1600, minHeight: 1000)
                #endif
            }

            .sheet(isPresented: $showAbout) {
                AboutView()
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 600, minHeight: 500)
                #elseif os(iOS)
                    // iPad-specific presentation (non-Catalyst)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }

            .sheet(item: $valgtOrd) { word in
                let input = WordInput(from: word)
                DetailWordView(initialWord: input, isNested: false)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                    .catalystSheetFrame(width: 1000, height: 800)
                #endif
            }
                
                
            // ── Flytende mic-knapp (bottom-right) ──────────────────
            VStack {
                Spacer()
                HStack {
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
                    .padding(.bottom, 28)
                }
            }
            .allowsHitTesting(true)
            }//.frame(minWidth: 300, idealWidth: 300, maxWidth: .infinity)
        
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
        
    
    
        
        
        
        
            //  .frame(minHeight: 900, idealHeight: 900, maxHeight: .infinity)
            
            
            // fullScreenCover og sheet
            .fullScreenCover(isPresented: $visSokeGrid) {
                SearchView()
                    .background(Color.white.ignoresSafeArea())
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
            }
            .onChange(of: appState.pendingSearchText) { oldValue, newValue in
                if newValue != nil {
                    visSokeGrid = true
                }
            }
            .onChange(of: appState.pendingOpenGrid) { _, newValue in
                if newValue {
                    gridFilteredIDs = appState.pendingGridWordIDs
                    appState.pendingGridWordIDs = []
                    appState.pendingOpenGrid = false
                    showGridView = true
                }
            }
        
            .fullScreenCover(isPresented: $visSyllableTest) {
                //SyllableTableView(text: "ขอบคุณ")
                SyllableTableView(text: "ขอบคุณ")
                    .background(Color.white.ignoresSafeArea())
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
            }
            
            .fullScreenCover(isPresented: $show100WordsGrid) {
                //GridView(filterThaiWords: basisThaiWords)
                
                
            }
            
            
            .fullScreenCover(isPresented: $visPhoneticView) {
                @State var model = ThaiIPAViewModel()
                VStack(spacing: 16) {
                    Text("Thai → IPA (v1)")
                        .font(.title2).bold()
                    
                    TextField("ไทย", text: $model.thaiInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .onSubmit { model.run() }
                    
                    Button("Convert") { model.run() }
                        .buttonStyle(.borderedProminent)
                    
                    Text(model.ipa)
                        .font(.title)
                        .monospaced()
                        .padding(.top, 8)
                    
                    Text("Tip: v1 supports common vowels and basic tones. Send me words that come out wrong, so we can improve the model.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                }
            }
                
               // .fullScreenCover(isPresented: $show4000WordsGrid) {
          //  .fullScreenCover(isPresented: $show4000WordsGrid) {
          //      let ids = objectIDs(forThaiWords: ThaiWordJson, in: context)
//
          //      VStack {
          //          Text("Antall ordxx: \(ThaiWordJson.count)")
          //          Text("Antall treff i Core Data: \(ids.count)")
          //
          //      }
          //  }
                
                .fullScreenCover(isPresented: $showGridView, onDismiss: {
                    gridFilteredIDs = []
                    appState.sqlGruppeId = appState.valgtGruppeId
                }) {
                    if gridFilteredIDs.isEmpty {
                        GridView(groupId: Int16(appState.sqlGruppeId), exerciseMode: !appState.visAlleDetaljer)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                    } else {
                        GridView(filtrerteId: gridFilteredIDs, exerciseMode: false)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                    }
                }

                .fullScreenCover(isPresented: $showReviewDue) {
                    ReviewDueView()
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                }

                .sheet(isPresented: $showExerciseLauncher) {
                    ExerciseLauncherView()
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                }

                .fullScreenCover(isPresented: $showRecentlyEdited) {
                    RecentlyEditedView()
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                }

                .fullScreenCover(isPresented: $showActiveLearning) {
                    ActiveLearningView()
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                }

                .sheet(isPresented: $showVocabularyView) {
                    
                  //  ExercisView(isPresented: $showVocabularyView,
                  //              words: aktiveOrd)      // <- send inn arrayet du vil trene på
                  //      .environment(appState)
                  //      .environment(\.managedObjectContext, context)
                }
                
                
           //     .sheet(isPresented: .constant(showGoogleView)) {
           //         GoogleTranslateView()
           //             .environment(appState)
           //             .onDisappear { showGoogleView = false }
           //     }
                
                .sheet(isPresented: .constant(showGoogleView)) {
                    // DetailWrapper(antallGloser: 20, repetisjonsFaktor: 3)
                    //     .environment(appState)
                    //     .frame(width: 800, height: 900)
                    //      .environment(\.managedObjectContext, context)
                    //    .onDisappear { showGoogleView = false }
                }
                
                    .sheet(isPresented: $visBackupSheet) {
                        Backup()
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                            #if targetEnvironment(macCatalyst)
                            .presentationSizing(.fitted) // lar vinduet tilpasse seg innholdet
                            .frame(minWidth: 500, idealWidth: 600, maxWidth: 1000,
                                   minHeight: 600, idealHeight: 800, maxHeight: 1200)
                        #elseif os(iOS)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                        #endif
                    }

                    .sheet(isPresented: $visExportToPublicSheet) {
                        ExportToPublicView()
                            .environment(\.managedObjectContext, context)
                            #if targetEnvironment(macCatalyst)
                            .frame(minWidth: 800, minHeight: 1000)
                        #elseif os(iOS)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                        #endif
                    }

                    .sheet(isPresented: $visImportFromPublicSheet) {
                        ImportFromPublicView()
                            .environment(\.managedObjectContext, context)
                            #if targetEnvironment(macCatalyst)
                            .frame(minWidth: 800, minHeight: 1000)
                        #elseif os(iOS)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                        #endif
                    }

                    .confirmationDialog(
                        wordTypeFixPreviewCount > 0
                            ? "\(wordTypeFixPreviewCount) words have frequency 1–4000 but are marked as Sentence. Change these to Word?"
                            : "No mismarked words found (frequency 1–4000 marked as Sentence).",
                        isPresented: $showWordTypeFixConfirm,
                        titleVisibility: .visible
                    ) {
                        if wordTypeFixPreviewCount > 0 {
                            Button("Fix \(wordTypeFixPreviewCount) words") {
                                let fixed = WordTypeFrequencyFix.fixWordsMismarkedAsSentence(context: context)
                                Notifier.shared.show(.success, "Fixed \(fixed) words from Sentence to Word")
                            }
                            Button("Cancel", role: .cancel) {}
                        } else {
                            Button("OK", role: .cancel) {}
                        }
                    }

                .sheet(item: $editCurrentGroup, onDismiss: {
                    let gid = appState.valgtGruppeId
                    let req = NSFetchRequest<Group>(entityName: "Group")
                    req.predicate = NSPredicate(format: "groupId == %d", gid)
                    req.fetchLimit = 1
                    if let group = try? context.fetch(req).first {
                        appState.valgtGruppeNavn = group.groupName ?? ""
                        currentGroupImage = group.groupUIImage
                    }
                }) { group in
                    EditGroupView(
                        gruppe: group,
                        visRedigeringsSkjema: Binding(
                            get: { editCurrentGroup != nil },
                            set: { if !$0 { editCurrentGroup = nil } }
                        ),
                        redigeringsmodus: $redigeringsmodus,
                        buttonColor: .blue
                    )
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 400, minHeight: 600)
                    #endif
                }
                .fullScreenCover(isPresented: $showSelectGroup) {
                    SelectGroup(appState: appState) { group in
                        appState.valgtGruppeId   = group.groupId
                        appState.sqlGruppeId     = group.groupId
                        let navn = group.groupName ?? "?"
                        appState.valgtGruppeNavn = navn
                        selectedGroup = navn
                        currentGroupImage = group.groupUIImage

                        // Core Data fetch
                        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                        req.predicate = NSPredicate(format: "groupId == %d", group.groupId)
                        req.sortDescriptors = [
                            NSSortDescriptor(key: "insertDate", ascending: false),
                            NSSortDescriptor(key: "dateTwo",    ascending: true)
                        ]
                        req.fetchLimit = 2000
                        words = (try? context.fetch(req)) ?? []

                        appState.visAlleDetaljer = true
                        showGridViewFromPicker = true
                    }
                    .fullScreenCover(isPresented: $showGridViewFromPicker, onDismiss: {
                        appState.sqlGruppeId = appState.valgtGruppeId
                    }) {
                        GridView(groupId: Int16(appState.sqlGruppeId), exerciseMode: !appState.visAlleDetaljer)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                    }
                }


            }
         }
    }

#Preview("MainAppView") {
    // Use preview Core Data stack
    let previewController = PersistenceController.preview
    let context = previewController.container.viewContext

    // Optionally seed a minimal group and word so the UI has something to show
    do {
        // Seed one group if none exists
        let groupFetch = NSFetchRequest<Group>(entityName: "Group")
        groupFetch.fetchLimit = 1
        let hasGroup = (try? context.count(for: groupFetch)) ?? 0 > 0
        if !hasGroup {
            let grp = Group(context: context)
            grp.groupId = 1
            grp.groupName = "Demo"
            grp.groupType = 1
        }
        // Seed one ThaiWords if none exists
        let wordFetch = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        wordFetch.fetchLimit = 1
        let hasWord = (try? context.count(for: wordFetch)) ?? 0 > 0
        if !hasWord {
            let w = ThaiWords(context: context)
            w.id = UUID()
            w.thaiWord = "สวัสดี"
            w.englishWord = "hello"
            w.groupId = 1
            w.insertDate = Date()
        }
        try? context.save()
    }

    // App state with demo values
    let state = AppState()
    state.valgtGruppeNavn = "Demo"
    state.valgtGruppeId = 1
    state.sqlGruppeId = 1
    state.pinnedGruppeId = 1

    return NavigationStack {
        MainAppView()
            .environment(state)
            .environment(\.managedObjectContext, context)
    }
#if targetEnvironment(macCatalyst)
    .frame(minWidth: 600, minHeight: 400)
#endif
}

