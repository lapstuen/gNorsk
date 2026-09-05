//
//  DetailWordView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/18/25.
//
import SwiftUI
import CoreData
import NaturalLanguage
import Foundation
import Observation   // <- nødvendig for @Observable
import AVFoundation
import UniformTypeIdentifiers
// import gPhotoKit // kommentert ut, se "Edit image"-kommentaren lenger ned

// Bøyningsendelser som prøves fjernet/erstattet når et oppslagsord ikke finnes eksakt i databasen
// (f.eks. "gutten"/"guttene"/"gutter" -> "gutt", "jenta" -> "jente"). Prøves i denne rekkefølgen.
fileprivate let norwegianInflectionRules: [(suffix: String, replacement: String)] = [
    ("ene", ""),   // guttene -> gutt
    ("en", ""),    // gutten -> gutt
    ("et", ""),    // huset -> hus, programmet -> programm (se undoubleFinalM)
    ("er", ""),    // gutter -> gutt
    ("er", "e"),   // liker -> like
    ("te", "e"),   // likte -> like
    ("t", "e"),    // likt -> like
    ("a", "e"),    // jenta -> jente
    ("e", ""),     // pene -> pen (adjektiv i flertall/bestemt form)
]

/// Norske ord kan ikke ende på dobbel M (i motsetning til andre doble konsonanter —
/// f.eks. dobbel T i "gutt" er helt normalt og skal IKKE endres). Når stamme-kandidaten
/// fra `norwegianInflectionRules` ender på "mm" (f.eks. "programmet" -> "programm" etter
/// å ha fjernet "et"), er den formen ugyldig — riktig stamme er enkel M: "program".
/// Returnerer alltid kandidaten selv i tillegg, siden ord som legitimt ender på "mm"
/// midt i en endelsefjerning uansett bør forsøkes som de er.
fileprivate func undoubleFinalM(_ word: String) -> [String] {
    guard word.hasSuffix("mm") else { return [word] }
    return [word, String(word.dropLast())]
}

/// Sterke verb bøyes med uregelmessig stammeendring (f.eks. "drakk"/"drukket" av "drikke") —
/// de følger ingen fast endelse og kan derfor ikke fanges av norwegianInflectionRules. Hver bøyd
/// form (preteritum og perfektum partisipp) mappes direkte til infinitiv i stedet.
let strongVerbForms: [String: String] = [
    "drakk": "drikke", "drukket": "drikke",
    "fant": "finne", "funnet": "finne",
    "skrev": "skrive", "skrevet": "skrive",
    "tok": "ta", "tatt": "ta",
    "så": "se", "sett": "se",
    "gikk": "gå", "gått": "gå",
    "bandt": "binde", "bundet": "binde",
    "bet": "bite", "bitt": "bite",
    "ble": "bli", "blitt": "bli",
    "brøt": "bryte", "brutt": "bryte",
    "bar": "bære", "båret": "bære",
    "datt": "dette", "dettet": "dette",
    "dro": "dra", "dratt": "dra",
    "drev": "drive", "drevet": "drive",
    "falt": "falle",
    "fløy": "fly", "flydd": "fly",
    "frøs": "fryse", "frosset": "fryse",
    "fikk": "få", "fått": "få",
    "grep": "gripe", "grepet": "gripe",
    "gråt": "gråte", "grått": "gråte",
    "holdt": "holde",
    "krøp": "krype", "krøpet": "krype",
    "lot": "la", "latt": "la",
    "lo": "le", "ledd": "le",
    "la": "legge", "lagt": "legge",
    "lå": "ligge", "ligget": "ligge",
    "løy": "lyve", "løyet": "lyve",
    "løp": "løpe", "løpt": "løpe",
    "nøt": "nyte", "nytt": "nyte",
    "rant": "renne", "rent": "renne",
    "red": "ri", "ridd": "ri",
    "rev": "rive", "revet": "rive",
    "røk": "ryke", "røket": "ryke",
    "sa": "si", "sagt": "si",
    "satt": "sitte", "sittet": "sitte",
    "skar": "skjære", "skåret": "skjære",
    "skrek": "skrike", "skreket": "skrike",
    "skjøt": "skyte", "skutt": "skyte",
    "slo": "slå", "slått": "slå",
    "sprang": "springe", "sprunget": "springe",
    "stod": "stå", "stått": "stå",
    "sang": "synge", "sunget": "synge",
    "vant": "vinne", "vunnet": "vinne",
]

/// Enkelte svake verb har så uregelmessig bøying (f.eks. "ha": har/hadde/hatt) at de heller ikke
/// følger de vanlige endelse-reglene i norwegianInflectionRules — samme direkte oppslag som
/// strongVerbForms, bare i en egen tabell siden dette grammatisk er svake, ikke sterke, verb.
let irregularWeakVerbForms: [String: String] = [
    "har": "ha",
    "hadde": "ha",
    "hatt": "ha",
]

/// Alle oppslagskandidater for et token: endelse-fjerning (norwegianInflectionRules, med
/// M-undubling), sterke verb-former og uregelmessige svake verb-former, slått sammen — samme
/// prioriterte kandidatliste brukt av alle oppslagsstedene i denne filen.
fileprivate func inflectionCandidates(for token: String) -> [String] {
    // Minst 2 bokstaver — en 1-bokstavs "kandidat" er aldri et reelt norsk ord og har ved
    // uhell truffet søppel-/testoppføringer i databasen (f.eks. "pene" -> "ene"-regelen ->
    // "p", som feilaktig traff en enkeltbokstav-oppføring i stedet for det riktige "pen").
    var candidates = norwegianInflectionRules.compactMap { rule -> String? in
        guard token.hasSuffix(rule.suffix), token.count > rule.suffix.count else { return nil }
        let candidate = String(token.dropLast(rule.suffix.count)) + rule.replacement
        return candidate.count >= 2 ? candidate : nil
    }.flatMap(undoubleFinalM)
    if let infinitive = strongVerbForms[token.lowercased()] {
        candidates.append(infinitive)
    }
    if let infinitive = irregularWeakVerbForms[token.lowercased()] {
        candidates.append(infinitive)
    }
    return candidates
}

struct WordSelection: Identifiable {
    let id = UUID()
    let word: String
}

// Forenklet quick-view for å se ord fra forslag
// Denne er MYE enklere enn DetailWordView og unngår alle konflikter
struct QuickWordView: View {
    let thaiWord: String
    let context: NSManagedObjectContext
    let onDismiss: () -> Void

    @State private var word: ThaiWords?
    @State private var englishWord: String = ""
    @State private var sentence: String = ""

    var body: some View {
        print("🟠 QUICK VIEW BODY - word: \(thaiWord)")
        return VStack(spacing: 0) {
            // Header med lukke-knapp
            HStack {
                Text("Quick View")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(.systemGray6))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Thai word
                    VStack(alignment: .leading) {
                        Text("Thai")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(thaiWord)
                            .font(.system(size: 40, weight: .bold))
                    }

                    // English
                    if !englishWord.isEmpty {
                        VStack(alignment: .leading) {
                            Text("English")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(englishWord)
                                .font(.title2)
                        }
                    }

                    // Stavelser
                    if !sentence.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Syllablesx")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sentence)
                                .font(.title3)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .task {
            print("🟠 QUICK VIEW TASK (should only run once)")
            let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            request.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
            request.fetchLimit = 1

            if let foundWord = try? context.fetch(request).first {
                word = foundWord
                englishWord = foundWord.englishWord ?? ""
                sentence = foundWord.sentence ?? ""
            }
        }
    }
}
// struct ThaiPartsPanel
struct ThaiPartsPanel: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var vm: ThaiPartsVM
    let sourceText: String
    let onSelectCandidate: (String) -> Void
    // Viktig: vi trenger context i init for å kunne lage VM
    init(sourceText: String, context: NSManagedObjectContext, onSelectCandidate: @escaping (String) -> Void) {
        self.sourceText = sourceText
        _vm = State(initialValue: ThaiPartsVM(context: context))
        self.onSelectCandidate = onSelectCandidate
    }
    // Rekursiv renderer uten ForEach/Binding-krøll
    private func renderRows(_ items: [String], _ i: Int = 0) -> AnyView {
        if i < items.count {
            let cand = items[i]
            let extDef: String? = vm.externalDefs[cand]
            return AnyView(
                VStack(spacing: 0) {
                    ThaiCandidateRow(
                        text: cand,
                        inDB: vm.inDB.contains(cand),
                        englishWord: vm.englishByCandidate[cand],
                        externalDef: extDef,
                        lookedUp: vm.lookedUp,
                        onOpenDetail: onSelectCandidate
                    )
                    Divider()
                    renderRows(items, i + 1)
                }
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Parts from the text").font(.headline)
                Spacer()
                Button {
                    vm.lookupInDatabase(context: context)
                } label: { Label("Look up in DB", systemImage: "internaldrive") }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.candidates.isEmpty || vm.lookedUp)
                Button {
                    vm.lookupExternalForMisses()
                } label: {
                    if vm.isCheckingExternal {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Search externally", systemImage: "globe")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!vm.lookedUp || vm.isCheckingExternal)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                renderRows(vm.candidates)
            }
            if !vm.rejected.isEmpty {
                DisclosureGroup("Forkastede (\(vm.rejected.count))") {
                    renderRows(vm.rejected)
                }
                .padding(.top, 8)
            }
        }
        .onAppear { vm.loadCandidates(from: sourceText) }
        .onChange(of: sourceText) { _, new in
            vm.loadCandidates(from: new)          // iOS 17+ to-parameter onChange
        }
    }
}
/// Enkel cache i minnet så vi ikke spammer nettverket.
fileprivate actor ExternalLexiconCache {
    static let shared = ExternalLexiconCache()
    private var cache: [String: Bool] = [:]
    func get(_ k: String) -> Bool? { cache[k] }
    func set(_ k: String, _ v: Bool) { cache[k] = v }
}
/// Returnerer true hvis termen finnes på th/en Wiktionary.
func externalLexiconExists(term raw: String) async -> Bool {
    let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return false }
    // cache først
    if let cached = await ExternalLexiconCache.shared.get(term) { return cached }
    // Vi sjekker to steder parallelt (Thai/Engelsk Wiktionary)
    func check(_ host: String) async -> Bool {
        let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        // Lettvekts API: side finnes ⇢ pageid > 0
        let urlStr = "https://\(host)/w/api.php?action=query&format=json&titles=\(q)&prop=info&inprop=varianttitles"
        guard let url = URL(string: urlStr) else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let query = obj["query"] as? [String: Any],
               let pages = query["pages"] as? [String: Any] {
                for (key, _) in pages {
                    if let pid = Int(key), pid > 0 { return true }
                }
            }
        } catch { /* ignorer nettfeil */ }
        return false
    }
    let exists: Bool = await withTaskGroup(of: Bool.self) { group in
        group.addTask { await check("th.wiktionary.org") }
        group.addTask { await check("en.wiktionary.org") }
        var anyTrue = false
        for await result in group {
            if result { anyTrue = true }
        }
        return anyTrue
    }
    await ExternalLexiconCache.shared.set(term, exists)
    return exists
}
///
// final class ThaiPartsVM
@Observable
final class ThaiPartsVM {
    var sourceText: String = ""
    let context: NSManagedObjectContext
    var candidates: [String] = []
    var rejected: [String] = []
    var inDB: Set<String> = []
    var englishByCandidate: [String: String] = [:]
    var externalDefs: [String: String] = [:]
    var lookedUp: Bool = false
    var isCheckingExternal: Bool = false
    init(context: NSManagedObjectContext) { self.context = context }
    @MainActor
    func loadCandidates(from text: String) {
        sourceText = text.precomposedStringWithCanonicalMapping
        let all = thaiCandidatesWithDiagnostics(in: sourceText, minLength: 2)
        candidates = all
        rejected = []
        inDB.removeAll()
        englishByCandidate.removeAll()
        externalDefs.removeAll()
        lookedUp = false
        isCheckingExternal = false
    }
    @MainActor private func lookupWord(_ s: String, context ctx: NSManagedObjectContext) -> ThaiWords? {
        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.predicate = NSPredicate(format: "thaiWord == %@", s)
        req.fetchLimit = 1
        return try? ctx.fetch(req).first
    }
    @MainActor
    func lookupInDatabase(context: NSManagedObjectContext? = nil) {
        let ctx = context ?? self.context
        var hits = Set<String>()
        var english: [String: String] = [:]
        for c in candidates where c.count >= 2 {
            guard let word = lookupWord(c, context: ctx) else { continue }
            hits.insert(c)
            let eng = word.englishWord?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let eng, !eng.isEmpty {
                english[c] = eng
            }
        }
        inDB = hits
        englishByCandidate = english
        lookedUp = true
    }
    @MainActor
    func lookupExternalForMisses() {
        guard lookedUp else { return }
        isCheckingExternal = true
        let misses = candidates.filter { $0.count >= 2 && !inDB.contains($0) }
        Task { @MainActor in
            defer { isCheckingExternal = false }
            for term in misses {
                let exists = await externalLexiconExists(term: term)
                if exists { externalDefs[term] = "wiktionary" }
            }
        }
    }
}
struct ThaiCandidatesDiagnostics {
    let plausible: [String]
    let rejected:  [String]
}
func thaiCandidatesWithDiagnostics(in text: String, minLength: Int = 2) -> [String] {
    var keep = Set<String>()
    for word in thaiWordSlices(in: text) {
        let arr = Array(word)
        for i in arr.indices {
            for j in i..<arr.count {
                let s = String(arr[i...j]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard s.count >= minLength else { continue }
                if isPlausibleThaiChunk(Substring(s)) {
                    keep.insert(s)
                }
            }
        }
    }
    return keep.sorted { $0.count > $1.count }
}


struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = max(1.0, lastScale * value)
                                if lastScale < 1.0 { lastScale = 1.0 }
                                scale = lastScale
                            },
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                lastOffset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                    )
                )
                .background(Color.black.opacity(0.98))
                .ignoresSafeArea()
        }
        .background(Color.black)
    }
}
struct DetailWordView: View {
    let initialWord: WordInput
    let isNested: Bool
    var allowVideoNavigation: Bool = false
    @State private var showThaiPartsPanel = false

    @State  var currentWordOID: NSManagedObjectID? = nil
    @State  var originalWordID: UUID? = nil
    @State  var sentenceInput = ""
    @State  var selectedSnippet = ""
    @State  var ipaSnippet = ""
    @State var minH: CGFloat = 40
    @State var maxH: CGFloat = 200

    @State private var showError = false
    @State private var segmentationDebugTokens: [String] = []
    @State private var tokenEnglishMap: [String: String] = [:]
    @State private var tokenRowContainerWidth: CGFloat = 0
    @State private var tokenExistsSet: Set<String> = []
    @State private var activeLookupToken: String? = nil
    @State private var hasSentences: Bool = false
    @State private var safariURL: URL? = nil
    @State private var showSafari = false
    @State private var wordGroupName: String = ""
    @State private var showSelectGroup = false
    @State private var synth = AVSpeechSynthesizer()

