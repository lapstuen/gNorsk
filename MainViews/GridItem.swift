import SwiftUI
import AVFoundation
import CoreData
import UniformTypeIdentifiers

enum MorsmaalLanguage: String, CaseIterable {
    case norsk, engelsk, fransk, tysk, spansk, svensk, dansk, kinesisk, thai

    var label: String {
        switch self {
        case .norsk:    return "Norwegian"
        case .engelsk:  return "English"
        case .fransk:   return "French"
        case .tysk:     return "German"
        case .spansk:   return "Spanish"
        case .svensk:   return "Swedish"
        case .dansk:    return "Danish"
        case .kinesisk: return "Chinese"
        case .thai:     return "Thai"
        }
    }

    var locale: String {
        switch self {
        case .norsk:    return "nb-NO"
        case .engelsk:  return "en-US"
        case .fransk:   return "fr-FR"
        case .tysk:     return "de-DE"
        case .spansk:   return "es-ES"
        case .svensk:   return "sv-SE"
        case .dansk:    return "da-DK"
        case .kinesisk: return "zh-CN"
        case .thai:     return "th-TH"
        }
    }

    var translationCode: String {
        switch self {
        case .norsk:    return "no"
        case .engelsk:  return "en"
        case .fransk:   return "fr"
        case .tysk:     return "de"
        case .spansk:   return "es"
        case .svensk:   return "sv"
        case .dansk:    return "da"
        case .kinesisk: return "zh-CN"
        case .thai:     return "th"
        }
    }

    var voiceId: String {
        switch self {
        case .norsk:    return "com.apple.voice.enhanced.nb-NO.Nora"
        case .engelsk:  return "com.apple.voice.enhanced.en-US.Samantha"
        case .fransk:   return "com.apple.voice.enhanced.fr-FR.Amelie"
        case .tysk:     return "com.apple.voice.enhanced.de-DE.Anna"
        case .spansk:   return "com.apple.voice.enhanced.es-ES.Monica"
        case .svensk:   return "com.apple.voice.enhanced.sv-SE.Alva"
        case .dansk:    return "com.apple.voice.enhanced.da-DK.Sara"
        case .kinesisk: return "com.apple.voice.enhanced.zh-CN.Tingting"
        case .thai:     return "com.apple.voice.enhanced.th-TH.Narisa"
        }
    }
}

enum ImageTapLanguage: String, CaseIterable {
    case thai, english, morsmaal, ingen

    var label: String {
        switch self {
        case .thai:     return "Norwegian"
        case .english:  return "English"
        case .morsmaal: return "Native language"
        case .ingen:    return "No sound"
        }
    }

    var systemImage: String {
        switch self {
        case .thai:     return "speaker.wave.3"
        case .english:  return "speaker.wave.3"
        case .morsmaal: return "speaker.wave.3"
        case .ingen:    return "speaker.slash"
        }
    }
}

