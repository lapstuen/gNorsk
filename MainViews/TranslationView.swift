//
//  TranslationView.swift
//  gThai
//
//  Created by Geir Lapstuen on 2/10/26.
//
import SwiftUI
import CoreData
import AVFoundation

struct TranslationView: View {
    @State private var showingSegmentation = false
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var thaiWord = ""
    @State private var englishWord = ""
    @State private var morsmaal = ""
    @State private var isTranslating = false
    @State private var currentLookupID = UUID()
    @State private var wordExists = false
    @State private var existingWord: ThaiWords?
    @State private var showExistingWordDetails = false
    @FocusState private var focusedField: TranslationField?
    @State private var speechManager: SpeechManager = {
        let mgr = SpeechManager(locale: Locale(identifier: "en-US"))
        mgr.firstWordTimeout = 300.0        // 5 minutter
        mgr.silenceAfterWordTimeout = 1.0
        mgr.audioMode = .voiceChat           // AGC + støyreduksjon for bedre opptak
        return mgr
    }()
    @AppStorage("translationSpeechInputMode") private var speechMode: TranslationSpeechMode = .english
    @AppStorage("translationOutputMode") private var outputMode: TranslationSpeechMode = .thai
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @AppStorage("speechRateEnglish") private var speechRateEnglish: Double = 0.5
    @AppStorage("speechRateMorsmaal") private var speechRateMorsmaal: Double = 0.5
    @AppStorage("imageTapLanguage") private var imageTapLanguage: ImageTapLanguage = .thai
    @State private var speechSynth = AVSpeechSynthesizer()
    @State private var thaiCopied = false
    @State private var isKeyboardVisible = false

    enum TranslationField {
        case thai, morsmaal, english
    }

    enum TranslationSpeechMode: String, CaseIterable {
        case english, thai
        case morsmaal = "norsk"

        func label(morsmaal: MorsmaalLanguage) -> String {
            switch self {
            case .english: return "English"
            case .morsmaal: return morsmaal.label
            case .thai: return "Norwegian"
            }
        }

        func locale(morsmaal: MorsmaalLanguage) -> Locale {
            switch self {
            case .english: return Locale(identifier: "en-US")
            case .morsmaal: return Locale(identifier: morsmaal.locale)
            case .thai: return Locale(identifier: "nb-NO")
            }
        }
    }

    private func navigateToExistingWord() {
        if let word = existingWord {
            appState.pendingGridWordIDs = [word.objectID]
        }
        appState.pendingOpenGrid = true
        dismiss()
    }

    private func checkIfWordExists() {
        let trimmed = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            wordExists = false
            existingWord = nil
            return
        }

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetch.predicate = NSPredicate(format: "thaiWord == %@", trimmed)
        fetch.fetchLimit = 1