    @State private var editableFrequencyRank: String = ""   // <-- NEW STATE VARIABLE
    // Hindrer .onChange(of: wordType) fra å nullstille editableFrequencyRank når wordType settes
    // PROGRAMMATISK i .onAppear (fra den lagrede verdien) — SwiftUI sitt .onChange skiller ikke
    // mellom en programmatisk og en brukerinitiert endring, så uten dette flagget nullstilles
    // frekvensen hver gang et ord med wordType=Sentence bare ÅPNES, ikke bare når brukeren
    // faktisk bytter i velgeren.
    @State private var isInitializingWordType = true

    @Environment(AppState.self)  var appState
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss)  var dismiss
    @Environment(\.openURL)  var openURL
    @State  var wordExists = false
    @State  var resultater: [ThaiWords] = []
    @State  var thaiWord: String = ""
    @State  var englishWord: String = ""
    @State  var ipa: String = ""
    @State  var sentence: String = ""
    @State  var tags: String = ""
    @State  var translation1: String = ""
    @State  var translation2: String = ""
    @State  var notes: String = ""
    @State  var wordType: Int16 = 0
    @State  var selectedImage: UIImage?
    @State  var imageDirty = false
    @State  var isDirty = false
    @State  var showPhotoVC = false
    @State  var isImageDropTargeted = false
    @State  var showAnnotationVC = false
    @State  var isTranslating = false
    @State  var visPhoneticView = false
    @State  var oversettelseFeil: String? = nil
    @State  var kildeIkon: UIImage? = nil
    @State  var visSletteAlert = false
    @State  var didDelete = false
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @State  var didChangeGroup = false
    @State  var selectedWord: String?
    @State  var selectedMeaning: String?
    @State  var selection: TextSelection? = nil
    @State  var showSegmentation = false
    @State private var showSyllableTranslate = false
    @State private var isPresented = false
    @State private var showPronounceChecker = false
    @State private var showSentences = false
    @State private var showingAddSentence = false
    @State private var showMainMenu = false
    @State private var showSyllableAnalysis = false
    @State private var selectedCandidateWord: String? = nil
    @State private var showMarkdownEditor = false
    @State private var showStopLearningAlert = false
    @State private var showFullImage = false
    @State private var groupYoutubeUrl: String? = nil
    @State private var hasRealImage = false
    @State private var siblingWordIDs: [NSManagedObjectID] = []
    @State private var showOrstDict = false
    @State private var showThaiLangDict = false
    @State private var currentSiblingIndex: Int = -1

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

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("(V1)")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(.green)
            Text(wordGroupName.isEmpty ? appState.valgtGruppeNavn : wordGroupName)
                .font(.title3).fontWeight(.semibold)
            Spacer()

          //  Button { showPronounceChecker = true } label: { Label("Utt",  systemImage: "mic.circle.fill") }.buttonStyle(.bordered)
    

            
            Button {
                showSegmentation = true
            } label: {
                Image(systemName: "square.grid.3x1.folder.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.25)) // velg farge
                    .clipShape(Circle())                   // gjør hele knappen rund
            }
            .buttonStyle(.plain)

            // Uttale-knapp
            Button {

                showPronounceChecker = true

            } label: {

                Image(systemName: "mic.circle.fill")

                    .resizable()

                    .scaledToFit()

                    .frame(width: 44, height: 44)

                    .foregroundStyle(.white)

            }

            .buttonStyle(.borderless)

            // Meny-knapp
            Menu {

                mainMenuContent

            } label: {

                Image(systemName: "list.bullet.circle.fill")

                    .font(.system(size: 44))

                    .foregroundStyle(.white)

            }

            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
         .padding(.top, 30)
         .padding(.bottom, 10)
       
        .background(headerGradient)
    }

    @ViewBuilder
    private var mainMenuContent: some View {
        // Fra contentView (HStack med + og bok-knappene)
      //  if let word = fetchWord() {
      //      Button {
      //          showingAddSentence = true
      //      } label: {
      //          Label("Legg til setning", systemImage: "plus")
      //      }
//
      //      Button {
      //          showSentences = true
      //      } label: {
      //          Label("Vis setninger", systemImage: "book")
      //      }
      //  }
//
      //  Divider()

        // Learning state
        if let word = fetchWord() {
            let isNew = word.learningState == LearningState.new.rawValue

            if isNew {
                Button {
                    startLearningWord(word)
                } label: {
                    Label("Start practicing", systemImage: "brain.head.profile")
                }
            } else {
                Button {
                    showStopLearningAlert = true
                } label: {
                    Label("Stop practicing", systemImage: "stop.circle")
                }
            }
        }

        Divider()

        // Fra headerView
        Button {
            showPhotoVC = true
        } label: {
            Label("Choose image", systemImage: "photo.on.rectangle")
        }

        Button {
            #if os(iOS)
            GPhotoIntegration.openForPhoto(caller: "gNorsk") {
                showPhotoVC = true
            }
            #endif
        } label: {
            Label("Hent fra gPhoto", systemImage: "sparkles")
        }

        if let img = selectedImage {
            Button {
                #if os(iOS)
                GPhotoIntegration.openForEdit(image: img, caller: "gNorsk") {
                    Notifier.shared.show(.warning, "gPhoto not available")
                }
                #endif
            } label: {
                Label("Edit image", systemImage: "pencil.tip.crop.circle")
            }
        }

        // Krever gPhotoKit — kommentert ut, bruk "Hent fra gPhoto" (redigering skjer i gPhoto før bildet sendes tilbake)
        // if selectedImage != nil {
        //     Button {
        //         showAnnotationVC = true
        //     } label: {
        //         Label("Edit image", systemImage: "pencil.tip.crop.circle")
        //     }
        // }

     //   Button {
     //       showSegmentation = true
     //   } label: {
     //       Label("Segmentering", systemImage: "square.grid.3x1.folder.badge.plus")
     //   }

      //  Divider()

        Menu {
            Button {
                g.talkTh(talkText: thaiWord, rate: 0.5, language: "nb-NO")
            } label: {
                Label("Narisa (TTS)", systemImage: "speaker.wave.2.fill")
            }
            Button {
                let utter = AVSpeechUtterance(string: thaiWord)
                utter.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.nb-NO.Nora") ?? AVSpeechSynthesisVoice(language: "nb-NO")
                let kanyaRate = UserDefaults.standard.double(forKey: "speechRateThai")
                utter.rate = kanyaRate > 0 ? Float(kanyaRate) : 0.5
                if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
                synth.speak(utter)
            } label: {
                Label("Kanya (TTS)", systemImage: "waveform")
            }
            Divider()
            Button {
                showPronounceChecker = true
            } label: {
                Label("Uttalesjekk", systemImage: "mic.circle.fill")
            }
        } label: {
            Label("Uttale", systemImage: "speaker.wave.2")
        }

        Menu {
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Thai2English", systemImage: "globe.asia.australia")
            }
            Button {
                showThaiLangDict = true
            } label: {
                Label("thai-language.com", systemImage: "character.book.closed")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://dict.longdo.com/?search=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Longdo Dict", systemImage: "book.pages")
            }
            Button {
                showOrstDict = true
            } label: {
                Label("Royal Society Dictionary", systemImage: "text.book.closed")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://forvo.com/search/\(encoded)/no/") {
                    openURL(url)
                }
            } label: {
                Label("Forvo", systemImage: "person.wave.2")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://papago.naver.com/?sk=no&tk=th&st=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Papago", systemImage: "p.circle.fill")
            }
            Button {
                openGoogleTranslate(thaiWord, targetLang: "th", using: openURL)
            } label: {
                Label("Google Translate", systemImage: "g.circle.fill")
            }
        } label: {
            Label("Referanser", systemImage: "books.vertical")
        }

        Button {
            translate()
        } label: {
            if isTranslating {
                Label("Oversetter...", systemImage: "arrow.triangle.2.circlepath")
            } else {
                Label("Oversett", systemImage: "arrow.left.arrow.right")
            }
        }
        .disabled(isTranslating)

        Divider()

        // Endre gruppe (Normal/Vente/OK)
        if let word = fetchWord() {
            Menu {
                changeGroupMenuContent(for: word)
            } label: {
                Label("Change group type", systemImage: "folder.badge.gearshape")
            }
        }

        Button {
            showSelectGroup = true
        } label: {
            Label("Change group", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            visSletteAlert = true
        } label: {
            Label("Delete word", systemImage: "trash")
        }
    }




    private func speakText(_ text: String, language: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let utter = AVSpeechUtterance(string: t)
        utter.voice = AVSpeechSynthesisVoice(language: language)
        let rateKey = language == "en-US" ? "speechRateEnglish" : "speechRateMorsmaal"
        let storedRate = UserDefaults.standard.double(forKey: rateKey)
        utter.rate = storedRate > 0 ? Float(storedRate) : 0.5
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(utter)
    }

    private func groupExists(_ groupId: Int16) -> Bool {
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        return (try? context.fetch(req).first) != nil
    }

    @ViewBuilder
    private func changeGroupMenuContent(for word: ThaiWords) -> some View {
        let currentGroupId = Int16(word.groupId)
        let baseGroupId = Int16((currentGroupId / 3) * 3)
        let groupType = Int16(currentGroupId % 3)

        let normalGroupId = baseGroupId
        let venteGroupId = Int16(baseGroupId + 1)
        let okGroupId = Int16(baseGroupId + 2)

        Button {
            changeWordGroup(word: word, to: normalGroupId)
        } label: {
            HStack {
                Text("Normal group (ID: \(normalGroupId))")
                if groupType == 0 { Image(systemName: "checkmark") }
            }
        }
        .disabled(groupType == 0)

        if groupExists(venteGroupId) {
            Button {
                changeWordGroup(word: word, to: venteGroupId)
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
                changeWordGroup(word: word, to: okGroupId)
            } label: {
                HStack {
                    Text("OK group (ID: \(okGroupId))")
                    if groupType == 2 { Image(systemName: "checkmark") }
                }
            }
            .disabled(groupType == 2)
        }
    }

    private func convertBracketedSyllablesToJSON(_ text: String) -> String? {
          // Accepts inputs like: [ขอ][ความ][ช่ว][ย][เหลือ][หน่อย]
          // Returns JSON array string like: ["ขอ","ความ","ช่ว","ย","เหลือ","หน่อย"]
          let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
          guard trimmed.contains("[") && trimmed.contains("]") else { return nil }
          // Regex to capture content inside brackets
          let pattern = #"\[([^\]]+)\]"#
          guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
          let ns = trimmed as NSString
          let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
          var parts: [String] = []
          for m in matches where m.numberOfRanges >= 2 {
              let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
              if !s.isEmpty { parts.append(s) }
          }
          guard !parts.isEmpty else { return nil }
          // Build JSON array string
          let escaped = parts.map { "\"\($0)\"" }.joined(separator: ",")
          return "[" + escaped + "]"
      }
    
    
    private func changeWordGroup(word: ThaiWords, to newGroupId: Int16) {
        let oldGroupId = word.groupId
        word.groupId = newGroupId

        do {
            try context.save()
            // Mark that group was changed to prevent overwriting in onDisappear
            didChangeGroup = true
            // Refresh context to ensure changes are visible
            context.refreshAllObjects()
            let groupTypeName = getGroupTypeName(for: newGroupId)
            Notifier.shared.show(.success, "Moved to \(groupTypeName) (ID: \(newGroupId))")
            // Trigger GridView refresh
            appState.refreshToken = UUID()
            // Close the detail view after moving to different group
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            word.groupId = oldGroupId // Revert on error
            Notifier.shared.show(.error, "Could not change group: \(error.localizedDescription)")
        }
    }

    private func getGroupTypeName(for groupId: Int16) -> String {
        switch groupId % 3 {
        case 0: return "Normal group"
        case 1: return "Waiting group"
        case 2: return "OK group"
        default: return "Unknown group"
        }
    }

    @ViewBuilder
    private func contentView(_ w: ThaiWords?) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                // Centered image with buttons on each side
                HStack(spacing: 12) {
                    // Forrige-knapp (kun YouTube-grupper med aktiv navigasjon)
                    if allowVideoNavigation && wordGroupName.hasPrefix("▶️") && currentSiblingIndex > 0 {
                        Button {
                            let prevID = siblingWordIDs[currentSiblingIndex - 1]
                            if let prev = try? context.existingObject(with: prevID) as? ThaiWords {
                                navigateToWord(prev)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 26, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }

                    VStack(spacing: 8) {
                        Button {
                            if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                               let url = URL(string: "https://ordbokene.no/nob/bm/\(encoded)") {
                                openURL(url)
                            }
                        } label: {
                            Image(systemName: "globe.asia.australia")
                                .font(.body)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            showThaiLangDict = true
                        } label: {
                            Image(systemName: "character.book.closed")
                                .font(.body)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let encoded = translation1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                               let url = URL(string: "https://forvo.com/search/\(encoded)/th/") {
                                openURL(url)
                            }
                        } label: {
                            Image(systemName: "person.wave.2")
                                .font(.body)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    ZStack {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray5))
                                .frame(width: 200, height: 200)
                                .overlay {
                                    Image(systemName: "photo.fill")
                                        .resizable().scaledToFit()
                                        .frame(width: 50)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isImageDropTargeted ? Color.accentColor : Color.blue.opacity(0.6), lineWidth: isImageDropTargeted ? 6 : 4)
                            .frame(width: 208, height: 208)
                            .allowsHitTesting(false)
                    }
                    .frame(width: 208, height: 208)
                    .contentShape(Rectangle())
                    .onTapGesture { showFullImage = true }
                    .onLongPressGesture(minimumDuration: 0.4) { showPhotoVC = true }
                    .onDrop(of: [.image], isTargeted: $isImageDropTargeted) { providers in
                        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else {
                            return false
                        }
                        provider.loadObject(ofClass: UIImage.self) { reading, _ in
                            guard let droppedImage = reading as? UIImage else { return }
                            DispatchQueue.main.async {
                                selectedImage = droppedImage
                                imageDirty = true
                            }
                        }
                        return true
                    }
                    // Neste-knapp (kun YouTube-grupper med aktiv navigasjon)
                    let activeVideoNav = allowVideoNavigation && wordGroupName.hasPrefix("▶️")
                    if activeVideoNav && currentSiblingIndex >= 0 && currentSiblingIndex < siblingWordIDs.count - 1 {
                        Button {
                            let nextID = siblingWordIDs[currentSiblingIndex + 1]
                            if let next = try? context.existingObject(with: nextID) as? ThaiWords {
                                navigateToWord(next)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 26, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    } else if !activeVideoNav, let word = w {
                        // Book/legg-til-setning-knapp når vi IKKE er i video-navigasjon
                        if hasSentences {
                            Button { showSentences = true } label: {
                                Image(systemName: "book")
                                    .font(.title2)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                           // .fullScreenCover(item: <#T##Binding<Identifiable?>#>, content: <#T##(Identifiable) -> View#>)
                            .fullScreenCover(isPresented: $showSentences) {
                                SentenceListView(tag: word.thaiWord ?? "")
                            }
                        } else {
                            Button { showingAddSentence = true } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .fullScreenCover(isPresented: $showingAddSentence, onDismiss: checkHasSentences) {
                                CreateWordView(linkedWord: word)
                                    .environment(appState)
                                    .environment(\.managedObjectContext, context)
                            }
                        }
                    } else {
                        // Video-nav aktiv men vi er på siste kort — placeholder for balanse
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .alert("The clipboard must contain only Thai characters.", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                }

                // Uttale-knapper - flere kilder for sammenligning
              //  TTSButtonRow(text: thaiWord, openURL: openURL)

                // Midlertidig fjernet igjen (utestet, kan ha kollidert med
                // segmentationDebugTokens-raden rett under) — se samtale 2026-07-30.
                // if !thaiWord.isEmpty {
                //     ThaiPartsPanel(
                //         sourceText: thaiWord,
                //         context: context,
                //         onSelectCandidate: { candidateText in
                //             let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                //             req.predicate = NSPredicate(format: "thaiWord == %@", candidateText)
                //             req.fetchLimit = 1
                //             if let match = try? context.fetch(req).first {
                //                 navigateToWord(match)
                //             } else {
                //                 Notifier.shared.show(.info, "'\(candidateText)' not found in database")
                //             }
                //         }
                //     )
                //     .padding(.horizontal)
                // }

                // Insert Orddeling (debug) tokens view here, BEFORE Englishx bare hvis flere enn 1
                if segmentationDebugTokens.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                   // Text("Orddeling (debug):")
                   //     .font(.caption)
                   //     .foregroundStyle(.secondary)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(segmentationDebugTokens.indices, id: \.self) { i in
                                    let token = segmentationDebugTokens[i]
                                    TokenButton(
                                        token: token,
                                        englishWord: tokenEnglishMap[token],
                                        existsInDB: tokenExistsSet.contains(token),
                                        isActive: activeLookupToken == token.precomposedStringWithCompatibilityMapping,
                                        onSelect: { activeLookupToken = token.precomposedStringWithCompatibilityMapping },
                                        onOpenDetail: {
                                            if fetchExistingWord(thaiWord: token) != nil {
                                                selectedCandidateWord = token
                                            }
                                            // Aldri auto-opprett ved å trykke på token
                                        },
                                        onCreateWord: tokenExistsSet.contains(token) ? nil : {
                                            createWordInCompanionGroup(thai: token)
                                        }
                                    )
                                    .id(token)
                                }
                            }.padding(.horizontal, 8)
                             .padding(.vertical, 8)
                             .frame(minWidth: tokenRowContainerWidth, alignment: .center)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { tokenRowContainerWidth = geo.size.width }
                                    .onChange(of: geo.size.width) { _, newWidth in
                                        tokenRowContainerWidth = newWidth
                                    }
                            }
                        )
                        .onChange(of: activeLookupToken) { _, newToken in
                            if let t = newToken {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(t, anchor: .center)
                                }
                            }
                        }
                    }
                }
                }




                VStack(alignment: .leading, spacing: 6) {

                    HStack {
                        Text("Norwegian").font(.caption.bold())
                        Spacer()
                        Button { showThaiPartsPanel.toggle() } label: {
                            Image(systemName: "square.split.2x1")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(thaiWord.isEmpty)
                        .help("Show word parts")
                        Button { CloudTTSTest.speakNorsk(thaiWord) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.largeTitle)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(thaiWord.isEmpty)
                    }
                    if showThaiPartsPanel && !thaiWord.isEmpty {
                        ThaiPartsPanel(
                            sourceText: thaiWord,
                            context: context,
                            onSelectCandidate: { candidateText in
                                let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                                req.predicate = NSPredicate(format: "thaiWord ==[c] %@", candidateText)
                                req.fetchLimit = 1
                                if let match = try? context.fetch(req).first {
                                    navigateToWord(match)
                                } else {
                                    Notifier.shared.show(.info, "'\(candidateText)' not found in database")
                                }
                            }
                        )
                        .padding(.vertical, 4)
                    }
                    if isNested {
                        TextEditor(text: $thaiWord)
                            .font(.system(size: 28))
                            .frame(minHeight: minH, maxHeight: maxH)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                            .textInputAutocapitalization(.never)
                    } else {
                        ThaiSuggestionEditor(
                            text: $thaiWord,
                            minH: $minH,
                            maxH: $maxH,
                            onSelectWord: { word in
                                print("🟣 SUGGESTION SELECTED: \(word)")
                                if fetchExistingWord(thaiWord: word) != nil {
                                    selectedCandidateWord = word
                                }
                                // Aldri auto-opprett ved å velge forslag
                            },
                            onSuggestionChanged: { activeLookupToken = $0 }
                        )
                    }
                }



                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Englishx").font(.caption.bold())
                        Spacer()
                        Button { speakText(englishWord, language: "en-US") } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.largeTitle)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(englishWord.isEmpty)
                    }
                    ZStack(alignment: .topLeading) {
                        Text(englishWord.isEmpty ? " " : englishWord)
                            .font(.system(size: 22))
                            .foregroundColor(.clear)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                        TextEditor(text: $englishWord)
                            .font(.system(size: 22))
                            .textInputAutocapitalization(.never)
                    }
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                HStack(spacing: 8) {
                    Text("Type").font(.caption.bold())
                    Picker("", selection: $wordType) {
                        Text("Word").tag(Int16(0))
                        Text("Sentence").tag(Int16(1))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .onChange(of: wordType) { _, newValue in
                        // Setninger skal aldri ha en frekvensrang i kjerne-ord-listen (1–4000) —
                        // 0 = "ikke satt", slik at ingen positive verdier blokkeres for spesialtilfeller av ord.
                        // isInitializingWordType hindrer dette fra å trigge når wordType bare
                        // settes fra den lagrede verdien i .onAppear (en programmatisk endring),
                        // i stedet for et faktisk brukerbytte i velgeren.
                        guard !isInitializingWordType else { return }
                        if newValue == 1 {
                            editableFrequencyRank = ""
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(morsmaalLanguage.label).font(.caption.bold())
                        Spacer()
                        Button { speakText(translation1, language: morsmaalLanguage.locale) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.largeTitle)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(translation1.isEmpty)
                    }
                    ZStack(alignment: .topLeading) {
                        Text(translation1.isEmpty ? " " : translation1)
                            .font(.system(size: 32))
                            .foregroundColor(.clear)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                        TextEditor(text: $translation1)
                            .font(.system(size: 32))
                    }
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notes (Markdown)").font(.caption.bold())
                        Spacer()
                        Button {
                            showMarkdownEditor = true
                        } label: {
                            Label("", systemImage: "square.and.pencil")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Klikkbar preview av notater
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                        if notes.isEmpty {
                            Text("Tap to add notes...")
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            let mdReady = notes
                                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                .replacingOccurrences(of: "\\s+(\\*{1,2})", with: "$1", options: .regularExpression)
                            Text((try? AttributedString(markdown: mdReady, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(notes))
                                .font(.system(size: 16))
                                .lineLimit(4)
                                .padding(12)
                        }
                    }
                    .frame(minHeight: 80, maxHeight: 120)
                    .onTapGesture {
                        showMarkdownEditor = true
                    }

                    // YouTube-knapp hvis gruppen har URL og notes har tidsstempel
                    if let url = groupYoutubeUrl, !url.isEmpty, !notes.isEmpty {
                        Button {
                            let secs = Group.timestampToSeconds(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                            openYouTube(baseUrl: url, seconds: secs)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.red)
                                Text("Start video ved \(notes.trimmingCharacters(in: .whitespacesAndNewlines))")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }


                }







                
                
                
                

                

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Syllables").font(.caption.bold())
                        Spacer()
                        Button {
                            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty && !thaiWord.isEmpty {
                                if generateSyllablesIfNeeded() {
                                    Notifier.shared.show(.success, "Generated syllables from Thai word")
                                } else {
                                    Notifier.shared.show(.error, "Could not generate syllables from Thai word")
                                }
                            } else if let data = trimmed.data(using: .utf8),
                                      let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
                                      !arr.isEmpty {
                                // Already valid JSON — do nothing
                            } else if let converted = convertBracketedSyllablesToJSON(trimmed) {
                                sentence = converted
                                if let word = fetchWord() {
                                    word.sentence = converted
                                    try? context.save()
                                }
                                Notifier.shared.show(.success, "Converted to JSON format")
                            } else {
                                Notifier.shared.show(.error, "No valid bracket format found to convert")
                            }
                        } label: {
                            Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    
                    
                    

                    HStack {
                        TextEditor(text: $sentence)
                            .frame(minHeight: 40, maxHeight: 120)
                            .font(.system(size: 30))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }


                }
                
                // Tone-annotert visning av stavelser
                if !sentence.isEmpty {
                    let currentWord = currentWordOID.flatMap { try? context.existingObject(with: $0) as? ThaiWords }
                    ToneAnnotatedSentenceView(
                        text: sentence,
                        fontSize: 44,
                        showInfoButtons: true,
                        word: currentWord
                    )
                    // Inline per-syllable buttons (one syllable = one info button)
                //    InlineSyllableInfoRow(rawSentence: sentence, fontSize: 22, word: currentWord)
                        .padding(.top, 6)

                    CombinedWordIPAView(sentence: sentence, word: currentWord, fontSize: 28)
                }

                

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags").font(.caption.bold())
                    TextEditor(text: $tags)
                        .frame(minHeight: 40, maxHeight: 40)
                        .font(.system(size: 20))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
                
            //    VStack(alignment: .leading, spacing: 6) {
            //        Text("IPA").font(.caption.bold())
            //        TextEditor(text: $ipa)
            //            .frame(minHeight: 40, maxHeight: 60)
            //            .font(.system(size: 20))
            //            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            //    }


                // NEW EDITABLE FREQUENCY RANK INPUT
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frequency rank (editable)").font(.caption.bold())
                    TextField("f.eks. 123", text: $editableFrequencyRank)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .submitLabel(.done)
                        .onSubmit {
                            if let w = w {
                                applyFrequencyRankEdit(to: w)
                            }
                        }
                }
                .gridCellColumns(2)
            }
            .padding(.horizontal)

            if let word = w {
                additionalFieldsSection(word: word)
            }
        }
        .background(Color.gray.opacity(0.05))
    }

  //  @ViewBuilder
  //  private var bottomBar: some View {
  //      HStack(spacing: 12) {
  //          Button { showPronounceChecker = true } label: { Label("Utt",  systemImage: "mic.circle.fill") }
  //              .buttonStyle(.bordered)
  //          Spacer()
  //          Button { showSegmentation = true } label: { Label("", systemImage: "square.grid.3x1.folder.badge.plus") }
  //              .buttonStyle(.bordered)
  //          Spacer()
  //      }
  //  }
//
    @ViewBuilder
    private func additionalFieldsSection(word: ThaiWords) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 8)

            Text("Additional information")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], alignment: .leading, spacing: 8) {
                InfoFieldView(label: "ID", value: word.id?.uuidString ?? "None")
                InfoFieldView(label: "Group ID", value: groupDisplayValue(for: word.groupId))

                Button {
                    toggleStar(for: word)
                } label: {
                    Image(systemName: word.star ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundColor(word.star ? .yellow : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                InfoFieldView(label: "Language", value: word.language ?? "Not set")
                InfoFieldView(label: "Created", value: formatDate(word.insertDate))
                InfoFieldView(label: "Date 1", value: formatDate(word.dateOne))
                InfoFieldView(label: "Date 2", value: formatDate(word.dateTwo))
                InfoFieldView(label: "Frequency rank", value: word.frequencyRank > 0 ? String(word.frequencyRank) : "Not set")
                InfoFieldView(label: "IPA", value: word.ipa ?? "Not set")
                InfoFieldView(label: "Translation 1", value: word.translation1 ?? "Not set")
            }

            // Læringsfelter
            VStack(alignment: .leading, spacing: 8) {
                Text("Learning")
                    .font(.caption.bold())
                    .foregroundColor(.green)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], alignment: .leading, spacing: 8) {
                    InfoFieldView(label: "Last reviewed", value: formatDate(word.lastReviewedAt))
                    InfoFieldView(label: "Due", value: formatDate(word.dueAt))
                    InfoFieldView(label: "Difficulty", value: word.easiness > 0 ? String(format: "%.2f", word.easiness) : "Not set")
                    InfoFieldView(label: "Repetitions", value: String(word.repetitions))
                    InfoFieldView(label: "Lapses", value: String(word.lapses))
                    InfoFieldView(label: "Last result", value: String(word.lastResult))
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Ikke satt" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func applyFrequencyRankEdit(to word: ThaiWords) {
        let trimmed = editableFrequencyRank.trimmingCharacters(in: .whitespacesAndNewlines)
        let newRank: Int32
        if trimmed.isEmpty {
            newRank = 0
        } else if let val = Int32(trimmed), val >= 0 {
            newRank = val
        } else {
            Notifier.shared.show(.error, "Ugyldig frekvensrang: \(editableFrequencyRank)")
            return
        }
        guard newRank != word.frequencyRank else { return }
        word.frequencyRank = newRank
        do {
            try context.save()
            // Uten dette blir ikke kort-fargen i gitteret gjenoppfrisket etter denne redigeringen —
            // GridView sin scanForMissingFrequency() kjører kun på nytt når refreshToken endres.
            appState.refreshToken = UUID()
            Notifier.shared.show(.success, "Frequency rank updated")
        } catch {
            Notifier.shared.show(.error, "Could not save frequency rank: \(error.localizedDescription)")
        }
    }

    private func refreshSegmentationDebug() {
        let (hits, debugTokens) = HybridSegmentationPipeline.run(
            text: thaiWord,
            context: context,
            ignorePrecomputedSyllables: false,
            useAppleNLWordPreprocess: false
        )
        segmentationDebugTokens = debugTokens
        // Store/små bokstaver er irrelevant for oppslaget ("jenta" skal finne "Jente") -> sammenlign case-insensitivt ([c]).
        // NB: "IN[c]" er upålitelig i Core Data/SQLite (samme kjente modifier-bug som CONTAINS[cd] —
        // se GLFunctions.swift-søkene) — bygg i stedet en OR av eksakte ==[c]-sammenligninger.
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
            debugTokens.map { NSPredicate(format: "thaiWord ==[c] %@", $0) })
        if let results = try? context.fetch(req) {
            var map: [String: String] = [:]
            var exists: Set<String> = []

            var lowercasedDbWords: Set<String> = []
            var englishByLowercasedThai: [String: String] = [:]
            for word in results {
                if let thai = word.thaiWord {
                    let lower = thai.lowercased()
                    lowercasedDbWords.insert(lower)
                    if let eng = word.englishWord, !eng.isEmpty {
                        englishByLowercasedThai[lower] = eng
                    }
                }
            }
            for token in debugTokens {
                let lowerToken = token.lowercased()
                if lowercasedDbWords.contains(lowerToken) {
                    exists.insert(token)
                    if let eng = englishByLowercasedThai[lowerToken] {
                        map[token] = eng
                    }
                }
            }

            // Fallback: prøv norske bøyningskandidater (flere pr. token, prøves i regelrekkefølge) for tokens uten treff
            let missing = debugTokens.filter { !exists.contains($0) }
            var candidatesByToken: [String: [String]] = [:] // original token -> kandidater i prioritert rekkefølge
            for token in missing {
                let candidates = inflectionCandidates(for: token)
                if !candidates.isEmpty {
                    candidatesByToken[token] = candidates
                }
            }
            if !candidatesByToken.isEmpty {
                let allCandidates = Array(Set(candidatesByToken.values.flatMap { $0 }))
                let req2 = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
                req2.predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
                    allCandidates.map { NSPredicate(format: "thaiWord ==[c] %@", $0) })
                if let results2 = try? context.fetch(req2) {
                    var foundLowercasedCandidates: Set<String> = []
                    var englishByLowercasedCandidate: [String: String] = [:]
                    for word in results2 {
                        if let thai = word.thaiWord {
                            let lower = thai.lowercased()
                            foundLowercasedCandidates.insert(lower)
                            if let eng = word.englishWord, !eng.isEmpty {
                                englishByLowercasedCandidate[lower] = eng
                            }
                        }
                    }
                    for (token, candidates) in candidatesByToken {
                        if let matched = candidates.first(where: { foundLowercasedCandidates.contains($0.lowercased()) }) {
                            exists.insert(token)
                            if let eng = englishByLowercasedCandidate[matched.lowercased()] {
                                map[token] = eng
                            }
                        }
                    }
                }
            }

            // Siste fallback: prøv gThai sitt CloudKit-speil (read-only, se GThaiReferenceStore) for
            // tokens som fortsatt ikke finnes i gNorsk sin egen database. Fyller kun englishWord for
            // visning i brikken — "Create word" er fortsatt tilgjengelig og oppretter ordet lokalt i gNorsk.
            let stillMissing = debugTokens.filter { !exists.contains($0) }
            if !stillMissing.isEmpty {
                var gthaiCandidatesByToken: [String: [String]] = [:]
                for token in stillMissing {
                    let candidates = [token] + inflectionCandidates(for: token)
                    gthaiCandidatesByToken[token] = candidates
                }
                let allGthaiCandidates = Array(Set(gthaiCandidatesByToken.values.flatMap { $0 }))
                let gthaiReq = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
                // I gThai sin egen database er det translation1 (morsmål/norsk) som inneholder norsk
                // tekst — thaiWord der er ekte thaiskrift. gNorsk har snudd rollene til de samme
                // kolonnenavnene, så vi må søke translation1 her, ikke thaiWord.
                gthaiReq.predicate = NSPredicate(format: "translation1 IN[c] %@", allGthaiCandidates)
                if let gthaiResults = try? GThaiReferenceStore.shared.context.fetch(gthaiReq) {
                    // "Finnes"-sjekken skal IKKE avhenge av om treffet tilfeldigvis har et utfylt
                    // engelsk ord — mange gThai-oppføringer mangler englishWord. foundLowercasedGthaiCandidates
                    // sporer alle reelle treff (kun basert på translation1), uavhengig av englishWord.
                    var foundLowercasedGthaiCandidates: Set<String> = []
                    var englishByLowercasedGthaiCandidate: [String: String] = [:]
                    for word in gthaiResults {
                        if let norsk = word.translation1 {
                            let lower = norsk.lowercased()
                            foundLowercasedGthaiCandidates.insert(lower)
                            if let eng = word.englishWord, !eng.isEmpty {
                                englishByLowercasedGthaiCandidate[lower] = eng
                            }
                        }
                    }
                    for (token, candidates) in gthaiCandidatesByToken {
                        if let matched = candidates.first(where: { foundLowercasedGthaiCandidates.contains($0.lowercased()) }) {
                            // Et treff her betyr at ordet (etter fjernet endelse) finnes i gThai sitt
                            // referanseoppslag — brikken skal da ikke vises som "ikke i databasen", selv
                            // om det ennå ikke er importert som eget ord lokalt i gNorsk.
                            exists.insert(token)
                            if let eng = englishByLowercasedGthaiCandidate[matched.lowercased()] {
                                map[token] = eng
                            }
                        }
                    }
                }
            }

            tokenEnglishMap = map
            tokenExistsSet = exists
        }
    }

    private func checkHasSentences() {
        guard !thaiWord.isEmpty else { hasSentences = false; return }
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "tags CONTAINS %@", thaiWord)
        req.fetchLimit = 1
        hasSentences = ((try? context.count(for: req)) ?? 0) > 0
    }

    var body: some View {
        let w = fetchWord()
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                contentView(w)
                    .padding(.bottom, 120)  // Ekstra padding nederst for å kunne scrolle over bottomBar
            }.scrollDismissesKeyboard(.immediately)   // eller .immediately
        }
        .safeAreaInset(edge: .top) {
            headerView
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .scrollIndicators(.visible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showPronounceChecker) { ThaiPronounceCheckView(target: thaiWord) }
        .sheet(isPresented: $showSyllableAnalysis) {
            ThaiSyllableAnalysisView(thaiWord: thaiWord)
        }
        
        .sheet(isPresented: $showFullImage) {
            if let img = selectedImage {
                ZoomableImageView(image: img)
                    .ignoresSafeArea()
            }
        }
        
        // fullScreenCover (ikke sheet): en sheet presentert INNENFRA en allerede-åpen sheet blir
        // på iPad ofte tvunget til en liten, kompakt visning av selve OS-et, uansett hvilke
        // presentationDetents/frame-modifikatorer vi setter — fullScreenCover unngår denne
        // "nøstet sheet"-begrensningen.
        .fullScreenCover(item: Binding(
            get: {
                if let word = selectedCandidateWord {
                    print("🟢 SHEET GET: \(word)")
                    // Hent eller opprett WordInput for dette ordet
                    if let existingWord = fetchExistingWord(thaiWord: word) {
                        return WordInput(from: existingWord)
                    } else {
                        // Opprett dummy WordInput hvis ordet ikke finnes
                        return WordInput(
                            objectID: nil,
                            thaiWord: word,
                            englishWord: "",
                            sentence: "",
                            tags: "",
                            image: nil,
                            uuid: UUID(),
                            translation1: "",
                            translation2: ""
                        )
                    }
                }
                print("🔴 SHEET GET: nil")
                return nil
            },
            set: { newValue, _ in
                print("🟡 SHEET SET: \(newValue?.thaiWord ?? "nil")")
                if newValue == nil {
                    selectedCandidateWord = nil
                }
            }
        )) { (wordInput: WordInput) in
            DetailWordView2(initialWord: wordInput, isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #else
                .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 900 : nil,
                       minHeight: UIDevice.current.userInterfaceIdiom == .pad ? UIScreen.main.bounds.height * 0.9 : nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
                // fullScreenCover kan ikke sveipes vekk (i motsetning til sheet) — trenger derfor
                // en egen lukk-knapp. Setter selectedCandidateWord = nil direkte (samme som
                // Binding sin set-closure over gjør) i stedet for @Environment(\.dismiss), for å
                // unngå tvetydighet om hvilken presentasjon dismiss() faktisk peker på her.
                .overlay(alignment: .topLeading) {
                    Button {
                        selectedCandidateWord = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white, Color.black.opacity(0.4))
                    }
                    .padding()
                }
        }
.alert("Do you want to delete this word?", isPresented: $visSletteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { slettOrd() }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Stop practicing this word?", isPresented: $showStopLearningAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Stop", role: .destructive) {
                if let word = fetchWord() {
                    stopLearningWord(word)
                }
            }
        } message: {
            Text("The word will be removed from the review schedule. All progress will be reset.")
        }
        .background(
            MarkdownEditorWrapper(markdownText: $notes, isPresented: $showMarkdownEditor)
                .frame(width: 400, height: 800)
        )
        .sheet(isPresented: $showSegmentation) {
            HybridSegmentationView(text: translation1)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                .frame(width: 400, height: 800)
        }
        .sheet(isPresented: $showPhotoVC) {
            PhotoViewControllerWrapper(initialSearchText: englishWord) { image in
                selectedImage = image
                imageDirty = true
                showPhotoVC = false
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: .gPhotoResult)) { notification in
            print("📱 DetailWordView: mottok .gPhotoResult notification")
            if let image = notification.userInfo?["image"] as? UIImage {
                print("📱 DetailWordView: bilde funnet i userInfo, størrelse \(image.size), setter selectedImage")
                selectedImage = image
                imageDirty = true
            } else {
                print("📱 DetailWordView: FEIL — ingen UIImage i userInfo[\"image\"]")
            }
        }
        #endif
        // Krever gPhotoKit — kommentert ut, se kommentar ved "Edit image"-knappen
        // .fullScreenCover(isPresented: $showAnnotationVC) {
        //     if let img = selectedImage {
        //         ImageAnnotationWrapper(image: img) { annotated in
        //             selectedImage = annotated
        //             imageDirty = true
        //         }
        //     }
        // }
        .popover(isPresented: Binding(
            get: { selectedWord != nil },
            set: { if !$0 { selectedWord = nil } }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedWord ?? "").font(.headline)
                Text(selectedMeaning ?? "").font(.subheadline)
                Button {
                    selectedWord = nil
                } label: {
                    Label("", systemImage: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 280)
        }
        .onAppear {
            guard currentWordOID == nil else {
                print("⏭️ onAppear: currentWordOID allerede satt, hopper over")
                if !hasRealImage { loadGroupThumbnailIfNeeded() }
                return
            }
            let w = initialWord
            currentWordOID = w.objectID
            print("🆕 onAppear: Satte currentWordOID = \(String(describing: currentWordOID)) for \(w.thaiWord)")
            thaiWord = w.thaiWord
            englishWord = w.englishWord
            ipa = w.ipa ?? ""
            tags = w.tags
            sentence = w.sentence.sanitizedForUITextView
            selectedImage = w.image
            originalWordID = w.uuid
            translation1 = w.translation1
            translation2 = w.translation2

            // Last inn notater fra databasen hvis dette er et eksisterende ord
            if let existingWord = fetchWord() {
                notes = existingWord.notes ?? ""
                wordType = existingWord.wordType
                // >= 0 (ikke > 0): 0 er en gyldig, bevisst lagret verdi og skal vises som "0",
                // ikke kollapses til tomt felt sammen med "aldri satt".
                editableFrequencyRank = existingWord.frequencyRank >= 0 ? String(existingWord.frequencyRank) : ""

                // Hent gruppenavn og YouTube-URL fra ordets faktiske gruppe
                let gid = existingWord.groupId
                let req: NSFetchRequest<Group> = Group.fetchRequest()
                req.predicate = NSPredicate(format: "groupId == %d", gid)
                req.fetchLimit = 1
                if let grp = try? context.fetch(req).first {
                    groupYoutubeUrl = grp.youtubeUrl
                    wordGroupName = grp.groupName ?? ""
                }
            }

            loadSiblings()

            // Auto-fyll fallback for tomt sentence-felt er slått av.
            // Vi vil bare vise det som faktisk ligger lagret i databasen.

            if selectedImage == nil { backfillImageIfNeeded() }
            hasRealImage = selectedImage != nil
            loadGroupThumbnailIfNeeded()

            // Auto-fyll stavelser FØR refreshSegmentationDebug() kjører — pipelinen der
            // leser precomputed stavelser fra `sentence` (ignorePrecomputedSyllables: false),
            // så rekkefølgen er viktig: ellers regner den ut debug-tokens fra et tomt felt
            // og fryser det resultatet selv om stavelsene fylles inn rett etterpå.
            generateSyllablesIfNeeded()
            translate()

            refreshSegmentationDebug()
            checkHasSentences()

            // Utsatt til neste runloop-runde: SwiftUI kan behandle .onChange(of: wordType) (utløst
            // av wordType-tilordningen lenger opp i denne samme .onAppear) etter at denne closuren
            // er ferdig, ikke synkront underveis — så flagget må fortsatt stå på true til DA.
            DispatchQueue.main.async {
                isInitializingWordType = false
            }
        }
        .onChange(of: thaiWord) { _, _ in
            refreshSegmentationDebug()
            checkHasSentences()
        }
        .onDisappear {
            print("🚪 DetailWordView onDisappear - didDelete: \(didDelete), didChangeGroup: \(didChangeGroup)")
            if !didDelete && !didChangeGroup {
                print("✅ Kaller lagreOrd() for \(thaiWord)")
                if let w = fetchWord() { applyFrequencyRankEdit(to: w) }
                lagreOrd()
            } else {
                print("⚠️ Hopper over lagreOrd() - didDelete: \(didDelete), didChangeGroup: \(didChangeGroup)")
            }
            Notifier.shared.hide()
        }
        #if targetEnvironment(macCatalyst)
        // Nested (fra SentenceListView): litt mindre så man ser vinduet bak
        // Normal: større størrelse for bedre arbeidsplass
        .frame(minWidth: isNested ? 900 : 1000, minHeight: isNested ? 1200 : 1300)
        #else
        // iPad: fast bredde, men høyden er begrenset til 90 % av FAKTISK skjermhøyde (ikke et
        // fast pikselbeløp) — en fast minHeight på f.eks. 1200 var høyere enn skjermens høyde i
        // liggende retning, slik at toppen av innholdet ble utilgjengelig/avkuttet der.
        // iPhone: ingen frame-begrensning, large detent fyller skjermen
        .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? (isNested ? 900 : 1000) : nil,
               minHeight: UIDevice.current.userInterfaceIdiom == .pad ? UIScreen.main.bounds.height * 0.9 : nil)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .wireNotifications()
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                SafariView(url: url)
            }
        }
        .fullScreenCover(isPresented: $showOrstDict) {
            OrstDictionaryView(word: thaiWord)
        }
        .fullScreenCover(isPresented: $showThaiLangDict) {
            ThaiLanguageDictionaryView(word: translation1)
        }
        .fullScreenCover(isPresented: $showSelectGroup) {
            SelectGroup(appState: appState) { selected in
                if let word = fetchWord() {
                    word.groupId = selected.groupId
                    didChangeGroup = true
                    try? context.save()
                    wordGroupName = selected.groupName ?? ""
                    appState.refreshToken = UUID()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                }
            }
            .environment(appState)
            .environment(\.managedObjectContext, context)
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 800, minHeight: 1000)
            #endif
        }
    }
}
var headerGradient: some View {
    LinearGradient(
        colors: [
            Color(.sRGB, red: 3.2,  green: 0.33, blue: 0.20, opacity: 0.4),
            Color(.sRGB, red: 0.19,  green: 0.35, blue: 0.40, opacity: 0.4)
        ],
        startPoint: .topLeading,
        endPoint: .trailing
    )
}
func getSubstrings(text: String, indices: TextSelection.Indices?) -> [Substring] {
    []
}