struct ThaiGridItem: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var word: ThaiWords
    @Binding var moveToPinnedGroup: Bool
    var frequencyRange: (min: Int, max: Int)? = nil
    // Beregnet av GridView ETTER at gitteret er ferdig lastet (scanForMissingFrequency,
    // egen render-runde via DispatchQueue.main.async) — IKKE beregnet live her per kort,
    // siden det viste seg at en live computed property basert på frequencyRange ikke
    // klarte å tvinge kortet til å tegne om fargen sin ved første visning.
    var isMissingFrequency: Bool = false
    var hideImage: Bool = false
    // Eksakt kolonnebredde beregnet av GridView. Håndheves strengt (fast bredde +
    // clipping), IKKE bare "maxWidth", slik at internt kortinnhold (lang tekst osv.)
    // som ikke ville krympet av seg selv, aldri kan tvinge kortet bredere enn
    // kolonnen GridView faktisk har beregnet plass til.
    var cardWidth: CGFloat? = nil
    @State private var showThai: Bool = false
    @State private var showPhotoVC = false
    @State private var isDropTargeted = false
    @AppStorage("imageTapLanguage") private var imageTapLanguage: ImageTapLanguage = .thai
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @AppStorage("speechRateEnglish") private var speechRateEnglish: Double = 0.5
    @AppStorage("speechRateMorsmaal") private var speechRateMorsmaal: Double = 0.5
    @State private var speechSynth = AVSpeechSynthesizer()

    // 70 % av opprinnelig størrelse (120pt), kun på iPhone — iPad/Mac beholder 120pt.
    private var imageSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 84 : 120
    }

    private var isOutOfFrequencyRange: Bool {
        guard let range = frequencyRange else {
            return false
        }
        let wordRank = word.getFrequencyRank()
        let isWithin = word.isWithinFrequencyRange(min: range.min, max: range.max)
        if showPrint { print("🔍 Ord: \(word.thaiWord ?? "?"), frequencyRank: \(word.frequencyRank), parsedRank: \(word.extractFrequencyRank() ?? -1), range: \(range.min)-\(range.max), innenfor: \(isWithin)") }
        return !isWithin
    }

    // Motsatt sjekk av frekvens-fargingen over: hvis vi IKKE står i en frekvensgruppe
    // (frequencyRange == nil) men ordet likevel har en registrert frekvens, er det et tegn på
    // datakontaminering (setninger/ord som aldri skulle fått frekvens, se undersøkelsen av
    // PublicImportService/ExportToPublicView) — flagg det tydelig visuelt, rødt, for manuell
    // opprydding senere. Rent diagnostisk, skriver ingenting til databasen.
    private var hasUnexpectedFrequency: Bool {
        frequencyRange == nil && word.getFrequencyRank() != nil
    }

    // Midlertidig hjelpemarkering for å finne veldig lange ord ved flytting/opprydding.
    private var isTooLongThaiWord: Bool {
        (word.thaiWord?.count ?? 0) > 25
    }

    private var resolvedCardColor: Color {
        let color: Color
        let reason: String
        if isOutOfFrequencyRange {
            color = Color.pink.opacity(0.3)
            reason = "outOfRange"
        } else if isMissingFrequency {
            color = Color.blue.opacity(0.35)
            reason = "missingFrequency"
        } else if hasUnexpectedFrequency {
            color = Color.red.opacity(0.4)
            reason = "unexpectedFrequency"
        } else {
            color = (word.id == nil ? Color(.white) : Color("CollectionBackground"))
            reason = "default"
        }
        if showPrint { print("🎨 ThaiGridItem.resolvedCardColor: word=\(word.thaiWord ?? "?") objectID=\(word.objectID) isMissingFrequency(param)=\(isMissingFrequency) frequencyRange=\(String(describing: frequencyRange)) => \(reason)") }
        return color
    }

    private var notesTimestamp: String? {
        guard let notes = word.notes else { return nil }
        let t = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group.timestampToSeconds(t) != nil ? t : nil
    }

    /// Samme sjekk som "book"-knappen i DetailWordView bruker (checkHasSentences).
    private var hasExampleSentences: Bool {
        guard let thaiWord = word.thaiWord, !thaiWord.isEmpty else { return false }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "tags CONTAINS %@", thaiWord)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    private var learningStateColor: Color {
        let state = Exercise.learningState(for: word)
        switch state {
        case .new: return .blue
        case .learning: return .orange
        case .reviewing: return .green
        case .relearning: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            if let ts = notesTimestamp {
                HStack {
                    Text("⏱ \(ts)")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            if !hideImage {
                Image(uiImage: word.uiImage)
                    .resizable()
                    .frame(width: imageSize, height: imageSize)
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(learningStateColor, lineWidth: 3))
                    .overlay(alignment: .topTrailing) {
                        if !hasExampleSentences {
                            Button {
                                Notifier.shared.show(.warning, "⚠️ Missing examples")
                            } label: {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .help("Missing example sentences")
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if word.learningState != LearningState.new.rawValue {
                            Button {
                                if let state = LearningState(rawValue: word.learningState) {
                                    Notifier.shared.show(.info, "\(state.displayName) — \(state.meaning)")
                                }
                            } label: {
                                Circle()
                                    .fill(learningStateColor)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .help(LearningState(rawValue: word.learningState).map { "\($0.displayName) — \($0.meaning)" } ?? "Learning state")
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Button {
                            // gPhoto-URL-en åpner direkte på iOS (appen er installert der), som
                            // hopper forbi denne lokale velgeren — i motsetning til Mac Catalyst,
                            // hvor URL-en feiler og faller tilbake til showPhotoVC uansett. Bruk
                            // samme lokale velger på begge for konsistent oppstart.
                            #if targetEnvironment(macCatalyst)
                            GPhotoIntegration.openForPhoto(target: word.objectID, caller: "gNorsk") {
                                showPhotoVC = true
                            }
                            #else
                            showPhotoVC = true
                            #endif
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                                // Synlig sirkel er 32pt, men treffpunktet er fortsatt HIG-minimum
                                // 44×44 — den ekstra usynlige paddingen under gir det, og
                                // .contentShape(Rectangle()) gjør hele 44×44-arealet tappbart,
                                // ikke bare de synlige pikslene.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Øverst til venstre i stedet for nederst til høyre. Kortet er mer
                        // "firkantet" (mindre høyt relativt til avataren) på iPad/Mac enn på
                        // iPhone, så Y-verdien er kalibrert separat per enhetstype (testet fram
                        // i gThai). X er proporsjonal med imageSize.
                        .offset(x: -imageSize * 0.25, y: UIDevice.current.userInterfaceIdiom == .phone ? -28 : -10)
                    }
                    .overlay(isDropTargeted ? Circle().stroke(Color.accentColor, lineWidth: 4) : nil)
                    .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else {
                            return false
                        }
                        provider.loadObject(ofClass: UIImage.self) { reading, _ in
                            guard let droppedImage = reading as? UIImage else { return }
                            DispatchQueue.main.async {
                                word.uiImage = droppedImage
                                try? context.save()
                            }
                        }
                        return true
                    }
                    .padding(.top, 3)
                    .onTapGesture {
                        if showThai || appState.visAlleDetaljer {
                            switch imageTapLanguage {
                            case .thai:
                                Logger.info("[TTS] Bilde trykket (avslørt kort) — Google TTS for '\(word.thaiWord ?? "")'")
                                CloudTTSTest.speakNorsk(word.thaiWord ?? "")
                            case .english:
                                speak(word.englishWord ?? "", language: "en-US", voiceId: "com.apple.voice.enhanced.en-US.Samantha", rate: Float(speechRateEnglish))
                            case .morsmaal:
                                speak(word.translation1 ?? word.englishWord ?? "", language: morsmaalLanguage.locale, voiceId: morsmaalLanguage.voiceId, rate: Float(speechRateMorsmaal))
                            case .ingen:
                                break
                            }
                        } else {
                            showThai = true
                            Logger.info("[TTS] Bilde trykket (første gang) — Google TTS for '\(word.thaiWord ?? "")'")
                            CloudTTSTest.speakNorsk(word.thaiWord ?? "")
                        }
                    }
            }

            if showThai || appState.visAlleDetaljer {
                Text(word.thaiWord ?? "thaiword?")
                    // Norsk trenger ikke samme store skrift som thai (thai er vanskeligere å
                    // lese i liten skrift) — gjelder kun gNorsk, gThai beholder .title.
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundStyle(isTooLongThaiWord ? .red : .black)

                Text(word.translation1 ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.blue)
                    #if targetEnvironment(macCatalyst)
                    .font(.title3)
                    #else
                    .font(.caption)
                    #endif

            }

            Text(word.englishWord ?? "")

                .lineLimit(1)
                .foregroundStyle(.black)
                .padding(6)
            #if(targetEnvironment(macCatalyst))
                .font(.title3)
            #else
                .font(.caption)
            #endif

            if moveToPinnedGroup {
                let tekstGroup = g.getGroupname(groupId: appState.pinnedGruppeId)
                Button("move to \(tekstGroup)") {
                    _ = g.updateGroupIdCoreData(id: word.id?.uuidString ?? "", groupId: appState.pinnedGruppeId)
                    appState.refreshToken = UUID()
                }
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            }
            
            if appState.visAlleDetaljer == false {
                Spacer()

                HStack {
                    let w = word
                    let isNew = w.learningState == LearningState.new.rawValue

                    // DEBUG: Show isNew status
                    Text(isNew ? "NEW" : "STARTED")
                        .font(.system(size: 6))
                        .foregroundColor(isNew ? .blue : .green)
                        .padding(.horizontal, 2)

                    // Show "Start" button for new words
                    if isNew {
                        Button {
                            startLearning(word: w)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                                Text("Start")
                                    .font(.system(size: 8))
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 50, height: 30)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                    } else {
                        // Enhanced confidence buttons - only show for started words
                        Button {
                            Exercise.gradeEnhanced(word: w, confidence: .good); try? w.managedObjectContext?.save()
                        } label: {
                            VStack(spacing: 2) {
                                Text("✅")
                                    .font(.system(size: 16))
                                Text("Correct")
                                    .font(.system(size: 8))
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 45, height: 30)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                    }

                    HStack {

                        Button {
                            showThai = true
                                } label: {
                                    Image(systemName: "eyes")
                                        .font(.system(size: 25))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.blue, .yellow) // hånd, sirkel
                                        .padding(2)
                                }
                                .buttonStyle(.plain)        // <- fjerner systemets grå bakgrunn
                                .contentShape(Circle())     // rundt treff-område
                                .clipShape(Circle())        // klipper bort evt. rest av firkant

                        if !isNew {
                            Button {
                                Exercise.gradeEnhanced(word: w, confidence: .blackout); try? w.managedObjectContext?.save()
                            } label: {
                                VStack(spacing: 2) {
                                    Text("❌")
                                        .font(.system(size: 16))
                                    Text("Wrong")
                                        .font(.system(size: 8))
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 35, height: 30)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(6)
                        }
                        HStack {

                        }
                    }
                }
            }
        }
        .onAppear {
            moveToPinnedGroup = appState.pinnedGruppeId > 0
        }
        .frame(minHeight: moveToPinnedGroup ? 254 : 230)
        .frame(width: cardWidth)
        .frame(maxWidth: cardWidth == nil ? .infinity : nil)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(resolvedCardColor)
                .shadow(radius: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.9), lineWidth: 2.5)
        )
        .sheet(isPresented: $showPhotoVC) {
            PhotoViewControllerWrapper(initialSearchText: word.englishWord ?? "") { image in
                word.uiImage = image
                try? context.save()
                showPhotoVC = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gPhotoResult)) { notification in
            // Notifikasjonen broadcastes til ALLE kort samtidig — bare kortet som faktisk
            // ba om bildet (dvs. er registrert som pendingTargetID) skal reagere.
            guard GPhotoIntegration.pendingTargetID == word.objectID else { return }
            guard let image = notification.userInfo?["image"] as? UIImage else { return }
            word.uiImage = image
            try? context.save()
            GPhotoIntegration.pendingTargetID = nil
        }
    }

    private func speak(_ text: String, language: String, voiceId: String, rate: Float = 0.5) {
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

    private func startLearning(word: ThaiWords) {
        word.learningState = LearningState.learning.rawValue
        word.learningStep = 0
        word.dueAt = Date() // Due now
        word.lastReviewedAt = Date()

        do {
            try word.managedObjectContext?.save()
            if showPrint { print("✅ Startet øving på: \(word.thaiWord ?? "")") }
        } catch {
            print("❌ Kunne ikke starte øving: \(error)")
        }
    }
}

// ✅ Preview fungerer nå
#Preview("ThaiGridItem") {
    @Previewable @State var moveToPinnedGroup = true

    let context = PersistenceController.preview.container.viewContext

    let word = ThaiWords(context: context)
    word.id = UUID()
    word.thaiWord = "สวัสดี"
    word.englishWord = "Hello"
    word.sentence = "สวัสดีครับ"
    word.star = false
    word.insertDate = Date()
    word.dateOne = Date()
    word.dateTwo = Date()
    word.groupId = 10
    word.image = UIImage(systemName: "star.fill")!.jpegData(compressionQuality: 0.8)

    let appState = AppState()
    appState.pinnedGruppeId = 1
    appState.visAlleDetaljer = true

    return ThaiGridItem(word: word, moveToPinnedGroup: $moveToPinnedGroup)
        .environment(appState)
        .environment(\.managedObjectContext, context)
        .padding()
        .background(Color(.systemBackground))
}
