//
//  ExerciseView.swift
//  gThai
//
//  Dedicated exercise view for focused learning sessions
//

import SwiftUI
import CoreData
import AVFoundation

struct ExerciseView: View {
    let groupId: Int16?
    let objectIDs: [NSManagedObjectID]?
    let exerciseType: ExerciseType
    let recall: RecallDirection

    enum ExerciseType {
        case newWords        // Only new words
        case review          // Only due reviews
        case mixed           // New + due reviews
        case learning        // Only words in learning state
        case allInGroup      // All words in group (no date/state filtering)
        case chunked(limit: Int)  // Limited number of oldest words by modifiedDate
        case favorites       // Only starred words (star = true)
    }

    enum RecallDirection {
        case passive   // Thai -> English
        case active    // English -> Thai
    }

    @FetchRequest private var words: FetchedResults<ThaiWords>

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var sessionWordIDs: [NSManagedObjectID] = []
    @State private var currentSessionIndex = 0
    @State private var sessionStats = SessionStats()
    @State private var showingSessionComplete = false
    @State private var showingDetailWordView = false
    @State private var isRevealed = false  // Track if Thai word is shown
    @State private var isMeaningRevealed = false  // Reveal English meaning separately in passive mode
    // Vises FØR selve kortet for hvert nye ord — spiller av lyden automatisk, slik at man kan
    // prøve å gjenkjenne ordet kun ved å høre det før man ser det. Nullstilles til true samme
    // steder som isRevealed nullstilles til false (nytt ord vist).
    @State private var showListenFirstOverlay = true
    // Styrer avspillingsfarten i listenFirstOverlay — 0.9 er samme standardverdi som resten av
    // appen brukte hardkodet fra før.
    @State private var listenFirstPlaybackRate: Double = 0.9
    // Setninger/ord som har dette ordet tagget (samme oppslag som hasExampleSentences i
    // GridItem.swift) — lar brukeren også høre en relatert setning fra listenFirstOverlay, ikke
    // bare selve ordet. relatedSentenceIndex sykler gjennom listen for hvert trykk.
    @State private var relatedSentences: [ThaiWords] = []
    @State private var relatedSentenceIndex = 0
    // Settes til den setningen som faktisk BLE spilt av sist (før relatedSentenceIndex hopper
    // videre til neste) — slik at "EN"-knappen for setningen alltid leser engelsk for akkurat
    // den setningen som nettopp ble hørt, ikke den neste i køen.
    @State private var lastPlayedSentence: ThaiWords?
    // Viser thai-teksten i et lite "felt" i listenFirstOverlay når "Thai"-knappen trykkes, og lar
    // brukeren svare OK/not OK direkte derfra — uten å måtte trykke Continue og se selve kortet.
    @State private var revealedThaiText = ""
    // Samme mønster/innstillinger som brukes for engelsk/norsk-avspilling i GridItem.swift.
    // Norsk er hardkodet her (ikke morsmaalLanguage-innstillingen) siden translation1-feltet
    // alltid ER norsk (se "Translation1 (Norwegian)" i DetailWordView), uansett hva
    // morsmaalLanguage måtte være satt til andre steder i appen.
    @State private var speechSynth = AVSpeechSynthesizer()
    @AppStorage("speechRateEnglish") private var speechRateEnglish: Double = 0.5
    @AppStorage("speechRateMorsmaal") private var speechRateMorsmaal: Double = 0.5
    
    @State private var recallMode: RecallDirection = .passive

    // Chunked exercise state
    @State private var availableWords: [ThaiWords] = []      // Session word pool
    @State private var completedWords: Set<UUID> = []        // Removed after good/easy
    @State private var shownInRound: Set<UUID> = []         // Shown in current round
    @State private var currentRound: Int = 1