extension Text {
    init(plain s: String) { self = Text(verbatim: s) }
}
extension String {
    var sanitizedForUITextView: String {
        var s = self
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",    with: "\n")
        let badScalars: [UnicodeScalar] = [
            UnicodeScalar(0x2028)!,
            UnicodeScalar(0x2029)!,
            UnicodeScalar(0xFEFF)!,
            UnicodeScalar(0x200B)!
        ]
        s.unicodeScalars.removeAll(where: { badScalars.contains($0) })
        while s.last == "\n" { s.removeLast() }
        let multipleBlankLines = #"\n{3,}"#
        s = s.replacingOccurrences(of: multipleBlankLines, with: "\n\n", options: .regularExpression)
        return s
    }
}
#if DEBUG
extension WordInput {
    init(
        thaiWord: String,
        englishWord: String = "",
        ipa: String = "",
        sentence: String = "",
        tags: String = "",
        image: UIImage? = nil,
        objectID: NSManagedObjectID? = nil,
        uuid: UUID? = UUID(),
        translation1: String = "",
        translation2: String = ""
    ) {
        self.objectID = objectID
        self.thaiWord = thaiWord
        self.englishWord = englishWord
        self.ipa = ipa
        self.sentence = sentence
        self.tags = tags
        self.image = image
        self.uuid = uuid
        self.translation1 = translation1
        self.translation2 = translation2
    }
    static var mock: WordInput {
        // Lager et bredere demo-bilde (16:9 ratio) for å matche typiske bilder
        let size = CGSize(width: 320, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        let demoImage = renderer.image { context in
            // Gradient bakgrunn
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor] as CFArray,
                locations: [0.0, 1.0]
            )!
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            // Hvit tekst "DEMO"
            let text = "DEMO"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 40),
                .foregroundColor: UIColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }

        return WordInput(
            thaiWord: "เพราะ",
            englishWord: "dictionary",
            ipa: "pʰrɔ́ʔ",
            sentence: "This is an example sentence.",
            image: demoImage,
            translation1: "because",
            translation2: "This is an example sentence in English"
        )
    }
}
#endif
private enum PreviewCoreData {
    static let context: NSManagedObjectContext = {
        let model = NSManagedObjectModel.mergedModel(from: [Bundle.main])!
        let container = NSPersistentContainer(name: "Preview", managedObjectModel: model)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in
            if let error = error { fatalError("Preview store error: \(error)") }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container.viewContext
    }()
}