        do {
            let results = try context.fetch(fetch)
            if let found = results.first {
                wordExists = true
                existingWord = found
            } else {
                wordExists = false
                existingWord = nil
            }
        } catch {
            wordExists = false
            existingWord = nil
        }
    }

    func lagreNyttOrd() {
        let trimmed = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Notifier.shared.show(.warning, "Enter a Norwegian word before saving.")
            return
        }

        // Ikke tillat lagring hvis ordet eksisterer
        guard !wordExists else {
            return
        }

        // Check if English translation is needed
        if englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isTranslating = true
            translateText(text: trimmed, fromLanguage: "no", toLanguage: "en") { [self] translation in
                DispatchQueue.main.async {
                    self.isTranslating = false
                    guard let translation else {
                        Notifier.shared.show(.error, "Translation failed — fill in English manually and save again.")
                        return
                    }
                    self.englishWord = translation
                    self.saveWordToCoreData(thaiWord: trimmed, englishWord: translation)
                }
            }
        } else {
            saveWordToCoreData(thaiWord: trimmed, englishWord: englishWord)
        }
    }

    private func saveWordToCoreData(thaiWord: String, englishWord: String) {
        do {
            let nyttOrd = ThaiWords(context: context)
            nyttOrd.id          = UUID()
            nyttOrd.thaiWord      = thaiWord
            nyttOrd.englishWord   = englishWord
            nyttOrd.translation1  = morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : morsmaal
            nyttOrd.groupId       = appState.sqlGruppeId

            try context.save()

            Notifier.shared.show(.success, "Word added: \(thaiWord)")
            dismiss()

        } catch {
            Notifier.shared.show(.error, "Failed to create word: \(error.localizedDescription)")
        }
    }

    private func speakNorsk() {
        let text = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        CloudTTSTest.speakNorsk(text)
    }

    // Skjul duplikat: hvis morsmål er satt til Engelsk eller Thai, dropp den faste
    // knappen for samme språk (unngår f.eks. "Thai / English / Engelsk").
    private var visibleSpeechModes: [TranslationSpeechMode] {
        TranslationSpeechMode.allCases.filter { mode in
            switch mode {
            case .thai:     return morsmaalLanguage != .norsk
            case .english:  return morsmaalLanguage != .engelsk
            case .morsmaal: return true
            }
        }
    }

    // Med 3 språk: du dikterer alltid inn på morsmål, og velger selv (og appen husker)
    // hvilket av de to andre språkene som skal leses opp igjen.
    // Med 2 språk: input kan være hvilket som helst av de to, output blir automatisk det andre.
    private var inputOptions: [TranslationSpeechMode] {
        visibleSpeechModes.count == 3 ? [.morsmaal] : visibleSpeechModes
    }
    private var outputOptions: [TranslationSpeechMode] {
        visibleSpeechModes.count == 3 ? [.thai, .english] : visibleSpeechModes
    }

    private func normalizeLangSelection() {
        let visible = visibleSpeechModes
        if visible.count == 3 {
            if speechMode != .morsmaal { speechMode = .morsmaal }
            if outputMode == .morsmaal { outputMode = .thai }
            return
        }
        if !visible.contains(speechMode) { speechMode = .morsmaal }
        if !visible.contains(outputMode) { outputMode = .morsmaal }
        if speechMode == outputMode, let other = visible.first(where: { $0 != speechMode }) {
            outputMode = other
        }
    }

    private var canLookup: Bool {
        switch speechMode {
        case .english:  return !englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .morsmaal: return !morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .thai:     return !thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func handleManualLookup() {
        let requestID = UUID()
        currentLookupID = requestID
        switch speechMode {
        case .english:
            let text = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            isTranslating = true
            translateText(text: text, fromLanguage: "en", toLanguage: "no") { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "Norwegian translation failed — fill in manually.")
                        return
                    }
                    self.thaiWord = translation
                }
            }
            let mlang = morsmaalLanguage
            translateText(text: text, fromLanguage: "en", toLanguage: mlang.translationCode) { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    self.isTranslating = false
                    guard let translation else {
                        Notifier.shared.show(.error, "\(mlang.label) translation failed — fill in manually.")
                        return
                    }
                    self.morsmaal = translation
                }
            }
        case .morsmaal:
            let text = morsmaal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            isTranslating = true
            let mlang = morsmaalLanguage
            translateText(text: text, fromLanguage: mlang.translationCode, toLanguage: "no") { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "Norwegian translation failed — fill in manually.")
                        return
                    }
                    self.thaiWord = translation
                }
            }
            translateText(text: text, fromLanguage: mlang.translationCode, toLanguage: "en") { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    self.isTranslating = false
                    guard let translation else {
                        Notifier.shared.show(.error, "English translation failed — fill in manually.")
                        return
                    }
                    self.englishWord = translation
                }
            }
        case .thai:
            let text = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            isTranslating = true
            let mlang = morsmaalLanguage
            translateText(text: text, fromLanguage: "no", toLanguage: "en") { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "English translation failed — fill in manually.")
                        return
                    }
                    self.englishWord = translation
                }
            }
            translateText(text: text, fromLanguage: "no", toLanguage: mlang.translationCode) { translation in
                DispatchQueue.main.async {
                    guard self.currentLookupID == requestID else { return }
                    self.isTranslating = false
                    guard let translation else {
                        Notifier.shared.show(.error, "\(mlang.label) translation failed — fill in manually.")
                        return
                    }
                    self.morsmaal = translation
                }
            }
        }
    }

    private func speakCurrentLanguage() {
        switch imageTapLanguage {
        case .thai:
            let t = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            CloudTTSTest.speakNorsk(t)
        case .english:
            speakEnglish()
        case .morsmaal:
            speakMorsmaal()
        case .ingen:
            break
        }
    }

    private func speakMorsmaal() {
        let text = morsmaal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: morsmaalLanguage.voiceId)
            ?? AVSpeechSynthesisVoice(language: morsmaalLanguage.locale)
        utterance.rate = Float(speechRateMorsmaal)
        utterance.volume = 1.0
        speechSynth.speak(utterance)
    }

    private func speakEnglish() {
        let text = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        if let enhancedVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha") {
            utterance.voice = enhancedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = Float(speechRateEnglish)
        utterance.volume = 1.0
        speechSynth.speak(utterance)
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        thaiWord = ""
        englishWord = ""
        morsmaal = ""
        switch speechMode {
        case .english:  englishWord = trimmed
        case .morsmaal: morsmaal = trimmed
        case .thai:     thaiWord = trimmed
        }
        handleManualLookup()
    }

    /// Ved enhver feil kalles `completion(nil)` — kalleren skal vise en feilmelding og la feltet
    /// stå uendret, ikke late som kildeteksten var en gyldig oversettelse. Tidligere brukte denne
    /// funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den delte
    /// AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
    private func translateText(text: String, fromLanguage: String, toLanguage: String, completion: @escaping (String?) -> Void) {
        AppleTranslationService.shared.translate(text: text, fromLanguage: fromLanguage, toLanguage: toLanguage, completion: completion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(appState.valgtGruppeNavn.isEmpty ? "Not set" : appState.valgtGruppeNavn)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

        List {
            Section(header: HStack {
                Button {
                    speakNorsk()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundStyle(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                }
                .disabled(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Norwegian")
                Spacer()
                Button {
                    UIPasteboard.general.string = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    withAnimation { thaiCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { thaiCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: thaiCopied ? "checkmark" : "paperclip")
                            .font(.body)
                        if thaiCopied {
                            Text("Kopiert")
                                .font(.caption.bold())
                        }
                    }
                    .foregroundStyle(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : (thaiCopied ? .green : .accentColor))
                }
                .disabled(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }) {
                ThaiKeyboardTextField(text: $thaiWord, placeholder: "Norwegian word") { _ in
                    checkIfWordExists()
                }
                .frame(height: 44)
                .overlay(alignment: .trailing) {
                    Button {
                        showingSegmentation = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.25) : Color.accentColor)
                                .frame(width: 28, height: 28)
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(4)
                        .accessibilityLabel("Open segmentation")
                    }
                    .buttonStyle(.plain)
                    .disabled(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section(header: HStack {
                Button {
                    speakMorsmaal()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundStyle(morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                }
                .disabled(morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Native language x2")
                Spacer()
            }) {
                TextField("Native language", text: $morsmaal)
                    .font(.title3.bold())
                    .focused($focusedField, equals: .morsmaal)
                    .disabled(isTranslating)
                if isTranslating {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Translating...")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
            }

            Section(header: HStack {
                Button {
                    speakEnglish()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundStyle(englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                }
                .disabled(englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("English")
                //Spacer()
            }) {
                TextField("English", text: $englishWord)
                    .font(.title3.bold())
                    .focused($focusedField, equals: .english)
                    .disabled(isTranslating)
                if isTranslating {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Translating...").foregroundColor(.blue).font(.caption)
                    }
                }
            }

            Section {
                if wordExists {
                    Image(systemName: "square.grid.2x2.fill")
                        .imageScale(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.orange)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.orange.opacity(0.4), radius: 8, x: 0, y: 4)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateToExistingWord() }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } else {
                    let saveDisabled = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating
                    ZStack {
                        if isTranslating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle").imageScale(.large)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(saveDisabled ? Color.accentColor.opacity(0.25) : Color.accentColor)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !saveDisabled else { return }
                        lagreNyttOrd()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                let speakDisabled = imageTapLanguage == .ingen || thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(spacing: 8) {
                    Image(systemName: imageTapLanguage.systemImage).imageScale(.large)
                    Text(imageTapLanguage.label).fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(speakDisabled ? Color.secondary.opacity(0.4) : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !speakDisabled else { return }
                    speakCurrentLanguage()
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 12) {
                    Button { pasteFromClipboard() } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color.accentColor.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    Picker("Language", selection: $speechMode) {
                        ForEach(inputOptions, id: \.self) { mode in
                            Text(mode.label(morsmaal: morsmaalLanguage)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: speechMode) { _, newMode in
                        speechManager.stop()
                        speechManager.transcript = ""
                        speechManager.setLocale(newMode.locale(morsmaal: morsmaalLanguage))
                    }
                    .onChange(of: morsmaalLanguage) { _, _ in
                        normalizeLangSelection()
                    }

                    Button { handleManualLookup() } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.title2)
                            .foregroundStyle(canLookup && !isTranslating ? Color.accentColor : Color.gray)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(canLookup && !isTranslating ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canLookup || isTranslating)
                }

                if visibleSpeechModes.count == 3 {
                    HStack(spacing: 8) {
                        Text("Les opp:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Output", selection: $outputMode) {
                            ForEach(outputOptions, id: \.self) { mode in
                                Text(mode.label(morsmaal: morsmaalLanguage)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if !speechManager.transcript.isEmpty {
                    Text(speechManager.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if case .recording = speechManager.status {
                        speechManager.handleFinalTranscript()
                    } else {
                        speechManager.transcript = ""
                        thaiWord = ""
                        englishWord = ""
                        morsmaal = ""
                        speechManager.start()
                    }
                } label: {
                    Image(systemName: speechManager.status == .recording ? "mic.fill" : "mic")
                        .font(.system(size: 42))
                        .foregroundStyle(speechManager.status == .recording ? .red : .accentColor)
                        .frame(width: 108, height: 108)
                        .background(Circle().fill(speechManager.status == .recording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }.listSectionSpacing(2) // kan settes til f.eks. 0, 4, 8 osv.
        } // VStack
        .navigationTitle("Translation")
        .sheet(isPresented: $showingSegmentation) {
            HybridSegmentationView(text: thaiWord)
                .environment(\.managedObjectContext, context)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            normalizeLangSelection()
            // Speech-to-text callback med modus-avhengig flyt
            speechManager.onTranscriptComplete = { (text: String) in
                let currentMode = TranslationSpeechMode(rawValue: UserDefaults.standard.string(forKey: "translationSpeechInputMode") ?? "english") ?? .english
                let mlang = MorsmaalLanguage(rawValue: UserDefaults.standard.string(forKey: "morsmaalLanguage") ?? "norsk") ?? .norsk
                let outSel = TranslationSpeechMode(rawValue: UserDefaults.standard.string(forKey: "translationOutputMode") ?? "thai") ?? .thai

                // Med 3 synlige språk: les opp det valgte "output"-språket.
                // Med 2 synlige språk: les alltid opp det andre av de to (motsatt av det du dikterte inn).
                let visible = TranslationSpeechMode.allCases.filter { mode in
                    switch mode {
                    case .thai:     return mlang != .norsk
                    case .english:  return mlang != .engelsk
                    case .morsmaal: return true
                    }
                }
                let targetSpeak = visible.count == 3 ? outSel : (visible.first(where: { $0 != currentMode }) ?? outSel)

                switch currentMode {
                case .english:
                    englishWord = text
                    if targetSpeak == .english { speakEnglish() }
                    translateText(text: text, fromLanguage: "en", toLanguage: "no") { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "Norwegian translation failed — fill in manually.")
                                return
                            }
                            thaiWord = translation
                            if targetSpeak == .thai { speakNorsk() }
                        }
                    }
                    translateText(text: text, fromLanguage: "en", toLanguage: mlang.translationCode) { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "\(mlang.label) translation failed — fill in manually.")
                                return
                            }
                            morsmaal = translation
                            UIPasteboard.general.string = translation
                            if targetSpeak == .morsmaal { speakMorsmaal() }
                        }
                    }

                case .morsmaal:
                    morsmaal = text
                    if targetSpeak == .morsmaal { speakMorsmaal() }
                    translateText(text: text, fromLanguage: mlang.translationCode, toLanguage: "no") { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "Norwegian translation failed — fill in manually.")
                                return
                            }
                            thaiWord = translation
                            if targetSpeak == .thai { speakNorsk() }
                        }
                    }
                    translateText(text: text, fromLanguage: mlang.translationCode, toLanguage: "en") { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "English translation failed — fill in manually.")
                                return
                            }
                            englishWord = translation
                            UIPasteboard.general.string = translation
                            if targetSpeak == .english { speakEnglish() }
                        }
                    }

                case .thai:
                    thaiWord = text
                    if targetSpeak == .thai { speakNorsk() }
                    translateText(text: text, fromLanguage: "no", toLanguage: "en") { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "English translation failed — fill in manually.")
                                return
                            }
                            englishWord = translation
                            UIPasteboard.general.string = translation
                            if targetSpeak == .english { speakEnglish() }
                        }
                    }
                    translateText(text: text, fromLanguage: "no", toLanguage: mlang.translationCode) { translation in
                        DispatchQueue.main.async {
                            guard let translation else {
                                Notifier.shared.show(.error, "\(mlang.label) translation failed — fill in manually.")
                                return
                            }
                            morsmaal = translation
                            if targetSpeak == .morsmaal { speakMorsmaal() }
                        }
                    }
                }
            }
            speechManager.setLocale(speechMode.locale(morsmaal: morsmaalLanguage))
            speechManager.requestAuth()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onDisappear {
            speechManager.stop()
            Notifier.shared.hide()
        }
    }
}

#Preview {
    // In-memory Core Data for preview
    let previewController = PersistenceController.preview
    let context = previewController.container.viewContext

    // AppState med noen eksempelverdier
    let state = AppState()
    state.valgtGruppeNavn = "Demo group"
    state.sqlGruppeId = 1
    state.valgtGruppeId = 1

    return NavigationStack {
        TranslationView()
            .environment(state)
            .environment(\.managedObjectContext, context)
    }
}

// UITextField-subklasse som alltid returnerer norsk-tastaturet
private final class _ThaiUITextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "nb-NO" }
            ?? super.textInputMode
    }
}

private struct ThaiKeyboardTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onChange: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onChange: onChange) }

    func makeUIView(context: Context) -> _ThaiUITextField {
        let field = _ThaiUITextField()
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 28, weight: .bold)
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: _ThaiUITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onChange: ((String) -> Void)?
        init(text: Binding<String>, onChange: ((String) -> Void)?) {
            _text = text
            self.onChange = onChange
        }
        @objc func textChanged(_ field: UITextField) {
            text = field.text ?? ""
            onChange?(field.text ?? "")
        }
    }
}

