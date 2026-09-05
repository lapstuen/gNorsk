import SwiftUI
import AVFoundation
import CoreData

private enum DictLang: String, CaseIterable {
    case thai, english
    case morsmaal = "norsk"

    func label(morsmaal: MorsmaalLanguage) -> String {
        switch self {
        case .thai:     return "Norwegian"
        case .english:  return "English"
        case .morsmaal: return morsmaal.label
        }
    }

    func locale(morsmaal: MorsmaalLanguage) -> Locale {
        switch self {
        case .thai:     return Locale(identifier: "nb-NO")
        case .english:  return Locale(identifier: "en-US")
        case .morsmaal: return Locale(identifier: morsmaal.locale)
        }
    }

    func translationCode(morsmaal: MorsmaalLanguage) -> String {
        switch self {
        case .thai:     return "no"
        case .english:  return "en"
        case .morsmaal: return morsmaal.translationCode
        }
    }
}

// Hvor lenge stillhet tolereres før opptaket stopper automatisk og oversetter.
// "Uendelig" beholder gammel oppførsel: restarter lytting til du stopper selv.
// Et konkret antall sekunder gir korte, raske oppslag (stopper og oversetter
// automatisk ved stillhet, i stedet for å fortsette å lytte).
private enum SilenceTimeoutOption: String, CaseIterable {
    case sec1, sec2, sec3, unendelig

    var label: String {
        switch self {
        case .sec1: return "1s"
        case .sec2: return "2s"
        case .sec3: return "3s"
        case .unendelig: return "∞"
        }
    }

    // nil = restart-løkken (uendelig diktering), ellers antall sekunder stillhet
    // før automatisk stopp+oversettelse.
    var seconds: Double? {
        switch self {
        case .sec1: return 1.0
        case .sec2: return 2.0
        case .sec3: return 3.0
        case .unendelig: return nil
        }
    }
}

struct VoiceDictationView: View {
    @AppStorage("dictInputLang")  private var inputLang: DictLang = .thai
    @AppStorage("dictOutputLang") private var outputLang: DictLang = .morsmaal
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @AppStorage("dictSilenceTimeout") private var silenceTimeoutOption: SilenceTimeoutOption = .sec2

    @Environment(\.managedObjectContext) private var context
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var liveTranscript = ""
    @State private var outputText = ""
    @State private var isTranslating = false
    @State private var isUserRecording = false
    @State private var outputSynth = AVSpeechSynthesizer()

    // Thai word chips
    @State private var thaiTokens: [String] = []
    @State private var tokenEnglishMap: [String: String] = [:]
    @State private var tokenExistsSet: Set<String> = []
    @State private var activeLookupToken: String? = nil

    // Stop stats
    @State private var showStopStats = false
    @State private var stopCharCount = 0
    @State private var stopWordCount = 0

    // Copy button feedback
    @State private var justCopied = false

    @FocusState private var isInputFocused: Bool


    @State private var speechManager: SpeechManager = {
        let mgr = SpeechManager(locale: Locale(identifier: "nb-NO"))
        mgr.firstWordTimeout = 300.0
        mgr.silenceAfterWordTimeout = 4.0
        mgr.audioMode = .voiceChat
        return mgr
    }()