private struct DetailWordViewPreviewWrapper: View {
    @State private var appState = AppState()
    var body: some View {
        DetailWordView(initialWord: .mock, isNested: false)
            .environment(appState)
            .environment(\.managedObjectContext, PreviewCoreData.context)
    }
}
extension DetailWordView {
    private func toggleStar(for word: ThaiWords) {
        word.star.toggle()
        do {
            try context.save()
            let message = word.star ? "⭐️ Lagt til favoritter" : "Fjernet fra favoritter"
            Notifier.shared.show(.success, message)
        } catch {
            print("❌ Kunne ikke oppdatere stjerne: \(error)")
            word.star.toggle() // Revert på feil
            Notifier.shared.show(.error, "Could not update favorite")
        }
    }

    private func slettOrd() {
        guard let oid = currentWordOID else { return }
        do {
            if let eksisterende = try context.existingObject(with: oid) as? ThaiWords {
                context.delete(eksisterende)
                try context.save()
                didDelete = true
                dismiss()
            }
        } catch {
            print("❌ Kunne ikke slette ordet: \(error)")
        }
    }

    private func startLearningWord(_ word: ThaiWords) {
        // Initialize learning state
        word.learningState = LearningState.learning.rawValue
        word.learningStep = 0
        word.dueAt = Date() // Due now
        word.lastReviewedAt = Date()

        do {
            try context.save()
            print("✅ Startet øving på: \(word.thaiWord ?? "")")
        } catch {
            print("❌ Kunne ikke starte øving: \(error)")
        }
    }