    init(groupId: Int16? = nil, objectIDs: [NSManagedObjectID]? = nil, exerciseType: ExerciseType = .mixed, recall: RecallDirection = .passive) {
        self.groupId = groupId
        self.objectIDs = objectIDs
        self.exerciseType = exerciseType
        self.recall = recall

        // Initialize mutable recall mode from initial parameter
        _recallMode = State(initialValue: recall)

        let now = Date()
        var predicates: [NSPredicate] = []

        // Ordliste (vilkårlig ID-sett) går foran gruppe-filteret, akkurat som i GridView.
        if let ids = objectIDs, !ids.isEmpty {
            predicates.append(NSPredicate(format: "self IN %@", ids))
        } else if let gid = groupId {
            predicates.append(NSPredicate(format: "groupId == %d", gid))
        }

        // Exercise type filter
        switch exerciseType {
        case .newWords:
            predicates.append(NSPredicate(format: "learningState == %d", LearningState.new.rawValue))

        case .review:
            predicates.append(NSPredicate(format: "learningState != %d AND dueAt <= %@",
                                        LearningState.new.rawValue, now as NSDate))

        case .learning:
            predicates.append(NSPredicate(format: "learningState == %d OR learningState == %d",
                                        LearningState.learning.rawValue,
                                        LearningState.relearning.rawValue))

        case .mixed:
            // New words OR due words
            let newPredicate = NSPredicate(format: "learningState == %d", LearningState.new.rawValue)
            let duePredicate = NSPredicate(format: "dueAt == nil OR dueAt <= %@", now as NSDate)
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [newPredicate, duePredicate]))

        case .allInGroup:
            // No additional filtering - just use groupId filter
            break

        case .chunked:
            // No additional filtering - fetch all, limit in onAppear
            break