    private var inputDisplay: String {
        let sep = inputText.isEmpty ? "" : " "
        return liveTranscript.isEmpty ? inputText : inputText + sep + liveTranscript
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Input field ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    if !inputDisplay.isEmpty {
                        Button { speak(inputDisplay, lang: inputLang) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                if isUserRecording {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(inputDisplay.isEmpty ? "Speech appears here…" : inputDisplay)
                                .foregroundStyle(inputDisplay.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                                .font(.system(size: 23, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                            Color.clear.frame(height: 1).id("inputBottom")
                        }
                        .frame(minHeight: 80, maxHeight: 160)
                        .onChange(of: inputDisplay) { _, _ in
                            withAnimation { proxy.scrollTo("inputBottom", anchor: .bottom) }
                        }
                    }
                } else {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Speech appears here…")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 23, weight: .medium))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .font(.system(size: 23, weight: .medium))
                            .scrollContentBackground(.hidden)
                            .focused($isInputFocused)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 80, maxHeight: 160)
                }

                if case .recording = speechManager.status {
                    VoiceLevelBar(level: speechManager.level)
                        .frame(height: 12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                // Thai word chips (only when Thai input)
                if inputLang == .thai && thaiTokens.count > 1 {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(thaiTokens, id: \.self) { token in
                                    DictationTokenChip(
                                        token: token,
                                        englishWord: tokenEnglishMap[token],
                                        existsInDB: tokenExistsSet.contains(token),
                                        isActive: activeLookupToken == token
                                    ) {
                                        activeLookupToken = activeLookupToken == token ? nil : token
                                    }
                                    .id(token)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: activeLookupToken) { _, newToken in
                            if let t = newToken {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(t, anchor: .center)
                                }
                            }
                        }
                    }
                    
                    Spacer()

                    if let active = activeLookupToken {
                        HStack(spacing: 6) {
                            Text(active)
                                .font(.headline)
                            Text("->")
                                .foregroundStyle(.secondary)
                            Text(tokenEnglishMap[active] ?? "—")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }

                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            // ── Output field ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    if isTranslating {
                        ProgressView().scaleEffect(0.8).padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ScrollView {
                    HStack(alignment: .top) {
                        Text(outputText.isEmpty ? "Translation appears here…" : outputText)
                            .foregroundStyle(outputText.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .font(.system(size: 23, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        
                        if !outputText.isEmpty {
                            Button {
                                speak(outputText, lang: outputLang)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .frame(height: 150)

                // Overflødig: oversettelse trigges allerede automatisk når mic slippes
                // (toggleMic) og når output-språk endres (onChange(of: outputLang)).
                /*
                Button {
                    let text = inputDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    performTranslation(text: text)
                } label: {
                    HStack(spacing: 6) {
                        if isTranslating {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Translate all")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(inputDisplay.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(inputDisplay.isEmpty || isTranslating || isUserRecording)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                */
            }

            Divider()

            // ── Tidsavbrudd (venstre) · Språkvalg (midt) · Bytt (høyre) ──
            HStack(spacing: 5) {
                Menu {
                    ForEach(SilenceTimeoutOption.allCases, id: \.self) { option in
                        Button {
                            silenceTimeoutOption = option
                        } label: {
                            if silenceTimeoutOption == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Text(silenceTimeoutOption.label)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 1)
                        .frame(width: 30)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.primary)
                }
                .menuIndicator(.hidden)

                Spacer()

                langMenuButton(selection: $inputLang)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                langMenuButton(selection: $outputLang)

                Spacer()

                // Bytt input/output-språk — praktisk når to personer som snakker
                // forskjellige språk deler telefonen: trykk for å bytte hvem som
                // "eier" hvilket språk, uten å måtte velge på nytt fra menyene.
                Button {
                    let old = inputLang
                    inputLang = outputLang
                    outputLang = old
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Controls ──────────────────────────────────────────────
            HStack(spacing: 36) {
                Button {
                    UIPasteboard.general.string = outputText
                    Notifier.shared.show(.success, "Copied!")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        justCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { justCopied = false }
                    }
                } label: {
                    Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .font(.title2)
                        .foregroundStyle(outputText.isEmpty ? Color.secondary : (justCopied ? Color.green : Color.accentColor))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(
                            outputText.isEmpty ? Color.secondary.opacity(0.08) : (justCopied ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                        ))
                        .scaleEffect(justCopied ? 1.15 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(outputText.isEmpty)

                Button { toggleMic() } label: {
                    ZStack {
                        Circle()
                            .fill(isUserRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                            .frame(width: 88, height: 88)
                        Image(systemName: isUserRecording ? "mic.fill" : "mic")
                            .font(.system(size: 36))
                            .foregroundStyle(isUserRecording ? .red : .accentColor)
                    }
                }
                .buttonStyle(.plain)

                Button { saveWholeText() } label: {
                    ZStack {
                        Circle().fill(inputDisplay.isEmpty ? Color.secondary.opacity(0.08) : Color.green.opacity(0.8))
                        if isTranslating {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .disabled(inputDisplay.isEmpty || isTranslating)

                Button {
                    inputText = ""
                    liveTranscript = ""
                    outputText = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundStyle(inputDisplay.isEmpty && outputText.isEmpty ? Color.secondary : Color.red)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(
                            inputDisplay.isEmpty && outputText.isEmpty ? Color.secondary.opacity(0.08) : Color.red.opacity(0.1)
                        ))
                }
                .buttonStyle(.plain)
                .disabled(inputDisplay.isEmpty && outputText.isEmpty)
            }
            .frame(height: 130)
        }
        // MIDLERTIDIG: lyseblå bakgrunn kun for å identifisere dette som
        // riktig vindu i Claude-samtalen — fjern når det er bekreftet.
        .background(Color.blue.opacity(0.15))
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
        .navigationTitle("Voice Dictation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            setupCallbacks()
            speechManager.setLocale(inputLang.locale(morsmaal: morsmaalLanguage))
            speechManager.silenceAfterWordTimeout = silenceTimeoutOption.seconds ?? 4.0
            speechManager.requestAuth()
        }
        .onDisappear {
            isUserRecording = false
            speechManager.stop()
        }
        .onChange(of: silenceTimeoutOption) { _, newOption in
            speechManager.silenceAfterWordTimeout = newOption.seconds ?? 4.0
        }
        .onChange(of: inputLang) { _, newLang in
            speechManager.setLocale(newLang.locale(morsmaal: morsmaalLanguage))
            inputText = ""
            liveTranscript = ""
            outputText = ""
            thaiTokens = []
            tokenEnglishMap = [:]
            tokenExistsSet = []
            activeLookupToken = nil
            if isUserRecording {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if isUserRecording { speechManager.start() }
                }
            }
        }
        .onChange(of: outputLang) { _, _ in
            guard !isUserRecording else { return }
            let text = inputDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            performTranslation(text: text, autoSpeak: true)
        }
        .onChange(of: inputText) { _, newText in
            guard inputLang == .thai, !isUserRecording else { return }
            let full = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            refreshThaiTokens(text: full)
        }
        // Manglet her fra før — Notifier.shared.show(...) (bl.a. "Saved to …",
        // "Save failed", og duplikat-varselet) oppdaterte alltid Notifier sin
        // delte tilstand stille i bakgrunnen uten at noe faktisk ble vist, siden
        // ingen view i dette skjermbildet observerte den (se ToastView/wireNotifications).
        .wireNotifications()
        // Statistikk-popup etter opptak er kommentert vekk (oppleves som forstyrrende bug-side).
        /*
        .sheet(isPresented: $showStopStats) {
            DictationStatsView(charCount: stopCharCount, wordCount: stopWordCount)
                .presentationDetents([.height(180)])
                .presentationDragIndicator(.visible)
        }
        */
    }

    // Fri kombinasjon: alle tre språk (Thai/English/morsmål=Norsk) vises alltid som
    // knapper for både input og output — du velger fritt hvilken kombinasjon du vil,
    // ingen fast "du dikterer alltid på morsmål"-regel lenger.
    private var visibleDictLangs: [DictLang] {
        DictLang.allCases
    }

    // Knapp (pille) som viser gjeldende språk og åpner en meny med alle tre
    // språkene (Thai/English/Norsk) å velge blant — matcher "Norsk → English"
    // to-pille-med-pil-oppsettet, men med full valgfrihet på hver side.
    @ViewBuilder
    private func langMenuButton(selection: Binding<DictLang>) -> some View {
        Menu {
            ForEach(visibleDictLangs, id: \.self) { lang in
                Button {
                    selection.wrappedValue = lang
                } label: {
                    if selection.wrappedValue == lang {
                        Label(lang.label(morsmaal: morsmaalLanguage), systemImage: "checkmark")
                    } else {
                        Text(lang.label(morsmaal: morsmaalLanguage))
                    }
                }
            }
        } label: {
            
            Text(selection.wrappedValue.label(morsmaal: morsmaalLanguage))

                .font(.subheadline.weight(.semibold))

                .padding(.horizontal, 16)

                .padding(.vertical, 8)

                .frame(minWidth: 100)

                .background(Capsule().fill(Color.accentColor))

                .foregroundStyle(.white)

        }
        .menuIndicator(.hidden)
    }

    private let charLimit = 10_000

    /// Stopper mikrofonen og flytter det som er transkribert så langt inn i
    /// `inputText`, hvis opptak pågår — ellers en no-op. Kalles fra både
    /// `toggleMic()` (mik-knappen) og `saveWholeText()` (det grønne
    /// lagre-ikonet), slik at man ikke lenger må huske å trykke mik-knappen
    /// manuelt før lagring: uten dette leste lagringen kun `inputText`, og
    /// det som nettopp ble sagt (og lå i `liveTranscript`) forsvant stille.
    private func stopRecordingIfNeeded() {
        guard isUserRecording else { return }
        isUserRecording = false
        speechManager.stop()
        if !liveTranscript.isEmpty {
            inputText += (inputText.isEmpty ? "" : " ") + liveTranscript
            liveTranscript = ""
        }
    }

    private func toggleMic() {
        if isUserRecording {
            stopRecordingIfNeeded()
            let text = inputDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            performTranslation(text: text, autoSpeak: true)
            stopCharCount = text.count
            if inputLang == .thai {
                stopWordCount = refreshThaiTokens(text: text)
            } else {
                stopWordCount = 0
            }
            showStopStats = true
        } else {
            // Samme opprydding som søppelbøtte-knappen — start alltid friskt før ny diktering.
            inputText = ""
            outputText = ""
            liveTranscript = ""
            isUserRecording = true
            speechManager.start()
        }
    }

    private func setupCallbacks() {
        // Under opptak: bare oppdater liveTranscript — ingen oversettelse, ingen segmentering
        speechManager.onTranscriptUpdate = { partial in
            liveTranscript = partial
        }

        speechManager.onTranscriptComplete = { final in
            let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Apples talegjenkjenning kapitaliserer alltid første bokstav i diktert tekst
                // (standard diktat-oppførsel, ikke bare ved reell setningsstart) — rettes tilbake.
                let normalized = trimmed.prefix(1).lowercased() + trimmed.dropFirst()
                inputText += (inputText.isEmpty ? "" : " ") + normalized
            }
            liveTranscript = ""

            // Endelig tidsavbrudd (ikke "uendelig"): stopp og oversett automatisk
            // ved stillhet, ikke restart — matcher det den gamle Oversettelse-
            // knappen gjorde med sitt korte, faste 1-sekunds avbrudd.
            if silenceTimeoutOption != .unendelig {
                isUserRecording = false
                speechManager.stop()
                let text = inputDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                performTranslation(text: text, autoSpeak: true)
                if inputLang == .thai { refreshThaiTokens(text: text) }
                return
            }

            // Sjekk tegngrense
            if inputText.count >= charLimit {
                isUserRecording = false
                speechManager.stop()
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    performTranslation(text: text)
                    stopCharCount = text.count
                    stopWordCount = inputLang == .thai ? refreshThaiTokens(text: text) : 0
                    showStopStats = true
                }
                return
            }

            // Restart session hvis brukeren fortsatt vil ta opp (kun "uendelig")
            if isUserRecording {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isUserRecording { speechManager.start() }
                }
            }
        }
    }

    @discardableResult
    private func refreshThaiTokens(text: String) -> Int {
        guard !text.isEmpty else {
            thaiTokens = []
            tokenEnglishMap = [:]
            tokenExistsSet = []
            activeLookupToken = nil
            return 0
        }
        let (_, debugTokens) = HybridSegmentationPipeline.run(
            text: text,
            context: context,
            ignorePrecomputedSyllables: false,
            useAppleNLWordPreprocess: false
        )
        thaiTokens = debugTokens
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "thaiWord IN %@", debugTokens)
        if let results = try? context.fetch(req) {
            var map: [String: String] = [:]
            var exists: Set<String> = []
            for w in results {
                if let thai = w.thaiWord {
                    exists.insert(thai)
                    if let eng = w.englishWord, !eng.isEmpty { map[thai] = eng }
                }
            }
            tokenEnglishMap = map
            tokenExistsSet = exists
        }
        if let active = activeLookupToken, !debugTokens.contains(active) {
            activeLookupToken = nil
        }
        return debugTokens.count
    }

    /// Lagrer uansett hvilket språk du dikterte på: `inputText`/`outputText` gir
    /// to av de tre språkene gratis (allerede oversatt av `performTranslation`),
    /// og kun det tredje, manglende språket hentes med ett ekstra
    /// oversettelses-kall — samme mønster som `lookupThaiAndEnglishFromMorsmaal`
    /// i `CreateWordView`/`AddSentenceView`.
    private func saveWholeText() {
        stopRecordingIfNeeded()
        let text = inputDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var resolved: [DictLang: String] = [inputLang: text]
        let output = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if outputLang != inputLang, !output.isEmpty {
            resolved[outputLang] = output
        }

        let missingLangs = DictLang.allCases.filter { resolved[$0] == nil }
        guard !missingLangs.isEmpty else {
            finishSavingWord(resolved)
            return
        }

        isTranslating = true
        var translationFailed = false
        let group = DispatchGroup()
        for lang in missingLangs {
            group.enter()
            translateForSave(text: text, from: inputLang, to: lang) { translated in
                if let translated {
                    resolved[lang] = translated
                } else {
                    translationFailed = true
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.isTranslating = false
            if translationFailed {
                Notifier.shared.show(.error, "Translation failed — fill in the missing field(s) manually and try again.")
                return
            }
            self.finishSavingWord(resolved)
        }
    }

    /// Ved feil kalles `completion(nil)` — kalleren skal vise en feilmelding, ikke late som
    /// kildeteksten var en gyldig oversettelse. Tidligere kalte denne funksjonen et uoffisielt
    /// Google-endepunkt direkte; bruker nå den delte AppleTranslationService (se
    /// SwiftGeneral/AppleTranslationService.swift).
    private func translateForSave(text: String, from: DictLang, to: DictLang, completion: @escaping (String?) -> Void) {
        AppleTranslationService.shared.translate(
            text: text,
            fromLanguage: from.translationCode(morsmaal: morsmaalLanguage),
            toLanguage: to.translationCode(morsmaal: morsmaalLanguage),
            completion: completion
        )
    }

    private func finishSavingWord(_ byLang: [DictLang: String]) {
        guard var thaiWord = byLang[.thai]?.trimmingCharacters(in: .whitespacesAndNewlines), !thaiWord.isEmpty else { return }
        // Apples talegjenkjenning kapitaliserer alltid første bokstav i diktert tekst
        // (standard diktat-oppførsel) — det skal det norske ordfeltet ikke ha.
        thaiWord = thaiWord.prefix(1).lowercased() + thaiWord.dropFirst()

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetch.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
        fetch.fetchLimit = 1
        if let existing = try? context.fetch(fetch), !existing.isEmpty {
            Notifier.shared.show(.warning, "\"\(thaiWord)\" already exists")
            return
        }

        let english = byLang[.english]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let native = byLang[.morsmaal]?.trimmingCharacters(in: .whitespacesAndNewlines)

        let word = ThaiWords(context: context)
        word.id = UUID()
        word.thaiWord = thaiWord
        word.englishWord = english?.isEmpty == false ? english : nil
        word.translation1 = native?.isEmpty == false ? native : nil
        word.groupId = appState.valgtGruppeId
        word.insertDate = Date()
        word.modifiedDate = Date()
        do {
            try context.save()
            Notifier.shared.show(.success, "Saved to \(appState.valgtGruppeNavn.isEmpty ? "group" : appState.valgtGruppeNavn)")
        } catch {
            Notifier.shared.show(.error, "Save failed: \(error.localizedDescription)")
        }
    }

    private func speak(_ text: String, lang: DictLang) {
        if lang == .thai {
            g.talkTh(talkText: text, rate: 0.5, language: lang.locale(morsmaal: morsmaalLanguage).identifier)
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            let utter = AVSpeechUtterance(string: text)
            utter.voice = AVSpeechSynthesisVoice(language: lang.locale(morsmaal: morsmaalLanguage).identifier)
            let rateKey = lang == .english ? "speechRateEnglish" : "speechRateMorsmaal"
            let storedRate = UserDefaults.standard.double(forKey: rateKey)
            utter.rate = storedRate > 0 ? Float(storedRate) : 0.5
            utter.volume = 1.0
            if outputSynth.isSpeaking { outputSynth.stopSpeaking(at: .immediate) }
            outputSynth.speak(utter)
        }
    }

    private func performTranslation(text: String, autoSpeak: Bool = false) {
        let mlang = MorsmaalLanguage(rawValue: UserDefaults.standard.string(forKey: "morsmaalLanguage") ?? "norsk") ?? .norsk
        let from = DictLang(rawValue: UserDefaults.standard.string(forKey: "dictInputLang") ?? "thai") ?? .thai
        let to   = DictLang(rawValue: UserDefaults.standard.string(forKey: "dictOutputLang") ?? "norsk") ?? .morsmaal
        guard from != to else {
            outputText = text
            if autoSpeak { speak(text, lang: to) }
            return
        }
        // Tidligere kalte denne funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den
        // delte AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
        isTranslating = true
        AppleTranslationService.shared.translate(
            text: text,
            fromLanguage: from.translationCode(morsmaal: mlang),
            toLanguage: to.translationCode(morsmaal: mlang)
        ) { translated in
            DispatchQueue.main.async {
                isTranslating = false
                guard let translated else {
                    Notifier.shared.show(.error, "Translation failed.")
                    return
                }
                outputText = translated
                if autoSpeak { speak(translated, lang: to) }
            }
        }
    }
}

private struct DictationTokenChip: View {
    let token: String
    let englishWord: String?
    let existsInDB: Bool
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.openURL) private var openURL
    @AppStorage("tokenButtonSpeechEnabled") private var speechEnabled = false
    @State private var showOrstDict = false
    @State private var showThaiLangDict = false

    var body: some View {
        Button { onTap() } label: {
            Text(token)
                .font(.largeTitle)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(existsInDB ? Color(.quaternaryLabel) : Color.orange.opacity(0.25))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive ? Color.red : (existsInDB ? Color.clear : Color.orange.opacity(0.6)),
                            lineWidth: isActive ? 2.5 : 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                speechEnabled.toggle()
            } label: {
                Label(speechEnabled ? "Speech: On" : "Speech: Off",
                      systemImage: speechEnabled ? "speaker.wave.2.fill" : "speaker.slash")
            }
            Divider()
            Button {
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Thai2English", systemImage: "globe.asia.australia")
            }
            Button { showThaiLangDict = true } label: {
                Label("thai-language.com", systemImage: "character.book.closed")
            }
            Button {
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://dict.longdo.com/?search=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Longdo Dict", systemImage: "book.pages")
            }
            Button { showOrstDict = true } label: {
                Label("Royal Society Dictionary", systemImage: "text.book.closed")
            }
            Button {
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://forvo.com/search/\(encoded)/no/") {
                    openURL(url)
                }
            } label: {
                Label("Forvo", systemImage: "person.wave.2")
            }
            Button {
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://papago.naver.com/?sk=no&tk=th&st=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Papago", systemImage: "p.circle.fill")
            }
            Button {
                openGoogleTranslate(token, targetLang: "th", using: openURL)
            } label: {
                Label("Google Translate", systemImage: "g.circle.fill")
            }
        }
        .sheet(isPresented: $showOrstDict) {
            OrstDictionaryView(word: token)
        }
        .sheet(isPresented: $showThaiLangDict) {
            ThaiLanguageDictionaryView(word: token)
        }
    }
}

private struct DictationStatsView: View {
    let charCount: Int
    let wordCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Recording Statistics")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("\(charCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("characters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if wordCount > 0 {
                    Divider().frame(height: 60)
                    VStack(spacing: 4) {
                        Text("\(wordCount)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("words found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

private struct VoiceLevelBar: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(level > 0.6 ? Color.orange : Color.green)
                    .frame(width: geo.size.width * CGFloat(min(level, 1.0)))
            }
        }
        .animation(.easeOut(duration: 0.05), value: level)
    }
}

#Preview {
    NavigationStack {
        VoiceDictationView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environment(AppState())
}