    private func stopLearningWord(_ word: ThaiWords) {
        // Reset to new state
        word.learningState = LearningState.new.rawValue
        word.learningStep = 0
        word.dueAt = nil
        word.lastReviewedAt = nil
        word.repetitions = 0
        word.lapses = 0

        do {
            try context.save()
            print("✅ Stoppet øving på: \(word.thaiWord ?? "")")
        } catch {
            print("❌ Kunne ikke stoppe øving: \(error)")
        }
    }
}
extension DetailWordView {
    private func fetchWord() -> ThaiWords? {
        guard let oid = currentWordOID else { return nil }
        return (try? context.existingObject(with: oid)) as? ThaiWords
    }

    private func fetchExistingWord(thaiWord: String) -> ThaiWords? {
        // Store/små bokstaver er irrelevant for oppslaget ("jenta" skal finne "Jente") -> sammenlign case-insensitivt ([c]).
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "thaiWord ==[c] %@", thaiWord)
        request.fetchLimit = 1
        if let found = try? context.fetch(request).first {
            return found
        }

        // Fallback: prøv norske bøyningskandidater i regelrekkefølge (f.eks. "Guttene"/"Gutten"/"Gutter" -> "Gutt", "Liker"/"Likte"/"Likt" -> "Like", "Jenta" -> "Jente")
        let candidates = inflectionCandidates(for: thaiWord)
        for candidate in candidates {
            let request2 = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            request2.predicate = NSPredicate(format: "thaiWord ==[c] %@", candidate)
            request2.fetchLimit = 1
            if let found = try? context.fetch(request2).first {
                return found
            }
        }
        return nil
    }

    private func groupDisplayValue(for groupId: Int16) -> String {
        let req: NSFetchRequest<Group> = Group.fetchRequest()
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        if let name = (try? context.fetch(req).first)?.groupName, !name.isEmpty {
            return "\(groupId) · \(name)"
        }
        return String(groupId)
    }

    private func loadGroupThumbnailIfNeeded() {
        guard !imageDirty else { return }
        guard let existingWord = fetchWord() else { return }
        let gid = existingWord.groupId
        let req: NSFetchRequest<Group> = Group.fetchRequest()
        req.predicate = NSPredicate(format: "groupId == %d", gid)
        req.fetchLimit = 1
        guard let grp = try? context.fetch(req).first else { return }

        // Gruppebilde brukes kun som fallback hvis ordet ikke har eget bilde
        if let img = grp.groupUIImage, !hasRealImage, selectedImage == nil {
            selectedImage = img
            return
        }

        // Fallback: YouTube thumbnail (kun hvis ingen word-bilde fra bruker)
        guard !hasRealImage else { return }
        guard let url = grp.youtubeUrl, !url.isEmpty else { return }
        var videoId: String? = nil
        if let r = url.range(of: "v=") {
            videoId = String(url[r.upperBound...].prefix(while: { $0 != "&" && $0 != "?" }))
        } else if let r = url.range(of: "youtu.be/") {
            videoId = String(url[r.upperBound...].prefix(while: { $0 != "?" && $0 != "&" }))
        }
        guard let vid = videoId, !vid.isEmpty,
              let thumbURL = URL(string: "https://img.youtube.com/vi/\(vid)/mqdefault.jpg") else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
               let img = UIImage(data: data) {
                await MainActor.run { selectedImage = img }
            }
        }
    }

    private func createWordInCompanionGroup(thai: String) {
        guard let sourceGroupId = fetchWord()?.groupId else { return }
        let companionGroupId = sourceGroupId + 1

        let compReq: NSFetchRequest<Group> = Group.fetchRequest()
        compReq.predicate = NSPredicate(format: "groupId == %d", companionGroupId)
        compReq.fetchLimit = 1
        let companionGroup: Group
        if let existing = try? context.fetch(compReq).first {
            companionGroup = existing
        } else {
            // Vennegruppen (samme mønster som GLFunctions.createNewGroupId()) finnes ikke ennå -> opprett den nå
            print("♻️ Oppretter manglende vennegruppe groupId=\(companionGroupId)")
            let newGroup = Group(context: context)
            newGroup.id = UUID()
            newGroup.groupId = companionGroupId
            newGroup.groupName = "$" + String(companionGroupId)
            newGroup.groupType = -1 // vanlig aktiv gruppe
            try? context.save()
            companionGroup = newGroup
        }

        // Sjekk om ordet allerede finnes i vennegruppen
        let dupReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        dupReq.predicate = NSPredicate(format: "thaiWord == %@ AND groupId == %d", thai, companionGroupId)
        dupReq.fetchLimit = 1
        if (try? context.fetch(dupReq).first) != nil {
            print("⚠️ '\(thai)' finnes allerede i vennegruppen – hopper over")
            return
        }

        print("♻️ Bruker vennegruppe '\(companionGroup.groupName ?? "")' (groupId=\(companionGroupId))")

        let newWord = ThaiWords(context: context)
        newWord.id = UUID()
        newWord.thaiWord = thai
        newWord.groupId = companionGroup.groupId
        newWord.insertDate = Date()
        newWord.modifiedDate = Date()

        try? context.save()

        Task {
            do {
                let eng = try await performGoogleTranslate(text: thai, from: "no", to: "en")
                let trimmed = eng.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    if !trimmed.isEmpty && trimmed != thai {
                        newWord.englishWord = trimmed
                        newWord.wordType = ThaiWords.detectWordType(english: trimmed)
                        try? context.save()
                    }
                }
            } catch {
                print("⚠️ Oversettelse feilet for \(thai): \(error)")
            }
        }
    }

    /// Genererer stavelser fra thai-ordet og lagrer dem i `sentence`-feltet, men kun
    /// hvis feltet er tomt (samme sjekk som "Convert"-knappen bruker for denne grenen).
    @discardableResult
    private func generateSyllablesIfNeeded() -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty, !thaiWord.isEmpty else { return false }
        let syllables = ThaiSeg.segmentThai(thaiWord)
        let syllableStrings = syllables.map { $0.original }
        guard let data = try? JSONSerialization.data(withJSONObject: syllableStrings, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        sentence = json
        if let word = fetchWord() {
            word.sentence = json
            try? context.save()
        }
        return true
    }

    private func translate() {
        guard !isTranslating, !thaiWord.isEmpty else { return }
        let needNorsk = translation1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needEngelsk = englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needNorsk || needEngelsk else { return }
        isTranslating = true

        Task {
            do {
                if needNorsk {
                    let norsk = try await performGoogleTranslate(text: thaiWord, from: "no", to: morsmaalLanguage.translationCode)
                    await MainActor.run {
                        translation1 = norsk
                        if let word = fetchWord() {
                            word.translation1 = norsk
                            try? context.save()
                        }
                    }
                }
                if needEngelsk {
                    let engelsk = try await performGoogleTranslate(text: thaiWord, from: "no", to: "en")
                    await MainActor.run {
                        englishWord = engelsk
                        if let word = fetchWord() {
                            word.englishWord = engelsk
                            try? context.save()
                        }
                    }
                }
                await MainActor.run { isTranslating = false }
            } catch {
                print("❌ Oversettelse feilet: \(error)")
                await MainActor.run {
                    oversettelseFeil = "Translation failed: \(error.localizedDescription)"
                    isTranslating = false
                }
            }
        }
    }

    /// Tidligere kalte denne funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den
    /// delte AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
    private func performGoogleTranslate(text: String, from: String, to: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppleTranslationService.shared.translate(text: text, fromLanguage: from, toLanguage: to) { result in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "Translation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not translate"]))
                }
            }
        }
    }
}
// MARK: - YouTube-navigasjon
extension DetailWordView {
    func loadSiblings() {
        guard allowVideoNavigation, wordGroupName.hasPrefix("▶️"), let word = fetchWord() else {
            siblingWordIDs = []
            currentSiblingIndex = -1
            return
        }
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "groupId == %d", word.groupId)
        req.sortDescriptors = []
        let words = (try? context.fetch(req)) ?? []
        let sorted = Group.sortedChronologically(words)
        siblingWordIDs = sorted.map(\.objectID)
        currentSiblingIndex = siblingWordIDs.firstIndex(of: word.objectID) ?? -1
    }

    func navigateToWord(_ newWord: ThaiWords) {
        if let w = fetchWord() { applyFrequencyRankEdit(to: w) }
        lagreOrd()

        currentWordOID = newWord.objectID
        thaiWord = newWord.thaiWord ?? ""
        englishWord = newWord.englishWord ?? ""
        ipa = newWord.ipa ?? ""
        tags = newWord.tags ?? ""
        sentence = (newWord.sentence ?? "").sanitizedForUITextView
        originalWordID = newWord.id
        translation1 = newWord.translation1 ?? ""
        translation2 = newWord.translation2 ?? ""
        notes = newWord.notes ?? ""
        wordType = newWord.wordType
        editableFrequencyRank = newWord.frequencyRank >= 0 ? String(newWord.frequencyRank) : ""
        imageDirty = false
        isDirty = false
        selectedImage = newWord.image.flatMap { UIImage(data: $0) }
        hasRealImage = selectedImage != nil
        currentSiblingIndex = siblingWordIDs.firstIndex(of: newWord.objectID) ?? -1

        if !hasRealImage { loadGroupThumbnailIfNeeded() }
        refreshSegmentationDebug()
        checkHasSentences()
    }
}

// #Preview for DetailWordView omitted

// MARK: - DetailWordView2
// Fullstendig kopi av DetailWordView med egne state-variabler
// Brukes for å åpne ord fra forslag uten konflikter
struct DetailWordView2: View {
    let initialWord: WordInput
    let isNested: Bool

    @State  var currentWordOID: NSManagedObjectID? = nil
    @State  var originalWordID: UUID? = nil
    @State  var sentenceInput = ""
    @State  var selectedSnippet = ""
    @State  var ipaSnippet = ""
    @State var minH: CGFloat = 150
    @State var maxH: CGFloat = 200

    @State private var showError = false
    @State private var wordGroupName: String = ""
    @State private var showSelectGroup = false
    @State private var synth = AVSpeechSynthesizer()

    @State private var editableFrequencyRank: String = ""  // Added state variable for editable frequency rank