        case .favorites:
            // Only starred words with active learning state
            predicates.append(NSPredicate(format: "star == true AND learningState != %d", LearningState.new.rawValue))
        }

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        // Different sort descriptors based on exercise type
        let sortDescriptors: [NSSortDescriptor]
        if case .chunked = exerciseType {
            sortDescriptors = [
                NSSortDescriptor(key: #keyPath(ThaiWords.modifiedDate), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.thaiWord), ascending: true)
            ]
        } else {
            sortDescriptors = [
                NSSortDescriptor(key: #keyPath(ThaiWords.learningState), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.dueAt), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.repetitions), ascending: true)
            ]
        }

        _words = FetchRequest(
            entity: ThaiWords.entity(),
            sortDescriptors: sortDescriptors,
            predicate: finalPredicate
        )
    }

    private var currentWord: ThaiWords? {
        if case .chunked = exerciseType {
            // Get next unshown word from available pool
            let remaining = availableWords.filter { word in
                !completedWords.contains(word.id ?? UUID()) &&
                !shownInRound.contains(word.id ?? UUID())
            }
            return remaining.first
        } else {
            guard currentSessionIndex < sessionWordIDs.count else { return nil }
            let objectID = sessionWordIDs[currentSessionIndex]
            return try? context.existingObject(with: objectID) as? ThaiWords
        }
    }

    private var progress: Double {
        guard !sessionWordIDs.isEmpty else { return 0 }
        return Double(currentSessionIndex) / Double(sessionWordIDs.count)
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                // Header
                headerView

                if let word = currentWord {
                    // Main card
                    exerciseCard(for: word)
                        .overlay {
                            if showListenFirstOverlay {
                                listenFirstOverlay(for: word)
                            }
                        }
                } else {
                    // No more words
                    noMoreWordsView
                }

               // Spacer()

                // Session stats
                sessionStatsView
            }
            //.padding()
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingSessionComplete) {
            let remaining = availableWords.filter { !completedWords.contains($0.id ?? UUID()) }
            SessionCompleteView(
                stats: sessionStats,
                remainingCount: remaining.count,
                onContinue: remaining.isEmpty ? nil : {
                    showingSessionComplete = false
                    shownInRound.removeAll()
                    currentRound += 1
                },
                onDismiss: {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingDetailWordView, onDismiss: {
            // Refresh the current word from Core Data after editing
            if let word = currentWord {
                context.refresh(word, mergeChanges: true)
            }
        }) {
            if let word = currentWord {
                DetailWordView(initialWord: WordInput(from: word), isNested: false)
                    .environment(\.managedObjectContext, context)
                    .environment(appState)
            }
        }
        .onAppear {
            isRevealed = false  // Start with word hidden
            isMeaningRevealed = false
            showListenFirstOverlay = true
            revealedThaiText = ""

            if sessionWordIDs.isEmpty {
                sessionWordIDs = words.map(\.objectID)
                currentSessionIndex = 0
            }

            if case .chunked(let limit) = exerciseType {
                // Initialize chunked exercise session
                availableWords = Array(words.prefix(limit))
                completedWords.removeAll()
                shownInRound.removeAll()
                currentRound = 1
            }
        }
    }

    // MARK: - View Components
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Button("←") {
                dismiss()
            }
            .foregroundColor(.white)

            Spacer()

            VStack {
                if case .chunked = exerciseType {
                    Text(chunkedProgress)
                        .font(.footnote)
                        .foregroundColor(.white)
                } else {
                    Text("\(currentSessionIndex + 1) / \(sessionWordIDs.count)")
                        .font(.headline)
                        .foregroundColor(.white)

              //      ProgressView(value: progress)
             //           .progressViewStyle(LinearProgressViewStyle(tint: .white))
           //             .frame(width: 150)
                }
            }
            
            Picker("Recall", selection: $recallMode) {
                Text("Passive").tag(RecallDirection.passive)
                Text("Active").tag(RecallDirection.active)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: recallMode) { _, _ in
                // Reset reveal state when switching mode
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRevealed = false
                    isMeaningRevealed = false
                }
            }

           

         //   Text(exerciseType.displayName)
           //     .font(.caption)
             //   .foregroundColor(.white.opacity(0.8))
        }
    }
    
   

    // Vises oppå exerciseCard for et helt nytt ord — lar brukeren prøve å gjenkjenne ordet kun ved
    // å høre det, før bilde/thai-tekst er synlig i det hele tatt. Spiller av automatisk med én
    // gang, med en knapp for å høre på nytt og en knapp for å gå videre til selve kortet.
    @ViewBuilder
    private func listenFirstOverlay(for word: ThaiWords) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)

            VStack(spacing: 24) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Listen and try to guess the word")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                        Slider(value: $listenFirstPlaybackRate, in: 0.5...1.3)
                        Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    }
                    Text("Speed: \(listenFirstPlaybackRate, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260)

                HStack(spacing: 12) {
                    Button {
                        playAudio(for: word)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Button {
                        speakEnglish(word)
                    } label: {
                        Text("EN")
                            .font(.title3.bold())
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        speakNorwegian(word)
                    } label: {
                        Text("NO")
                            .font(.title3.bold())
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)
                }
        Button {
                    showListenFirstOverlay = false
                } label: {
                    // Ren SF Symbol uten .borderedProminent/.bordered — de stilene legger på en
                    // egen bakgrunnsform (kapsel/avrundet rektangel) som blir litt oval når
                    // innholdet ikke er helt kvadratisk. "pencil.circle.fill" er allerede tegnet
                    // som en perfekt sirkel i seg selv, så .plain gir en ekte rund knapp.
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Divider()

                // Lar brukeren svare direkte fra lytte-overlayet — uten å gå via Continue og
                // kortet bak. gradeWord gjør nøyaktig det samme som OK/not OK-knappene på selve
                // kortet (logger svaret, oppdaterer spaced-repetition-status, går videre).
                VStack(spacing: 10) {
                    Text(revealedThaiText.isEmpty ? " " : revealedThaiText)
                        .font(.system(size: 66, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))

                    HStack(spacing: 12) {
                        Button {
                            revealedThaiText = word.thaiWord ?? ""
                        } label: {
                            Text("Thai")
                                .font(.title3.bold())
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            gradeWord(word, confidence: .hard)
                        } label: {
                            Text("❌ Not OK")
                                .font(.title3.bold())
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button {
                            gradeWord(word, confidence: .good)
                        } label: {
                            Text("👌 OK")
                                .font(.title3.bold())
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
                   

                    if !relatedSentences.isEmpty {
                        VStack(spacing: 8) {
                            Text("\(relatedSentences.count) example sentence(s) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Button {
                                    let sentence = relatedSentences[relatedSentenceIndex]
                                    playAudio(for: sentence)
                                    lastPlayedSentence = sentence
                                    relatedSentenceIndex = (relatedSentenceIndex + 1) % relatedSentences.count
                                } label: {
                                    Label("Play a sentence", systemImage: "text.bubble.fill")
                                        .font(.title3.bold())
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)

                                Button {
                                    if let sentence = lastPlayedSentence {
                                        speakEnglish(sentence)
                                    }
                                } label: {
                                    Text("EN")
                                        .font(.title3.bold())
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .disabled(lastPlayedSentence == nil)

                                Button {
                                    if let sentence = lastPlayedSentence {
                                        speakNorwegian(sentence)
                                    }
                                } label: {
                                    Text("NO")
                                        .font(.title3.bold())
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .disabled(lastPlayedSentence == nil)
                            }
                        }
                    }

            
                }
            }
            .padding(30)

            // Bla fram/tilbake mellom ord KUN for å lytte — svarer ikke på øvelsen, ingen grading.
            // Tydelig plassert i hver sin kant, adskilt fra knappene i midten.
            if canBrowseWords {
                HStack {
                    Button {
                        showPreviousWordInOverlay()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 50))
                    }
                    .disabled(currentSessionIndex <= 0)
                    .opacity(currentSessionIndex <= 0 ? 0.3 : 1)

                    Spacer()

                    Button {
                        showNextWordInOverlay()
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 50))
                    }
                    .disabled(currentSessionIndex >= sessionWordIDs.count - 1)
                    .opacity(currentSessionIndex >= sessionWordIDs.count - 1 ? 0.3 : 1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            playAudio(for: word)
            loadRelatedSentences(for: word)
        }
    }

    @ViewBuilder
    private func exerciseCard(for word: ThaiWords) -> some View {
        VStack(spacing: 20) {

            Spacer()
            // Learning state indicator
            learningStateHeader(for: word)

            // Main content
            VStack(spacing: 8) {
                // Image shown in both modes
                if recallMode == .passive {
                    Image(systemName: "questionmark.app.dashed")
                        .resizable()
                        .frame(width: 200, height: 200)
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white, lineWidth: 4))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                isRevealed = true
                                if recallMode == .passive {
                                    // Only reveal Thai; keep meaning hidden until explicitly requested
                                    isMeaningRevealed = false
                                }
                            }
                            playAudio(for: word)
                        }
                } else {
                    Image(uiImage: word.uiImage)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white, lineWidth: 4))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                isRevealed = true
                                if recallMode == .passive {
                                    // Only reveal Thai; keep meaning hidden until explicitly requested
                                    isMeaningRevealed = false
                                }
                            }
                            playAudio(for: word)
                        }
                }
                
                

                Spacer()

                if recallMode == .passive {
                    let showThai = recallMode == .passive || isRevealed
                    if showThai {
                        Text(word.thaiWord ?? "")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.primary)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Text("?")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.primary.opacity(0.3))
                    }

                    if isRevealed {
                        if isMeaningRevealed {
                            ScrollView {
                                Text(word.englishWord ?? "")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal, 4)
                            }
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isMeaningRevealed = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "eye")
                                    Text("Show meaning")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                } else {
                    // Active: English prompt always, Thai revealed
                    Text(word.englishWord ?? "")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 4)

                    Spacer()

                    if isRevealed {
                        Text(word.thaiWord ?? "")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.primary)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Text("?")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.primary.opacity(0.3))
                    }
                }
            }

            // Detaljer button
            Button {
                showingDetailWordView = true
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Show details")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // Two simple buttons
            HStack(spacing: 20) {
                Button {
                    gradeWord(word, confidence: .hard)
                } label: {
                    VStack {
                        Text("❌")
                            .font(.system(size: 40))
                        Text("not OK")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 0)
                    .background(Color.red.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red, lineWidth: 3)
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    gradeWord(word, confidence: .good)
                } label: {
                    VStack {
                        Text("👌")
                            .font(.system(size: 40))
                        Text("OK")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 0)
                    .background(Color.green.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green, lineWidth: 3)
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func learningStateHeader(for word: ThaiWords) -> some View {
        let state = EnhancedExercise.learningState(for: word)
        HStack {
            Circle()
                .fill(stateColor(for: state))
                .frame(width: 12, height: 12)
            Text(state.displayName)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            if word.dueAt != nil {
                Text("Neste: \(EnhancedExercise.nextReviewInterval(for: word))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var noMoreWordsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Session complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Great job! You've completed all the words.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("View results") {
                showingSessionComplete = true
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding()
    }

   @ViewBuilder
    private var sessionStatsView: some View {
        HStack(spacing: 10) {
            StatView(title: "New", value: "\(sessionStats.newWords)", color: .blue)
            StatView(title: "Learned", value: "\(sessionStats.graduated)", color: .green)
            StatView(title: "Retry", value: "\(sessionStats.relearning)", color: .orange)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    // MARK: - Helper Functions
    private func stateColor(for state: LearningState) -> Color {
        switch state {
        case .new: return .blue
        case .learning: return .orange
        case .reviewing: return .green
        case .relearning: return .red
        }
    }

    private func confidenceColor(for level: ConfidenceLevel) -> Color {
        switch level {
        case .blackout: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    // Bla fram/tilbake i listenFirstOverlay UTEN å svare på øvelsen (ingen gradeWord/
    // advanceToNextWord kjøres) — lar brukeren bare høre gjennom ordene i sesjonen. Bare
    // meningsfullt for den vanlige (ikke-chunked) sesjonstypen, siden chunked-modus sin
    // currentWord er styrt av availableWords-filtrering, ikke currentSessionIndex.
    private var canBrowseWords: Bool {
        if case .chunked = exerciseType { return false }
        return true
    }

    private func showListenOverlayFor(newIndex: Int) {
        guard canBrowseWords, sessionWordIDs.indices.contains(newIndex) else { return }
        currentSessionIndex = newIndex
        isRevealed = false
        isMeaningRevealed = false
        revealedThaiText = ""
        if let word = currentWord {
            playAudio(for: word)
            loadRelatedSentences(for: word)
        }
    }

    private func showPreviousWordInOverlay() {
        showListenOverlayFor(newIndex: currentSessionIndex - 1)
    }

    private func showNextWordInOverlay() {
        showListenOverlayFor(newIndex: currentSessionIndex + 1)
    }

    // Samme oppslag som hasExampleSentences i GridItem.swift — finner andre ThaiWords-rader som
    // har dette ordet tagget i sitt tags-felt (",ordet,").
    private func loadRelatedSentences(for word: ThaiWords) {
        relatedSentenceIndex = 0
        lastPlayedSentence = nil
        guard let thaiWord = word.thaiWord, !thaiWord.isEmpty else {
            relatedSentences = []
            return
        }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "tags CONTAINS %@", thaiWord)
        relatedSentences = (try? context.fetch(request)) ?? []
    }

    private func playAudio(for word: ThaiWords) {
        Task {
            do {
                try await CloudTTSTest.testGoogleTTS(word.thaiWord ?? "", rate: listenFirstPlaybackRate)
            } catch {
                g.talkTh(talkText: word.thaiWord ?? "", rate: Float(listenFirstPlaybackRate), language: "nb-NO")
            }
        }
    }

    private func speak(_ text: String, language: String, voiceId: String, rate: Float) {
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId) ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        utterance.volume = 1.0
        if speechSynth.isSpeaking { speechSynth.stopSpeaking(at: .immediate) }
        speechSynth.speak(utterance)
    }

    // Samme sjekk som "Oversett"-knappen i DetailWordView bruker: hvis feltet er tomt, oversett
    // fra thai og lagre FØR vi leser opp — i stedet for å bare lese opp en tom tekst.
    private func speakEnglish(_ word: ThaiWords) {
        let existing = word.englishWord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else {
            speak(existing, language: "en-US", voiceId: "com.apple.voice.enhanced.en-US.Samantha", rate: Float(speechRateEnglish))
            return
        }
        guard let thaiWord = word.thaiWord, !thaiWord.isEmpty else { return }
        translateText2(soureLanguage: "th", toLanguage: "en", text: thaiWord) { results, _ in
            guard let translated = results.first, !translated.isEmpty else { return }
            word.englishWord = translated
            try? word.managedObjectContext?.save()
            speakEnglish(word)
        }
    }

    private func speakNorwegian(_ word: ThaiWords) {
        let existing = word.translation1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else {
            speak(existing, language: "nb-NO", voiceId: "com.apple.voice.enhanced.nb-NO.Nora", rate: Float(speechRateMorsmaal))
            return
        }
        guard let thaiWord = word.thaiWord, !thaiWord.isEmpty else { return }
        translateText2(soureLanguage: "th", toLanguage: "no", text: thaiWord) { results, _ in
            guard let translated = results.first, !translated.isEmpty else { return }
            word.translation1 = translated
            try? word.managedObjectContext?.save()
            speakNorwegian(word)
        }
    }

    private func gradeWord(_ word: ThaiWords, confidence: ConfidenceLevel) {
        withAnimation(.easeOut(duration: 0.3)) {
            let previousState = EnhancedExercise.learningState(for: word)
            EnhancedExercise.grade(word: word, confidence: confidence)
            let newState = EnhancedExercise.learningState(for: word)

            // Update session stats
            updateSessionStats(previousState: previousState, newState: newState, confidence: confidence)

            do {
                try word.managedObjectContext?.save()
            } catch {
                print("Save error: \(error)")
            }

            // Move to next word
            if case .chunked = exerciseType {
                handleChunkedWordCompletion(word: word, confidence: confidence)
            } else {
                advanceToNextWord()
            }
        }
    }

    private func updateSessionStats(previousState: LearningState, newState: LearningState, confidence: ConfidenceLevel) {
        if previousState == .new {
            sessionStats.newWords += 1
        }

        if previousState == .learning && newState == .reviewing {
            sessionStats.graduated += 1
        }

        if newState == .relearning {
            sessionStats.relearning += 1
        }

        sessionStats.totalReviews += 1
    }

    private func advanceToNextWord() {
        currentSessionIndex += 1
        isRevealed = false  // Reset for next word
        isMeaningRevealed = false
        showListenFirstOverlay = true
        revealedThaiText = ""

        if currentSessionIndex >= sessionWordIDs.count {
            showingSessionComplete = true
        } else if let word = currentWord {
            // showListenFirstOverlay var allerede true (vi forlot aldri overlayet ved å trykke
            // OK/not OK herfra) — .onAppear fyres da IKKE på nytt for det nye ordet, så vi må
            // trigge avspilling manuelt her, akkurat som showNextWordInOverlay allerede gjør.
            playAudio(for: word)
            loadRelatedSentences(for: word)
        }
    }

    // MARK: - Chunked Exercise Helpers

    private func handleChunkedWordCompletion(word: ThaiWords, confidence: ConfidenceLevel) {
        guard let wordId = word.id else { return }

        shownInRound.insert(wordId)

        if confidence == .good || confidence == .easy {
            completedWords.insert(wordId)
        }

        advanceChunkedExercise()
    }

    private func advanceChunkedExercise() {
        let remaining = availableWords.filter { !completedWords.contains($0.id ?? UUID()) }
        let unshownInRound = remaining.filter { !shownInRound.contains($0.id ?? UUID()) }

        if unshownInRound.isEmpty {
            if remaining.isEmpty {
                showingSessionComplete = true
            } else {
                shownInRound.removeAll()
                currentRound += 1
            }
        }

        isRevealed = false  // Reset for next word
        isMeaningRevealed = false
        showListenFirstOverlay = true
        revealedThaiText = ""
        if !showingSessionComplete, let word = currentWord {
            // Se forklaring i advanceToNextWord.
            playAudio(for: word)
            loadRelatedSentences(for: word)
        }
    }

    private var chunkedProgress: String {
        guard case .chunked(let limit) = exerciseType else { return "" }
        let mastered = completedWords.count
        let shown = shownInRound.count
        return "\(mastered)/\(limit) mestret, \(shown)/\(limit) vist (Runde \(currentRound))"
    }
}

// MARK: - Supporting Types
struct SessionStats {
    var newWords = 0
    var graduated = 0
    var relearning = 0
    var totalReviews = 0
}

struct SessionCompleteView: View {
    let stats: SessionStats
    let remainingCount: Int
    let onContinue: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 80))
                .foregroundColor(.gold)

            Text("Session complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 15) {
                HStack {
                    Text("Total reviewed:")
                    Spacer()
                    Text("\(stats.totalReviews)")
                        .fontWeight(.bold)
                }

                HStack {
                    Text("New words:")
                    Spacer()
                    Text("\(stats.newWords)")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                HStack {
                    Text("Learned (graduated):")
                    Spacer()
                    Text("\(stats.graduated)")
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                HStack {
                    Text("To relearn:")
                    Spacer()
                    Text("\(stats.relearning)")
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }

                if remainingCount > 0 {
                    Divider()
                    HStack {
                        Text("Remaining words:")
                        Spacer()
                        Text("\(remainingCount)")
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            if remainingCount > 0, let onContinue = onContinue {
                Button("Continue with remaining") {
                    onContinue()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color.orange)
                .cornerRadius(12)
            }

            Button("Done") {
                onDismiss()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding(30)
    }
}

extension ExerciseView.ExerciseType {
    var displayName: String {
        switch self {
        case .newWords: return "New words"
        case .review: return "Review"
        case .learning: return "Learning"
        case .mixed: return "Mixed"
        case .allInGroup: return "All in group"
        case .chunked(let limit): return "Chunked (\(limit) words)"
        case .favorites: return "Favorites"
        }
    }
}

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

#Preview("ExerciseView") {
    NavigationView {
        ExerciseView(groupId: 1, exerciseType: .mixed)
            .environment(AppState())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