    @Environment(AppState.self)  var appState
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss)  var dismiss
    @Environment(\.openURL)  var openURL
    @State  var wordExists = false
    @State  var resultater: [ThaiWords] = []
    @State  var thaiWord: String = ""
    @State  var englishWord: String = ""
    @State  var ipa: String = ""
    @State  var sentence: String = ""
    @State  var tags: String = ""
    @State  var translation1: String = ""
    @State  var translation2: String = ""
    @State  var notes: String = ""
    @State  var wordType: Int16 = 0
    @State  var selectedImage: UIImage?
    @State  var imageDirty = false
    @State  var isDirty = false
    @State  var showPhotoVC = false
    @State  var isImageDropTargeted = false
    @State  var showAnnotationVC = false
    @State  var isTranslating = false
    @State  var visPhoneticView = false
    @State  var oversettelseFeil: String? = nil
    @State  var kildeIkon: UIImage? = nil
    @State  var visSletteAlert = false
    @State  var didDelete = false
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @State  var didChangeGroup = false
    @State  var selectedWord: String?
    @State  var selectedMeaning: String?
    @State  var selection: TextSelection? = nil
    @State  var showSegmentation = false
    @State private var showSyllableTranslate = false
    @State private var isPresented = false
    @State private var showPronounceChecker = false
    @State private var showSentences = false
    @State private var showingAddSentence = false
    @State private var showMainMenu = false
    @State private var showSyllableAnalysis = false
    @State private var selectedCandidateWord: String? = nil
    @State private var showMarkdownEditor = false
    @State private var showStopLearningAlert = false
    @State private var groupYoutubeUrl: String? = nil
    @State private var showOrstDict = false
    @State private var showThaiLangDict = false

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("(V2)")
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(.yellow)
            Text(wordGroupName.isEmpty ? appState.valgtGruppeNavn : wordGroupName)
                .font(.title3).fontWeight(.semibold)
            Spacer()


            // Uttale-knapp
            Button {
                showPronounceChecker = true
            } label: {
                Image(systemName: "mic.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 33, height: 33)
                    .foregroundStyle(.white)
            }

            // Meny-knapp
            Menu {
                mainMenuContent
            } label: {
                Image(systemName: "list.bullet.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 33, height: 33)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 40)
        .background(headerGradient)
    }

    @ViewBuilder
    private var mainMenuContent: some View {
        //if let word = fetchWord() {
        //    Button {
        //        showingAddSentence = true
        //    } label: {
        //        Label("Legg til setning", systemImage: "plus")
        //    }
//
        //    Button {
        //        showSentences = true
        //    } label: {
        //        Label("Vis setninger", systemImage: "book")
        //    }
        //}
//
        //Divider()

        Button {
            showPhotoVC = true
        } label: {
            Label("Choose image", systemImage: "photo.on.rectangle")
        }

        Button {
            #if os(iOS)
            GPhotoIntegration.openForPhoto(caller: "gNorsk") {
                showPhotoVC = true
            }
            #endif
        } label: {
            Label("Hent fra gPhoto", systemImage: "sparkles")
        }

        if let img = selectedImage {
            Button {
                #if os(iOS)
                GPhotoIntegration.openForEdit(image: img, caller: "gNorsk") {
                    Notifier.shared.show(.warning, "gPhoto not available")
                }
                #endif
            } label: {
                Label("Edit image", systemImage: "pencil.tip.crop.circle")
            }
        }

        // Krever gPhotoKit — kommentert ut, bruk "Hent fra gPhoto" (redigering skjer i gPhoto før bildet sendes tilbake)
        // if selectedImage != nil {
        //     Button {
        //         showAnnotationVC = true
        //     } label: {
        //         Label("Edit image", systemImage: "pencil.tip.crop.circle")
        //     }
        // }

       // Button {
       //     showSegmentation = true
       // } label: {
       //     Label("Segmentering", systemImage: "square.grid.3x1.folder.badge.plus")
       // }

        Divider()

        Menu {
            Button {
                g.talkTh(talkText: thaiWord, rate: 0.5, language: "nb-NO")
            } label: {
                Label("Narisa (TTS)", systemImage: "speaker.wave.2.fill")
            }
            Button {
                let utter = AVSpeechUtterance(string: thaiWord)
                utter.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.nb-NO.Nora") ?? AVSpeechSynthesisVoice(language: "nb-NO")
                let kanyaRate = UserDefaults.standard.double(forKey: "speechRateThai")
                utter.rate = kanyaRate > 0 ? Float(kanyaRate) : 0.5
                if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
                synth.speak(utter)
            } label: {
                Label("Kanya (TTS)", systemImage: "waveform")
            }
            Divider()
            Button {
                showPronounceChecker = true
            } label: {
                Label("Uttalesjekk", systemImage: "mic.circle.fill")
            }
        } label: {
            Label("Uttale", systemImage: "speaker.wave.2")
        }

        Menu {
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Thai2English", systemImage: "globe.asia.australia")
            }
            Button {
                showThaiLangDict = true
            } label: {
                Label("thai-language.com", systemImage: "character.book.closed")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://dict.longdo.com/?search=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Longdo Dict", systemImage: "book.pages")
            }
            Button {
                showOrstDict = true
            } label: {
                Label("Royal Society Dictionary", systemImage: "text.book.closed")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://forvo.com/search/\(encoded)/no/") {
                    openURL(url)
                }
            } label: {
                Label("Forvo", systemImage: "person.wave.2")
            }
            Button {
                if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://papago.naver.com/?sk=no&tk=th&st=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Papago", systemImage: "p.circle.fill")
            }
            Button {
                openGoogleTranslate(thaiWord, targetLang: "th", using: openURL)
            } label: {
                Label("Google Translate", systemImage: "g.circle.fill")
            }
        } label: {
            Label("Referanser", systemImage: "books.vertical")
        }

        Button {
            translate()
        } label: {
            if isTranslating {
                Label("Oversetter...", systemImage: "arrow.triangle.2.circlepath")
            } else {
                Label("Oversett", systemImage: "arrow.left.arrow.right")
            }
        }
        .disabled(isTranslating)

        Divider()

        // Endre gruppe (Normal/Vente/OK)
        if let word = fetchWord() {
            Menu {
                changeGroupMenuContent2(for: word)
            } label: {
                Label("Change group type", systemImage: "folder.badge.gearshape")
            }
        }

        Button {
            showSelectGroup = true
        } label: {
            Label("Change group", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            visSletteAlert = true
        } label: {
            Label("Delete word", systemImage: "trash")
        }
    }

    private func speakText(_ text: String, language: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let utter = AVSpeechUtterance(string: t)
        utter.voice = AVSpeechSynthesisVoice(language: language)
        let rateKey = language == "en-US" ? "speechRateEnglish" : "speechRateMorsmaal"
        let storedRate = UserDefaults.standard.double(forKey: rateKey)
        utter.rate = storedRate > 0 ? Float(storedRate) : 0.5
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(utter)
    }

    private func groupExists2(_ groupId: Int16) -> Bool {
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        return (try? context.fetch(req).first) != nil
    }

    @ViewBuilder
    private func changeGroupMenuContent2(for word: ThaiWords) -> some View {
        let currentGroupId = Int16(word.groupId)
        let baseGroupId = Int16((currentGroupId / 3) * 3)
        let groupType = Int16(currentGroupId % 3)

        let normalGroupId = baseGroupId
        let venteGroupId = Int16(baseGroupId + 1)
        let okGroupId = Int16(baseGroupId + 2)

        Button {
            changeWordGroup2(word: word, to: normalGroupId)
        } label: {
            HStack {
                Text("Normal group (ID: \(normalGroupId))")
                if groupType == 0 { Image(systemName: "checkmark") }
            }
        }
        .disabled(groupType == 0)

        if groupExists2(venteGroupId) {
            Button {
                changeWordGroup2(word: word, to: venteGroupId)
            } label: {
                HStack {
                    Text("Waiting group (ID: \(venteGroupId))")
                    if groupType == 1 { Image(systemName: "checkmark") }
                }
            }
            .disabled(groupType == 1)
        }

        if groupExists2(okGroupId) {
            Button {
                changeWordGroup2(word: word, to: okGroupId)
            } label: {
                HStack {
                    Text("OK group (ID: \(okGroupId))")
                    if groupType == 2 { Image(systemName: "checkmark") }
                }
            }
            .disabled(groupType == 2)
        }
    }

    private func changeWordGroup2(word: ThaiWords, to newGroupId: Int16) {
        let oldGroupId = word.groupId
        word.groupId = newGroupId

        do {
            try context.save()
            // Mark that group was changed to prevent overwriting in onDisappear
            didChangeGroup = true
            // Refresh context to ensure changes are visible
            context.refreshAllObjects()
            let groupTypeName = getGroupTypeName2(for: newGroupId)
            Notifier.shared.show(.success, "Moved to \(groupTypeName) (ID: \(newGroupId))")
            // Trigger GridView refresh
            appState.refreshToken = UUID()
            // Close the detail view after moving to different group
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            word.groupId = oldGroupId // Revert on error
            Notifier.shared.show(.error, "Could not change group: \(error.localizedDescription)")
        }
    }

    private func getGroupTypeName2(for groupId: Int16) -> String {
        switch groupId % 3 {
        case 0: return "Normal group"
        case 1: return "Waiting group"
        case 2: return "OK group"
        default: return "Unknown group"
        }
    }

    @ViewBuilder
    private func contentView(_ w: ThaiWords?) -> some View {
        VStack(spacing: 2) {
            HStack {
                if let word = w {
                    // Plus button for adding sentence (only when we have a real word)
                    Button {
                        showingAddSentence = true
                    } label: {
                        Label("", systemImage: "plus")
                    }
                    .fullScreenCover(isPresented: $showingAddSentence) {
                        CreateWordView(linkedWord: word)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        if let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://ordbokene.no/nob/bm/\(encoded)") {
                            openURL(url)
                        }
                    } label: {
                        Image(systemName: "globe.asia.australia")
                            .font(.body)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showThaiLangDict = true
                    } label: {
                        Image(systemName: "character.book.closed")
                            .font(.body)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let encoded = translation1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://forvo.com/search/\(encoded)/th/") {
                            openURL(url)
                        }
                    } label: {
                        Image(systemName: "person.wave.2")
                            .font(.body)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Image display - works both with Core Data word and mock data
                SwiftUI.Group {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 2)
                            .onTapGesture {
                                if let t = w?.thaiWord {
                                    CloudTTSTest.speakNorsk(t)
                                }
                            }
                    } else {
                        Image(systemName: "questionmark.square.fill")
                            .resizable().scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if isImageDropTargeted {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor, lineWidth: 6)
                    }
                }
                .onDrop(of: [.image], isTargeted: $isImageDropTargeted) { providers in
                    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else {
                        return false
                    }
                    provider.loadObject(ofClass: UIImage.self) { reading, _ in
                        guard let droppedImage = reading as? UIImage else { return }
                        DispatchQueue.main.async {
                            selectedImage = droppedImage
                            imageDirty = true
                        }
                    }
                    return true
                }
                if let word = w {
                    // Book button (only when we have a real word)
                    Button {
                        showSentences = true
                    } label: {
                        Label("", systemImage: "book")
                    }
                    
                    
                    .fullScreenCover(isPresented: $showSentences) {
                        SentenceListView(tag: word.thaiWord ?? "")
                    }
                }
            }
            .alert("The clipboard must contain only Thai characters.", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }

            
            
            
            
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Norwegian").font(.caption.bold())
                        Spacer()
                        Button { CloudTTSTest.speakNorsk(thaiWord) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(thaiWord.isEmpty)
                    }
                    if isNested {
                        TextEditor(text: $thaiWord)
                            .font(.system(size: 28))
                            .frame(minHeight: minH, maxHeight: maxH)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    } else {
                        ThaiSuggestionEditor(
                            text: $thaiWord,
                            minH: $minH,
                            maxH: $maxH,
                            onSelectWord: { word in
                                print("🟣 SUGGESTION SELECTED: \(word)")
                                selectedCandidateWord = word
                            }
                        )
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Englishx").font(.caption.bold())
                        Spacer()
                        Button { speakText(englishWord, language: "en-US") } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(englishWord.isEmpty)
                    }
                    ZStack(alignment: .topLeading) {
                        Text(englishWord.isEmpty ? " " : englishWord)
                            .font(.system(size: 22))
                            .foregroundColor(.clear)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                        TextEditor(text: $englishWord)
                            .font(.system(size: 22))
                    }
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                HStack(spacing: 8) {
                    Text("Type").font(.caption.bold())
                    Picker("", selection: $wordType) {
                        Text("Word").tag(Int16(0))
                        Text("Sentence").tag(Int16(1))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .onChange(of: wordType) { _, newValue in
                        // Setninger skal aldri ha en frekvensrang i kjerne-ord-listen (1–4000) —
                        // 0 = "ikke satt", slik at ingen positive verdier blokkeres for spesialtilfeller av ord.
                        if newValue == 1 {
                            editableFrequencyRank = ""
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(morsmaalLanguage.label).font(.caption.bold())
                        Spacer()
                        Button { speakText(translation1, language: morsmaalLanguage.locale) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(translation1.isEmpty)
                    }
                    ZStack(alignment: .topLeading) {
                        Text(translation1.isEmpty ? " " : translation1)
                            .font(.system(size: 32))
                            .foregroundColor(.clear)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                        TextEditor(text: $translation1)
                            .font(.system(size: 32))
                    }
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                HStack {
                    Text("Notes (Markdown)").font(.caption.bold())
                    Spacer()
                    Button {
                        showMarkdownEditor = true
                    } label: {
                        Label("", systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                }

                

                
                
                ////-----

                

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags").font(.caption.bold())
                    TextEditor(text: $tags)
                        .frame(minHeight: 40, maxHeight: 40)
                        .font(.system(size: 20))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                VStack(alignment: .leading, spacing: 6) {
                    
                    
          //          VStack(alignment: .leading, spacing: 6) {
          //              Text("IPA").font(.caption.bold())
          //              TextEditor(text: $ipa)
          //                  .frame(minHeight: 40, maxHeight: 60)
          //                  .font(.system(size: 20))
          //                  .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
          //          }
          //
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Syllables").font(.caption.bold())
                            Spacer()
                            Button {
                                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty && !thaiWord.isEmpty {
                                    if generateSyllablesIfNeeded() {
                                        Notifier.shared.show(.success, "Generated syllables from Thai word")
                                    } else {
                                        Notifier.shared.show(.error, "Could not generate syllables from Thai word")
                                    }
                                } else if let data = trimmed.data(using: .utf8),
                                          let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
                                          !arr.isEmpty {
                                    // Already valid JSON — do nothing
                                } else if let converted = convertBracketedSyllablesToJSON(trimmed) {
                                    sentence = converted
                                    if let word = fetchWord() {
                                        word.sentence = converted
                                        try? context.save()
                                    }
                                    Notifier.shared.show(.success, "Converted to JSON format")
                                } else {
                                    Notifier.shared.show(.error, "No valid bracket format found to convert")
                                }
                            } label: {
                                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack {
                            TextEditor(text: $sentence)
                                .frame(minHeight: 40, maxHeight: 120)
                                .font(.system(size: 30))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        }

                        // Tone-annotert visning av stavelser
                        if !sentence.isEmpty {
                            let currentWord = currentWordOID.flatMap { try? context.existingObject(with: $0) as? ThaiWords }
                            ToneAnnotatedSentenceView(
                                text: sentence,
                                fontSize: 24,
                                showInfoButtons: true,
                                word: currentWord
                            )
                            // Inline per-syllable buttons (one syllable = one info button)
                         //   InlineSyllableInfoRow(rawSentence: sentence, fontSize: 22, word: currentWord)
                                .padding(.top, 6)

                            CombinedWordIPAView(sentence: sentence, word: currentWord, fontSize: 22)
                        }

                       
                    }

                    // YouTube-knapp hvis gruppen har URL og notes har tidsstempel
                    if let url = groupYoutubeUrl, !url.isEmpty, !notes.isEmpty {
                        Button {
                            let secs = Group.timestampToSeconds(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                            Group.openYouTube(baseUrl: url, seconds: secs)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.red)
                                Text("Start video ved \(notes.trimmingCharacters(in: .whitespacesAndNewlines))")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    // Klikkbar preview av notater
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                        if notes.isEmpty {
                            Text("Tap to add notes...")
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            let mdReady = notes
                                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                .replacingOccurrences(of: "\\s+(\\*{1,2})", with: "$1", options: .regularExpression)
                            Text((try? AttributedString(markdown: mdReady, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(notes))
                                .font(.system(size: 16))
                                .lineLimit(4)
                                .padding(12)
                        }
                    }
                    .frame(minHeight: 80, maxHeight: 120)
                    .onTapGesture {
                        showMarkdownEditor = true
                    }
                }

                // NEW EDITABLE FREQUENCY RANK INPUT
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frequency rank (editable)").font(.caption.bold())
                    TextField("f.eks. 123", text: $editableFrequencyRank)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .submitLabel(.done)
                        .onSubmit {
                            if let w = w {
                                applyFrequencyRankEdit(to: w)
                            }
                        }
                }
                .gridCellColumns(2)
            }
            .padding(.horizontal)

            if let word = w {
                additionalFieldsSection2(word: word)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func additionalFieldsSection2(word: ThaiWords) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 8)

            Text("Additional information")
                .font(.headline)
                .foregroundColor(.primary)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], alignment: .leading, spacing: 8) {
                InfoFieldView(label: "ID", value: word.id?.uuidString ?? "None")
                InfoFieldView(label: "Group ID", value: groupDisplayValue(for: word.groupId))

                // Stjerne som klikkbar knapp (bare ikon)
                Button {
                    toggleStar2(for: word)
                } label: {
                    Image(systemName: word.star ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundColor(word.star ? .yellow : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                InfoFieldView(label: "Language", value: word.language ?? "Not set")
                InfoFieldView(label: "Created", value: formatDate(word.insertDate))
                InfoFieldView(label: "Date 1", value: formatDate(word.dateOne))
                InfoFieldView(label: "Date 2", value: formatDate(word.dateTwo))
                InfoFieldView(label: "Frequency rank", value: word.frequencyRank > 0 ? String(word.frequencyRank) : "Not set")
                InfoFieldView(label: "IPA", value: word.ipa ?? "Not set")
                InfoFieldView(label: "Translation 1", value: word.translation1 ?? "Not set")
            }

            // Læringsfelter
            VStack(alignment: .leading, spacing: 8) {
                Text("Learning")
                    .font(.caption.bold())
                    .foregroundColor(.green)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], alignment: .leading, spacing: 8) {
                    InfoFieldView(label: "Last reviewed", value: formatDate(word.lastReviewedAt))
                    InfoFieldView(label: "Due", value: formatDate(word.dueAt))
                    InfoFieldView(label: "Difficulty", value: word.easiness > 0 ? String(format: "%.2f", word.easiness) : "Not set")
                    InfoFieldView(label: "Repetitions", value: String(word.repetitions))
                    InfoFieldView(label: "Lapses", value: String(word.lapses))
                    InfoFieldView(label: "Last result", value: String(word.lastResult))
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { showPronounceChecker = true } label: { Label("Pron",  systemImage: "mic.circle.fill") }.buttonStyle(.bordered)
            Spacer()

            Button { showSegmentation = true } label: { Label("", systemImage: "square.grid.3x1.folder.badge.plus") }.buttonStyle(.bordered)

            Spacer()
            // Stavelse-analyse button removed - now shown in segmentation view
        }
    }

    var body: some View {
        let w = fetchWord()
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                contentView(w)
                    .padding(.bottom, 120)  // Ekstra padding nederst for å kunne scrolle over bottomBar
            }

        }
        .safeAreaInset(edge: .top) {
            headerView
        }
#if targetEnvironment(macCatalyst)
    .overlay(alignment: .bottom) {
        bottomBar
            .padding(.horizontal)
            .padding(.vertical, 0)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
            .padding(.bottom, 14)
    }
#else

        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal)
                .padding(.vertical, 0)
                .background(.ultraThinMaterial)
        }
#endif
        .background(Color(.systemBackground).ignoresSafeArea())
        .scrollIndicators(.visible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showPronounceChecker) { ThaiPronounceCheckView(target: thaiWord) }
        .sheet(isPresented: $showSyllableAnalysis) {
            ThaiSyllableAnalysisView(thaiWord: thaiWord)
        }
        // fullScreenCover (ikke sheet) — se forklaring i hoved-DetailWordView sin tilsvarende
        // presentasjon: en nøstet sheet på iPad ignorerer presentationDetents/frame.
        .fullScreenCover(item: Binding(
            get: {
                if let word = selectedCandidateWord {
                    print("🟢 SHEET GET: \(word)")
                    // Hent eller opprett WordInput for dette ordet
                    if let existingWord = fetchExistingWord(thaiWord: word) {
                        return WordInput(from: existingWord)
                    } else {
                        // Opprett dummy WordInput hvis ordet ikke finnes
                        return WordInput(
                            objectID: nil,
                            thaiWord: word,
                            englishWord: "",
                            sentence: "",
                            tags: "",
                            image: nil,
                            uuid: UUID(),
                            translation1: "",
                            translation2: ""
                        )
                    }
                }
                print("🔴 SHEET GET: nil")
                return nil
            },
            set: { newValue, _ in
                print("🟡 SHEET SET: \(newValue?.thaiWord ?? "nil")")
                if newValue == nil {
                    selectedCandidateWord = nil
                }
            }
        )) { (wordInput: WordInput) in
            DetailWordView2(initialWord: wordInput, isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #else
                .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 900 : nil,
                       minHeight: UIDevice.current.userInterfaceIdiom == .pad ? UIScreen.main.bounds.height * 0.9 : nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
                // fullScreenCover kan ikke sveipes vekk (i motsetning til sheet) — trenger derfor
                // en egen lukk-knapp. Setter selectedCandidateWord = nil direkte (samme som
                // Binding sin set-closure over gjør) i stedet for @Environment(\.dismiss), for å
                // unngå tvetydighet om hvilken presentasjon dismiss() faktisk peker på her.
                .overlay(alignment: .topLeading) {
                    Button {
                        selectedCandidateWord = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white, Color.black.opacity(0.4))
                    }
                    .padding()
                }
        }
        .alert("Do you want to delete this word?", isPresented: $visSletteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { slettOrd() }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Stop practicing this word?", isPresented: $showStopLearningAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Stop", role: .destructive) {
                if let word = fetchWord() {
                    stopLearningWord(word)
                }
            }
        } message: {
            Text("The word will be removed from the review schedule. All progress will be reset.")
        }
        .background(
            MarkdownEditorWrapper(markdownText: $notes, isPresented: $showMarkdownEditor)
                .frame(width: 400, height: 800)
        )
        .sheet(isPresented: $showSegmentation) {
            HybridSegmentationView(text: thaiWord)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showPhotoVC) {
            PhotoViewControllerWrapper(initialSearchText: englishWord) { image in
                selectedImage = image
                imageDirty = true
                showPhotoVC = false
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: .gPhotoResult)) { notification in
            print("📱 DetailWordView: mottok .gPhotoResult notification")
            if let image = notification.userInfo?["image"] as? UIImage {
                print("📱 DetailWordView: bilde funnet i userInfo, størrelse \(image.size), setter selectedImage")
                selectedImage = image
                imageDirty = true
            } else {
                print("📱 DetailWordView: FEIL — ingen UIImage i userInfo[\"image\"]")
            }
        }
        #endif
        // Krever gPhotoKit — kommentert ut, se kommentar ved "Edit image"-knappen
        // .fullScreenCover(isPresented: $showAnnotationVC) {
        //     if let img = selectedImage {
        //         ImageAnnotationWrapper(image: img) { annotated in
        //             selectedImage = annotated
        //             imageDirty = true
        //         }
        //     }
        // }
        .popover(isPresented: Binding(
            get: { selectedWord != nil },
            set: { if !$0 { selectedWord = nil } }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedWord ?? "").font(.headline)
                Text(selectedMeaning ?? "").font(.subheadline)
                Button {
                    selectedWord = nil
                } label: {
                    Label("", systemImage: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 280)
        }
        .onAppear {
            guard currentWordOID == nil else {
                print("⏭️ onAppear: currentWordOID allerede satt, hopper over")
                return
            }
            let w = initialWord
            currentWordOID = w.objectID
            print("🆕 onAppear: Satte currentWordOID = \(String(describing: currentWordOID)) for \(w.thaiWord)")
            thaiWord = w.thaiWord
            englishWord = w.englishWord
            ipa = w.ipa ?? ""
            tags = w.tags
            sentence = w.sentence.sanitizedForUITextView
            selectedImage = w.image
            originalWordID = w.uuid
            translation1 = w.translation1
            translation2 = w.translation2

            // Last inn notater fra databasen hvis dette er et eksisterende ord
            if let existingWord = fetchWord() {
                notes = existingWord.notes ?? ""
                wordType = existingWord.wordType
                // >= 0 (ikke > 0): 0 er en gyldig, bevisst lagret verdi og skal vises som "0",
                // ikke kollapses til tomt felt sammen med "aldri satt".
                editableFrequencyRank = existingWord.frequencyRank >= 0 ? String(existingWord.frequencyRank) : ""

                // Hent gruppenavn og YouTube-URL fra ordets faktiske gruppe
                let gid = existingWord.groupId
                let req: NSFetchRequest<Group> = Group.fetchRequest()
                req.predicate = NSPredicate(format: "groupId == %d", gid)
                req.fetchLimit = 1
                if let grp = try? context.fetch(req).first {
                    groupYoutubeUrl = grp.youtubeUrl
                    wordGroupName = grp.groupName ?? ""
                }
            }

            // Auto-fyll fallback for tomt sentence-felt er slått av.
            // Vi vil bare vise det som faktisk ligger lagret i databasen.

            if selectedImage == nil { backfillImageIfNeeded() }
            if selectedImage == nil { selectedImage = UIImage(systemName: "questionmark.square.fill") }
        }
        .onDisappear {
            print("🚪 DetailWordView2 onDisappear - didDelete: \(didDelete), didChangeGroup: \(didChangeGroup)")
            if !didDelete && !didChangeGroup {
                print("✅ Kaller lagreOrd() for \(thaiWord)")
                if let w = fetchWord() { applyFrequencyRankEdit(to: w) }
                lagreOrd()
            } else {
                print("⚠️ Hopper over lagreOrd() - didDelete: \(didDelete), didChangeGroup: \(didChangeGroup)")
            }
            Notifier.shared.hide()
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 900, minHeight: 1200)
        #else
        // iPad: fast bredde, men høyden er 90 % av FAKTISK skjermhøyde, ikke et fast pikselbeløp —
        // se forklaring i hoved-DetailWordView sin tilsvarende modifier.
        // iPhone: ingen frame-begrensning, large detent fyller skjermen
        .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 900 : nil,
               minHeight: UIDevice.current.userInterfaceIdiom == .pad ? UIScreen.main.bounds.height * 0.9 : nil)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .wireNotifications()
        .fullScreenCover(isPresented: $showOrstDict) {
            OrstDictionaryView(word: thaiWord)
        }
        .fullScreenCover(isPresented: $showThaiLangDict) {
            ThaiLanguageDictionaryView(word: translation1)
        }
        .fullScreenCover(isPresented: $showSelectGroup) {
            SelectGroup(appState: appState) { selected in
                if let word = fetchWord() {
                    word.groupId = selected.groupId
                    didChangeGroup = true
                    try? context.save()
                    wordGroupName = selected.groupName ?? ""
                    appState.refreshToken = UUID()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                }
            }
            .environment(appState)
            .environment(\.managedObjectContext, context)
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 800, minHeight: 1000)
            #endif
        }
    }

    private func applyFrequencyRankEdit(to word: ThaiWords) {
        let trimmed = editableFrequencyRank.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            word.frequencyRank = 0
        } else if let val = Int32(trimmed), val >= 0 {
            word.frequencyRank = val
        } else {
            Notifier.shared.show(.error, "Ugyldig frekvensrang: \(editableFrequencyRank)")
            return
        }
        do {
            try context.save()
            Notifier.shared.show(.success, "Frequency rank updated")
        } catch {
            Notifier.shared.show(.error, "Could not save frequency rank: \(error.localizedDescription)")
        }
    }

    private func slettOrd() {
        guard let oid = currentWordOID else { return }
        do {
            if let eksisterende = try context.existingObject(with: oid) as? ThaiWords {
                context.delete(eksisterende)
                try context.save()
                didDelete = true
                dismiss()
            }
        } catch {
            print("❌ Kunne ikke slette ordet: \(error)")
        }
    }

    private func convertBracketedSyllablesToJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[") && trimmed.contains("]") else { return nil }
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        var parts: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { parts.append(s) }
        }
        guard !parts.isEmpty else { return nil }
        let escaped = parts.map { "\"\($0)\"" }.joined(separator: ",")
        return "[" + escaped + "]"
    }

    private func generateSyllablesIfNeeded() -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty, !thaiWord.isEmpty else { return false }
        let syllables = ThaiSeg.segmentThai(thaiWord)
        let syllableStrings = syllables.map { $0.original }
        guard let data = try? JSONSerialization.data(withJSONObject: syllableStrings, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        sentence = json
        if let word = fetchWord() {
            word.sentence = json
            try? context.save()
        }
        return true
    }

    private func fetchWord() -> ThaiWords? {
        guard let oid = currentWordOID else { return nil }
        return (try? context.existingObject(with: oid)) as? ThaiWords
    }

    private func fetchExistingWord(thaiWord: String) -> ThaiWords? {
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func groupDisplayValue(for groupId: Int16) -> String {
        let req: NSFetchRequest<Group> = Group.fetchRequest()
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        req.fetchLimit = 1
        if let name = (try? context.fetch(req).first)?.groupName, !name.isEmpty {
            return "\(groupId) · \(name)"
        }
        return String(groupId)
    }

    private func translate() {
        guard !isTranslating, !thaiWord.isEmpty else { return }
        let needNorsk = translation1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needEngelsk = englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needNorsk || needEngelsk else { return }
        isTranslating = true

        Task {
            do {
                if needNorsk {
                    let norsk = try await performGoogleTranslate(text: thaiWord, from: "no", to: morsmaalLanguage.translationCode)
                    await MainActor.run { translation1 = norsk }
                }
                if needEngelsk {
                    let engelsk = try await performGoogleTranslate(text: thaiWord, from: "no", to: "en")
                    await MainActor.run { englishWord = engelsk }
                }
                await MainActor.run { isTranslating = false }
            } catch {
                print("❌ Oversettelse feilet: \(error)")
                await MainActor.run {
                    oversettelseFeil = "Translation failed: \(error.localizedDescription)"
                    isTranslating = false
                }
            }
        }
    }

    /// Tidligere kalte denne funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den
    /// delte AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
    private func performGoogleTranslate(text: String, from: String, to: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppleTranslationService.shared.translate(text: text, fromLanguage: from, toLanguage: to) { result in
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "Translation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not translate"]))
                }
            }
        }
    }

    private func backfillImageIfNeeded() {
        guard let oid = currentWordOID,
              let word = try? context.existingObject(with: oid) as? ThaiWords,
              let imgData = word.image,
              let img = UIImage(data: imgData) else { return }
        selectedImage = img
    }

    private func lagreOrd() {
        print("💾 lagreOrd() START for '\(thaiWord)'")
        guard let oid = currentWordOID else {
            print("❌ FEIL: currentWordOID er nil! Kan ikke lagre \(thaiWord)")
            print("   initialWord.objectID = \(String(describing: initialWord.objectID))")
            return
        }
        print("   currentWordOID = \(oid)")

        do {
            let wordToSave: ThaiWords
            let isNewWord: Bool
            print("   Henter eksisterende objekt fra context...")
            if let existing = try? context.existingObject(with: oid) as? ThaiWords {
                print("   ✅ Fant eksisterende ord i context")
                wordToSave = existing
                isNewWord = false
            } else {
                print("   ⚠️ Fant IKKE eksisterende ord - sjekker duplikat...")
                // Sjekk om ordet allerede finnes før vi oppretter nytt
                let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                fetch.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
                fetch.fetchLimit = 1

                if let duplicate = try context.fetch(fetch).first {
                    print("   ❌ Duplikat funnet! Avbryter lagring.")
                    Notifier.shared.show(.error, "The word '\(thaiWord)' already exists in the database.")
                    return
                }
                print("   ✅ Ingen duplikat - oppretter nytt ord")

                wordToSave = ThaiWords(context: context)
                wordToSave.id = UUID()
                wordToSave.groupId = appState.sqlGruppeId
                isNewWord = true
            }

            wordToSave.thaiWord = thaiWord
            wordToSave.englishWord = englishWord
            wordToSave.ipa = ipa
            wordToSave.sentence = sentence
            wordToSave.tags = tags
            wordToSave.translation1 = translation1
            wordToSave.translation2 = translation2
            wordToSave.notes = notes
            wordToSave.wordType = wordType

            if imageDirty, let img = selectedImage {
                wordToSave.image = img.jpegData(compressionQuality: 0.8)
            }

            // Update modified date
            wordToSave.modifiedDate = Date()
            print("📝 LAGRET: modifiedDate satt til \(wordToSave.modifiedDate!) for \(thaiWord)")

            try context.save()

            // Vis bekreftelse kun for nye ord
            if isNewWord {
                Notifier.shared.show(.success, "New word saved: \(thaiWord)")
            } else {
                print("✅ Eksisterende ord oppdatert: \(thaiWord)")
            }
        } catch {
            print("❌ Lagring feilet: \(error)")
            Notifier.shared.show(.error, "Could not save word: \(error.localizedDescription)")
        }
    }
}

// MARK: - DetailWordView2 Extensions
extension DetailWordView2 {
    private func toggleStar2(for word: ThaiWords) {
        word.star.toggle()
        do {
            try context.save()
            let message = word.star ? "⭐️ Lagt til favoritter" : "Fjernet fra favoritter"
            Notifier.shared.show(.success, message)
        } catch {
            print("❌ Kunne ikke oppdatere stjerne: \(error)")
            word.star.toggle() // Revert på feil
            Notifier.shared.show(.error, "Could not update favorite")
        }
    }

    private func startLearningWord(_ word: ThaiWords) {
        word.learningState = LearningState.learning.rawValue
        word.learningStep = 0
        word.dueAt = Date()
        word.lastReviewedAt = Date()

        do {
            try context.save()
            print("✅ Startet øving på: \(word.thaiWord ?? "")")
        } catch {
            print("❌ Kunne ikke starte øving: \(error)")
        }
    }

    private func stopLearningWord(_ word: ThaiWords) {
        word.learningState = LearningState.new.rawValue
        word.learningStep = 0
        word.dueAt = nil
        word.lastReviewedAt = nil
        word.repetitions = 0
        word.lapses = 0

        do {
            try context.save()
            print("✅ Stoppet øving på: \(word.thaiWord ?? "")")
        } catch {
            print("❌ Kunne ikke stoppe øving: \(error)")
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Ikke satt" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/* MARK: - Inline per-syllable info row used in DetailWordView commentet out.. more clean but less info
private struct InlineSyllableInfoRow: View {
    let rawSentence: String
    let fontSize: CGFloat
    let word: ThaiWords?
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @State private var selectedInfo: SyllableToneInfo? = nil

    var body: some View {
        let syllables = parseSyllables(rawSentence)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(syllables.enumerated()), id: \.offset) { _, syl in
                    HStack(spacing: 6) {
                        // Render [stavelse]
                        Text("[")
                            .font(.system(size: fontSize))
                            .foregroundStyle(.secondary)
                        Text(syl)
                            .font(.system(size: fontSize, weight: .semibold))
                        Text("]")
                            .font(.system(size: fontSize))
                            .foregroundStyle(.secondary)
                        // Info button for THIS syllable
                        Button {
                            if let info = analyzeSingleSyllable(syl) { selectedInfo = info }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: fontSize * 0.9))
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $selectedInfo) { info in
                    #if targetEnvironment(macCatalyst)
                    ToneExplanationView(info: info, word: word)
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                        .frame(minWidth: 560, idealWidth: 560, maxWidth: 700,
                               minHeight: 1100, idealHeight: 1100, maxHeight: 1100)
                    #else
                    ToneExplanationView(info: info, word: word)
                        .environment(appState)
                        .environment(\.managedObjectContext, context)
                    #endif
                
            
        }
    }

    // Parse both formats: ["a","b"] or [a][b]
    private func parseSyllables(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.contains("\"") { // JSON array format
            if let data = trimmed.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: data) {
                return arr.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
        // Fallback: extract content between [ and ]
        let pattern = "\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let s = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
        }
        return out
    }

    // Build SyllableToneInfo for a single syllable string
    private func analyzeSingleSyllable(_ syl: String) -> SyllableToneInfo? {
        // Use ThaiSeg to analyze; if it returns multiple, merge like ToneAnnotatedSentenceView does
        let analyzed = ThaiSeg.segmentThai(syl)
        guard !analyzed.isEmpty else { return nil }
        let one: ThaiSyllable = analyzed.count == 1 ? analyzed[0] : mergeSyllables(analyzed, originalText: syl)

        // Ensure the displayed original equals the full input syllable
        let normalizedOriginal = syl.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullOne = ThaiSyllable(
            onset: one.onset,
            nucleus: one.nucleus,
            coda: one.coda,
            live: one.live,
            ipa: one.ipa,
            toneMark: one.toneMark,
            range: one.range,
            original: normalizedOriginal,
            start: one.start,
            end: one.end
        )

        let firstCons = firstConsonant(in: one.original)
        let consClass = consonantClassString(for: firstCons)
        let codaChar = one.coda?.first
        let live = isLiveByIPA(nucleus: one.nucleus, coda: codaChar)
        let toneMarkStr = one.toneMark.map(String.init) ?? ""
        let vlenIPA = ThaiIPA.ipaForVowel(nucleus: one.nucleus, coda: codaChar)
        let isLong = vlenIPA.contains("ː") || ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"].contains(vlenIPA)
        let toneStr = finnThaiTone(consonantClass: consClass, liveSyllable: live, ToneMark: toneMarkStr, lognVowel: isLong)
        let tone = toneEnum(from: toneStr)
        let toneMark = ThaiPhonetics.toneDiacritic(tone)

        return SyllableToneInfo(
            syllable: fullOne,
            consonantClass: consClass,
            isLive: live,
            isLongVowel: isLong,
            hasToneMark: !toneMarkStr.isEmpty,
            toneMarkChar: toneMarkStr,
            tone: tone,
            toneMark: toneMark
        )
    }

    private func mergeSyllables(_ syllables: [ThaiSyllable], originalText: String) -> ThaiSyllable {
        let last = syllables[syllables.count - 1]
        let first = syllables[0]
        return ThaiSyllable(
            onset: last.onset,
            nucleus: last.nucleus,
            coda: last.coda,
            live: last.live,
            ipa: last.ipa,
            toneMark: last.toneMark,
            range: first.range.lowerBound..<last.range.upperBound,
            original: originalText,
            start: first.start,
            end: last.end
        )
    }
}

 MARK: - Inline per-syllable  end */

// MARK: - TokenButton

public struct TokenButton: View {
    let token: String
    let englishWord: String?
    let existsInDB: Bool
    var isActive: Bool = false
    var onSelect: (() -> Void)? = nil
    let onOpenDetail: () -> Void
    var onCreateWord: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.managedObjectContext) private var moc
    @AppStorage("tokenButtonSpeechEnabled") private var speechEnabled = false
    @State private var showPopover = false
    @State private var showOrstDict = false
    @State private var showThaiLangDict = false
    @State private var popoverImageData: Data? = nil
    @State private var popoverThaiText: String? = nil
    @State private var popoverNotes: String? = nil

    private func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // Hentes kun når brukeren faktisk trykker på knappen — ingen prefetching for alle tokens.
    private func loadPopoverDetailsIfNeeded() {
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "thaiWord ==[c] %@", token)
        req.fetchLimit = 1
        if let match = try? moc.fetch(req).first {
            popoverImageData = match.image
            popoverThaiText = nonEmpty(match.translation1)
            popoverNotes = nonEmpty(match.notes)
            return
        }

        // Ikke eksakt treff — prøv norske bøyningskandidater (samme regler/fallback som
        // resten av visningen, se norwegianInflectionRules/undoubleFinalM), f.eks.
        // "programmet" -> "programm" (ugyldig, dobbel M) -> "program".
        let candidatesForToken = inflectionCandidates(for: token)
        for candidate in candidatesForToken {
            let candReq = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            candReq.predicate = NSPredicate(format: "thaiWord ==[c] %@", candidate)
            candReq.fetchLimit = 1
            if let match = try? moc.fetch(candReq).first {
                popoverImageData = match.image
                popoverThaiText = nonEmpty(match.translation1)
                popoverNotes = nonEmpty(match.notes)
                return
            }
        }

        popoverImageData = nil
        popoverThaiText = nil
        popoverNotes = nil

        // Ordet finnes ikke lokalt ennå (kun i tokenEnglishMap via gThai-speilet) — prøv samme
        // speil her også, inkludert bøyningskandidatene (samme som lokal-passet over). I gThai
        // sin database er translation1=norsk og thaiWord=ekte thaiskrift, så her bruker vi
        // treffets thaiWord som "Thai"-verdien, motsatt av det lokale oppslaget.
        for candidate in [token] + candidatesForToken {
            let mirrorReq = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            mirrorReq.predicate = NSPredicate(format: "translation1 ==[c] %@", candidate)
            mirrorReq.fetchLimit = 1
            if let mirrorMatch = try? GThaiReferenceStore.shared.context.fetch(mirrorReq).first {
                popoverThaiText = nonEmpty(mirrorMatch.thaiWord)
                popoverNotes = nonEmpty(mirrorMatch.notes)
                return
            }
        }
    }

    private func measuredHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let box = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        )
        return ceil(box.height)
    }

    private var estimatedPopoverSize: (width: CGFloat, height: CGFloat) {
        let titleText = englishWord ?? (existsInDB ? token : "Not in database")
        let titleFont = UIFont.preferredFont(forTextStyle: .title3)
        let bodyFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let thaiFont = bodyFont.withSize(bodyFont.pointSize * 2)
        let screenWidth = UIScreen.main.bounds.width
        let imageReserve: CGFloat = popoverImageData != nil ? 72 : 0  // 64 image + 8 spacing
        let hPadding: CGFloat = 12 + 48 + imageReserve  // leading + trailing (room for overlay button) + image
        let vPadding: CGFloat = 24
        let minHeight: CGFloat = popoverImageData != nil ? 64 + vPadding : 0
        let hasExtraFields = popoverThaiText != nil || popoverNotes != nil

        let narrowWidth: CGFloat = min(400, screenWidth - 32)
        let wideWidth: CGFloat = min(440, screenWidth - 32)

        let singleLineTitleWidth = ceil((titleText as NSString).size(withAttributes: [.font: titleFont]).width)

        let width: CGFloat = (!hasExtraFields && singleLineTitleWidth + hPadding <= narrowWidth)
            ? singleLineTitleWidth + hPadding
            : wideWidth

        let textWidth = width - hPadding
        var height = measuredHeight(titleText, font: titleFont, width: textWidth)
        if let thai = popoverThaiText {
            height += 8 + measuredHeight("Thai: \(thai)", font: thaiFont, width: textWidth)
        }
        if let notes = popoverNotes {
            height += 8 + measuredHeight("Notes: \(notes)", font: bodyFont, width: textWidth)
        }

        return (width, max(height + vPadding, minHeight))
    }

    public var body: some View {
        Button {
            onSelect?()
            loadPopoverDetailsIfNeeded()
            showPopover = true
            if speechEnabled { CloudTTSTest.speakNorsk(token) }
        } label: {
            Text(token)
                .font(.largeTitle)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(existsInDB ? Color(.quaternaryLabel) : Color.orange.opacity(0.25))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive ? Color.red :
                                (existsInDB ? Color.clear : Color.orange.opacity(0.6)),
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
            if !existsInDB, let create = onCreateWord {
                Button {
                    create()
                } label: {
                    Label("Create word", systemImage: "plus.circle.fill")
                }
                Divider()
            }
            Button {
                onSelect?()
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://ordbokene.no/nob/bm/\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Bokmålsordboka", systemImage: "globe.asia.australia")
            }
            Button {
                onSelect?()
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Thai2English", systemImage: "globe.asia.australia")
            }
            Button {
                onSelect?()
                showThaiLangDict = true
            } label: {
                Label("thai-language.com", systemImage: "character.book.closed")
            }
            Button {
                onSelect?()
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://dict.longdo.com/?search=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Longdo Dict", systemImage: "book.pages")
            }
            Button {
                onSelect?()
                showOrstDict = true
            } label: {
                Label("Royal Society Dictionary", systemImage: "text.book.closed")
            }
            Button {
                onSelect?()
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://forvo.com/search/\(encoded)/no/") {
                    openURL(url)
                }
            } label: {
                Label("Forvo", systemImage: "person.wave.2")
            }
            Button {
                onSelect?()
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://papago.naver.com/?sk=no&tk=th&st=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Papago", systemImage: "p.circle.fill")
            }
            Button {
                onSelect?()
                openGoogleTranslate(token, targetLang: "th", using: openURL)
            } label: {
                Label("Google Translate", systemImage: "g.circle.fill")
            }
        }
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 8) {
                    if let data = popoverImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(englishWord ?? (existsInDB ? token : "Not in database"))
                            .font(.title3)
                        if let thai = popoverThaiText {
                            let bodyFont = UIFont.preferredFont(forTextStyle: .subheadline)
                            Text("Thai: \(thai)")
                                .font(Font(bodyFont.withSize(bodyFont.pointSize * 2)))
                                .foregroundStyle(.secondary)
                        }
                        if let notes = popoverNotes {
                            Text("Notes: \(notes)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12)
                .padding(.trailing, 48)
                .padding(.vertical, 12)
                Button {
                    if existsInDB {
                        showPopover = false
                        onOpenDetail()
                    } else {
                        UIPasteboard.general.string = token
                        Notifier.shared.show(.success, "Copied to clipboard")
                    }
                } label: {
                    Image(systemName: existsInDB ? "arrow.up.right.circle" : "doc.on.doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 8)
            }
            #if targetEnvironment(macCatalyst)
            .frame(width: estimatedPopoverSize.width, height: estimatedPopoverSize.height)
            .presentationCompactAdaptation(.popover)
            #else
            .presentationDetents([.height(estimatedPopoverSize.height)])
            #endif
        }
        .fullScreenCover(isPresented: $showOrstDict) {
            OrstDictionaryView(word: token)
        }
        .fullScreenCover(isPresented: $showThaiLangDict) {
            ThaiLanguageDictionaryView(word: token)
        }
    }
}
