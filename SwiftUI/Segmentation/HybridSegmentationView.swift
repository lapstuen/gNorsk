import SwiftUI
import Foundation
import AVFoundation
import CoreData
import Dispatch
import NaturalLanguage

struct HybridSegmentationPipeline {
    static func run(text: String, context: NSManagedObjectContext, ignorePrecomputedSyllables: Bool, useAppleNLWordPreprocess: Bool) -> (hits: [WordHit], debugTokens: [String]) {
        // Local helpers re-implemented here because instance methods cannot be called without an instance.
        
        // MARK: - Helpers
        
        func sanitizeThai(_ s: String) -> String {
            var cleaned = s
            // Remove common zero-width characters
            let zeroWidth = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]
            for zw in zeroWidth {
                cleaned = cleaned.replacingOccurrences(of: zw, with: "")
            }
            // Remove regular whitespace/newlines
            cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines).joined()
            // Normalize composition
            return cleaned.precomposedStringWithCanonicalMapping
        }
        
        func appleNLWordTokens(from text: String) -> [String] {
            let t = text.precomposedStringWithCanonicalMapping
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = t
            var tokens: [String] = []
            tokenizer.enumerateTokens(in: t.startIndex..<t.endIndex) { range, _ in
                let token = String(t[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { tokens.append(token) }
                return true
            }
            return tokens
        }
        
        func existsInDatabase(thai: String) -> Bool {
            let key = sanitizeThai(thai)
            guard !key.isEmpty else { return false }
            let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            request.predicate = NSPredicate(format: "thaiWord == %@", key)
            request.fetchLimit = 1
            do {
                let count = try context.count(for: request)
                return count > 0
            } catch {
                print("❌ existsInDatabase error for \(thai) [sanitized=\(key)]: \(error)")
                return false
            }
        }
        
        func strictExistsInDatabase(thai: String) -> Bool {
            let key = sanitizeThai(thai)
            guard !key.isEmpty else { return false }
            let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            request.predicate = NSPredicate(format: "thaiWord == %@", key)
            request.fetchLimit = 1
            do {
                let count = try context.count(for: request)
                return count > 0
            } catch {
                print("❌ strictExistsInDatabase error for \(thai) [sanitized=\(key)]: \(error)")
                return false
            }
        }
        
        func englishForThai(_ thai: String) -> String? {
            let key = sanitizeThai(thai)
            guard !key.isEmpty else { return nil }
            // Try Core Data first
            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate = NSPredicate(format: "thaiWord == %@", key)
            req.fetchLimit = 1
            if let found = try? context.fetch(req).first {
                if let eng = found.englishWord, !eng.isEmpty {
                    return eng.components(separatedBy: ";").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                }
                // englishWord tom på akkurat dette treffet (i vår kopi av gThai-databasen) —
                // translation1 er norsk i gThai sin database, bruk den som fallback-glose.
                if let norsk = found.translation1, !norsk.isEmpty {
                    return norsk.components(separatedBy: ";").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                }
            }
            // Fallback to ThaiLexicon
            let lex = ThaiLexicon.resolveEnglish(key)
            if lex != "—" {
                return lex.components(separatedBy: ";").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            return nil
        }
        
        func splitTokenIfUnknown(_ token: WordHit) -> [WordHit] {
            if englishForThai(token.thai) != nil { return [token] }
            var queue: [String] = [token.thai]
            var output: [WordHit] = []
            
            while !queue.isEmpty {
                let current = queue.removeFirst()
                if englishForThai(current) != nil {
                    output.append(WordHit(thai: current, english: englishForThai(current), children: nil))
                    continue
                }
                var splitFound = false
                if current.count > 1 {
                    for idx in 1..<(current.count) {
                        let left = String(current.prefix(idx))
                        let right = String(current.suffix(current.count - idx))
                        if englishForThai(left) != nil && englishForThai(right) != nil {
                            queue.insert(right, at: 0)
                            queue.insert(left, at: 0)
                            splitFound = true
                            break
                        }
                    }
                }
                if !splitFound {
                    output.append(WordHit(thai: current, english: englishForThai(current), children: nil))
                }
            }
            return output
        }
        
        func stripPoliteness(_ word: String) -> String {
            let suffixes = ["คะ", "ค่ะ", "ครับ"]
            for suffix in suffixes {
                if word.hasSuffix(suffix) {
                    return String(word.dropLast(suffix.count))
                }
            }
            if word.hasSuffix("ค") {
                return String(word.dropLast(1))
            }
            return word
        }
        
        func dictionaryMerge(_ hits: [WordHit]) -> [WordHit] {
            guard !hits.isEmpty else { return hits }
            var result: [WordHit] = []
            var i = 0
            let maxWindow = 6
            
            while i < hits.count {
                var merged: WordHit? = nil
                let remaining = hits.count - i
                let windowUpper = min(maxWindow, remaining)
                
                if windowUpper > 1 {
                    for window in stride(from: windowUpper, through: 2, by: -1) {
                        let slice = hits[i..<(i+window)]
                        let combined = slice.map { $0.thai }.joined()
                        if window == 2 {
                            let parts = slice.map { $0.thai }
                            let left = parts[0]
                            let right = parts[1]
                            let leftStrong = existsInDatabase(thai: left) || (ThaiLexicon.resolveEnglish(left) != "—")
                            let rightStrong = existsInDatabase(thai: right) || (ThaiLexicon.resolveEnglish(right) != "—")
                            if leftStrong && rightStrong {
                                continue
                            }
                        }
                        let base = stripPoliteness(combined)
                        let baseExists = strictExistsInDatabase(thai: base)
                        let combinedExists = strictExistsInDatabase(thai: combined)
                        if baseExists {
                            let eng = englishForThai(base)
                            merged = WordHit(thai: base, english: eng, children: nil)
                            i += window
                            break
                        } else if combinedExists {
                            let eng = englishForThai(combined)
                            merged = WordHit(thai: combined, english: eng, children: nil)
                            i += window
                            break
                        }
                    }
                }
                
                if let m = merged {
                    result.append(m)
                } else {
                    result.append(hits[i])
                    i += 1
                }
            }
            return result
        }
        
        func postProcess(_ hits: [WordHit]) -> [WordHit] {
            guard !hits.isEmpty else { return hits }

            // Helper to decide if a child is a leaf (no deeper children)
            func isLeaf(_ h: WordHit) -> Bool { h.children == nil || h.children?.isEmpty == true }
            func isShort(_ s: String) -> Bool { s.count <= 2 }

            var processedTopLevel: [WordHit] = []

            for top in hits {
                // Only process children; do NOT merge at top-level
                guard let children = top.children, !children.isEmpty else {
                    processedTopLevel.append(top)
                    continue
                }

                var newChildren: [WordHit] = []
                var i = 0

                while i < children.count {
                    if i + 1 < children.count {
                        let a = children[i]
                        let b = children[i + 1]
                        let aIsLeaf = isLeaf(a)
                        let bIsLeaf = isLeaf(b)

                        print("[postProcess-children] Considering pair: \(a.thai) (leaf=\(aIsLeaf)) + \(b.thai) (leaf=\(bIsLeaf))")

                        if aIsLeaf && bIsLeaf {
                            let aStrong = existsInDatabase(thai: a.thai) || (ThaiLexicon.resolveEnglish(a.thai) != "—")
                            let bStrong = existsInDatabase(thai: b.thai) || (ThaiLexicon.resolveEnglish(b.thai) != "—")
                            let aRed = !aStrong
                            let bRed = !bStrong
                            print("[postProcess-children] Strength: aStrong=\(aStrong), bStrong=\(bStrong) -> aRed=\(aRed), bRed=\(bRed)")

                            // Merge when left is red (not found), even if right is green
                            if aRed {
                                let combinedThai = a.thai + b.thai
                                let combinedBase = stripPoliteness(combinedThai)
                                let exists = strictExistsInDatabase(thai: combinedBase)
                                print("[postProcess-children] Try merge (red+red): combined='\(combinedThai)' base='\(combinedBase)' existsInDB=\(exists)")

                                if exists {
                                    var englishShort: String? = nil
                                    do {
                                        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
                                        request.predicate = NSPredicate(format: "thaiWord == %@", combinedBase)
                                        request.fetchLimit = 1
                                        if let found = try context.fetch(request).first, let eng = found.englishWord, !eng.isEmpty {
                                            englishShort = eng.components(separatedBy: ";").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                        }
                                    } catch {
                                        print("⚠️ postProcess-children lookup failed for \(combinedBase): \(error)")
                                    }

                                    print("[postProcess-children] MERGE OK -> '\(combinedBase)' english='\(englishShort ?? "nil")'")
                                    let merged = WordHit(
                                        thai: combinedBase,
                                        english: englishShort,
                                        children: nil
                                    )
                                    newChildren.append(merged)
                                    i += 2
                                    continue
                                }
                            }
                        }
                    }
                    print("[postProcess-children] No merge at child i=\(i). Keeping '" + children[i].thai + "'")
                    newChildren.append(children[i])
                    i += 1
                }

                // Rebuild the top item with updated children
                let updatedTop = WordHit(thai: top.thai, english: top.english, children: newChildren)
                processedTopLevel.append(updatedTop)
            }

            // Preserve special-case top-level repair for the very end only
            if processedTopLevel.count >= 2 {
                let lastIndex = processedTopLevel.count - 1
                let penultimateIndex = lastIndex - 1
                let a = processedTopLevel[penultimateIndex]
                let b = processedTopLevel[lastIndex]

                if a.thai == "อะ" && b.thai.hasPrefix("ไร") {
                    let repaired = "อะไร"
                    let lex = ThaiLexicon.resolveEnglish(repaired)
                    let hasLex = (lex != "—")
                    let lookup = ThaiNLPData.lookup(repaired, context: context)
                    let hasIPAOrPre = (lookup.isPreComputed && !lookup.syllables.isEmpty) || (!lookup.ipa.isEmpty && !lookup.ipa.contains("NoJson"))
                    if hasLex || hasIPAOrPre {
                        print("[postProcess] Special repair: 'อะ' + 'ไร*' -> 'อะไร' (accepted)")
                        var newResult = processedTopLevel
                        newResult.removeLast(2)
                        let englishShort = hasLex ? lex.components(separatedBy: ";").first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) : nil
                        let merged = WordHit(thai: repaired, english: englishShort, children: nil)
                        newResult.append(merged)
                        return newResult
                    }
                }
            }

            return processedTopLevel
        }
        
        // Start pipeline (Option 1: Use Apple NLTokenizer as primary segmenter)
        // KNOWN LIMITATION: Apple NLTokenizer does not know all Thai compound words.
        // Example: "เกียดคร้าน" is split into เกีย + ด + คร้าน instead of one token.
        // Fix if this becomes a problem: after getting nlTokens, run a merge pass that
        // checks if consecutive tokens concatenated exist in the Core Data DB, and merges them.
        let nlTokens: [String] = appleNLWordTokens(from: text)
        // Map NL tokens into initial WordHit array with english if available
        let initialHits: [WordHit] = nlTokens.map { token in
            WordHit(thai: token, english: englishForThai(token), children: nil)
        }
        // Keep debug tokens aligned with the actual tokenization used
        let debugTokens: [String] = nlTokens

        // Use NL tokens directly as top-level hits (no additional merging for now)
        let pass1 = initialHits

        // Enrich with precomputed syllables and preserve hierarchy
        // Top level: longest words (pass1)
        // If a word is a compound (splitTokenIfUnknown created multiple pieces earlier), keep its children as component words.
        // For each leaf (no children), attach syllables as a deeper level if available and not ignored.
        let enriched: [WordHit] = pass1.map { hit in
            // If this hit already has children (e.g., components), recurse to enrich their syllables
            if let children = hit.children, !children.isEmpty {
                let enrichedChildren = children.map { child -> WordHit in
                    // For each child, if it has no children, try to attach syllables
                    if child.children == nil || child.children?.isEmpty == true {
                        // Direct sync read of word.syllables — same field as ThaiNLPData.lookup, no semaphore/deadlock risk
                        let sylls: [String]
                        if !ignorePrecomputedSyllables {
                            sylls = syllablesFromCoreData(for: child.thai, context: context)
                                ?? ThaiSeg.segmentWordIntoSyllables(child.thai).map { $0.original }
                        } else {
                            sylls = ThaiSeg.segmentWordIntoSyllables(child.thai).map { $0.original }
                        }
                        if sylls.count > 1 {
                            let syllableChildren: [WordHit] = sylls.map { s in
                                WordHit(thai: s, english: englishForThai(s), children: nil)
                            }
                            return WordHit(thai: child.thai, english: child.english, children: syllableChildren)
                        }
                        return child
                    } else {
                        // If child already has children, leave it as-is for now (or recurse further if needed)
                        return child
                    }
                }
                return WordHit(thai: hit.thai, english: hit.english, children: enrichedChildren)
            } else {
                // Leaf at top level: direct sync read of word.syllables — same field as ThaiNLPData.lookup, no semaphore/deadlock risk
                let sylls: [String]
                if !ignorePrecomputedSyllables {
                    sylls = syllablesFromCoreData(for: hit.thai, context: context)
                        ?? ThaiSeg.segmentWordIntoSyllables(hit.thai).map { $0.original }
                } else {
                    sylls = ThaiSeg.segmentWordIntoSyllables(hit.thai).map { $0.original }
                }
                if sylls.count > 1 {
                    let syllableChildren: [WordHit] = sylls.map { s in
                        WordHit(thai: s, english: englishForThai(s), children: nil)
                    }
                    return WordHit(thai: hit.thai, english: hit.english, children: syllableChildren)
                }
                return hit
            }
        }
        // Do NOT flatten here. Preserve hierarchy for UI so chevron expansion works.
        // If you want additional post-processing on leaves, it should be done without destroying the tree.
        // For now, return enriched directly.
        let postProcessed = postProcess(enriched)
        return (postProcessed, debugTokens)
    }
}

struct SegmentedListView: View {
    let hits: [WordHit]
    @Binding var speakingWord: String?
    @Binding var expandedHits: Set<UUID>
    let existsInDB: (String) -> Bool
    let onSpeak: (String) -> Void
    let onWordTap: (WordHit) -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                VStack(alignment: .leading, spacing: 4) {
                    let childrenJoined = hit.children?.map { $0.thai }.joined()
                    let hasCharMismatch: Bool = {
                        guard let joined = childrenJoined else { return false }
                        let norm1 = hit.thai.precomposedStringWithCanonicalMapping
                        let norm2 = joined.precomposedStringWithCanonicalMapping
                        return norm1 != norm2
                    }()
                        WordRowView(
                            hit: hit,
                            speakingWord: $speakingWord,
                            isExpanded: expandedHits.contains(hit.id),
                            hasChildren: hit.children != nil,
                        isChild: false,
                        existsInDB: existsInDB(hit.thai),
                        hasCharMismatch: hasCharMismatch,
                            onToggleExpand: {
                                if expandedHits.contains(hit.id) {
                                    expandedHits.remove(hit.id)
                                } else {
                                    expandedHits.insert(hit.id)
                                }
                            },
                        onWordTap: onWordTap,
                        onSpeakTap: { onSpeak($0) }
                    )
                    
                    if expandedHits.contains(hit.id), let children = hit.children {
                        ForEach(Array(children.enumerated()), id: \.element.id) { childIndex, child in
                            WordRowView(
                                hit: child,
                                speakingWord: $speakingWord,
                                isExpanded: false,
                                hasChildren: false,
                                isChild: true,
                                existsInDB: existsInDB(child.thai),
                                hasCharMismatch: false,
                                onToggleExpand: {},
                                onWordTap: onWordTap,
                                onSpeakTap: { onSpeak($0) }
                            )
                            .padding(.leading, 24)
                        }
                    }
                }
                .id(hit.id)
            }
        }
    }
}

struct HybridSegmentationView: View {
    let text: String
    @Environment(\.managedObjectContext) private var context
    // Kun for lesing av thai-oppslag (IPA, oversettelse, "finnes i db") — gNorsk sin egen
    // thaiWord-kolonne inneholder norsk, ikke thai. `context` over brukes fortsatt til lagring
    // (CreateWordView/AdminToolsView/DetailWordView2) — den skal ALDRI erstattes med speilet.
    private var gThaiLookupContext: NSManagedObjectContext { GThaiReferenceStore.shared.context }
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var wordHits: [WordHit] = []
    @State private var speakingWord: String? = nil
    @State private var selectedWord: WordHit? = nil
    @State private var showingWordDetail = false
    @State private var showingPronounceChecker = false
    @State private var selectedWordForPronunciation: String? = nil
    @State private var expandedHits: Set<UUID> = []
    @State private var showingAdminTools = false
    @State private var debugWordTokens: [String] = []
    @State private var useAppleNLWordPreprocess = false
    @State private var isSegmenting = false
    @State private var selectedDetailWordInput: WordInput? = nil

    private func sanitizeThai(_ s: String) -> String {
        var cleaned = s
        let zeroWidth = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]
        for zw in zeroWidth {
            cleaned = cleaned.replacingOccurrences(of: zw, with: "")
        }
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines).joined()
        return cleaned.precomposedStringWithCanonicalMapping
    }
    
    private func appleNLWordTokens(from text: String) -> [String] {
        let t = text.precomposedStringWithCanonicalMapping
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = t
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: t.startIndex..<t.endIndex) { range, _ in
            let token = String(t[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { tokens.append(token) }
            return true
        }
        return tokens
    }
    
    private func existsInDatabase(thai: String) -> Bool {
        let key = sanitizeThai(thai)
        guard !key.isEmpty else { return false }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord == %@", key)
        request.fetchLimit = 1
        do {
            let count = try gThaiLookupContext.count(for: request)
            return count > 0
        } catch {
            print("❌ existsInDatabase error for \(thai) [sanitized=\(key)]: \(error)")
            return false
        }
    }

    private func fetchExistingWord(thaiWord: String) -> ThaiWords? {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord == %@", sanitizeThai(thaiWord))
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func detailWordInput(for hit: WordHit) -> WordInput {
        if let existingWord = fetchExistingWord(thaiWord: hit.thai) {
            return WordInput(from: existingWord)
        }

        let resolvedEnglish = hit.english ?? {
            let lex = ThaiLexicon.resolveEnglish(hit.thai)
            return lex == "—" ? "" : lex
        }()

        return WordInput(
            objectID: nil,
            thaiWord: hit.thai,
            englishWord: resolvedEnglish,
            ipa: "",
            sentence: "",
            tags: "",
            image: nil,
            uuid: UUID(),
            translation1: "",
            translation2: ""
        )
    }

    private func speakWord(_ word: String) {
        speakingWord = word
        Task {
            var didSpeak = false
            do {
                try await CloudTTSTest.testGoogleTTS(word, languageCode: "th-TH")
                didSpeak = true
                print("🔊 Spoke via CloudTTSTest for: \(word)")
            } catch {
                print("❌ Cloud TTS feil: \(error)")
                #if canImport(AVFoundation)
                if let _ = Optional(g as Any) {
                    g.talkTh(talkText: word, rate: 0.5, language: "th-TH")
                    didSpeak = true
                    print("🔊 Spoke via global g.talkTh for: \(word)")
                }
                if !didSpeak {
                    let utterance = AVSpeechUtterance(string: word)
                    utterance.voice = AVSpeechSynthesisVoice(language: "th-TH")
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                    AVSpeechSynthesizer().speak(utterance)
                    didSpeak = true
                    print("🔊 Spoke via AVSpeechSynthesizer fallback for: \(word)")
                }
                #endif
            }
            await MainActor.run {
                speakingWord = nil
            }
        }
    }

    func performSegmentation() {
        if isSegmenting { return }
        print("[Seg] start text='\(text)' useApple=\(useAppleNLWordPreprocess) thread=\(Thread.isMainThread ? "main" : "bg")")
        isSegmenting = true
        let currentText = text
        let currentUseApple = useAppleNLWordPreprocess
        let currentContext = gThaiLookupContext
        DispatchQueue.global(qos: .userInitiated).async {
            print("[Seg] run pipeline on bg thread")
            let (hits, debugTokens) = HybridSegmentationPipeline.run(
                text: currentText,
                context: currentContext,
                ignorePrecomputedSyllables: false,
                useAppleNLWordPreprocess: currentUseApple
            )
            DispatchQueue.main.async {
                print("[Seg] finish hits=\(hits.count) tokens=\(debugTokens.count) thread=\(Thread.isMainThread ? "main" : "bg")")
                self.debugWordTokens = debugTokens
                self.wordHits = hits
                self.expandedHits.removeAll()
                self.isSegmenting = false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header: original text and debug tokens (non-scrollable)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opprinnelig tekst:").font(.caption).foregroundColor(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 8) {
                            Button(action: {
                                speakWord(text)
                            }) {
                                Image(systemName: speakingWord == text ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .foregroundColor(speakingWord == text ? .blue : .secondary)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            .disabled(speakingWord != nil)

                            Button(action: {
                                selectedWordForPronunciation = nil
                                showingPronounceChecker = true
                            }) {
                                Image(systemName: "mic.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(text)
                            .font(.title3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(debugWordTokens.indices, id: \.self) { i in
                                    let token = debugWordTokens[i]
                                    Button {
                                        // Select immediately without heavy work
                                        selectedWord = WordHit(thai: token, english: nil, children: nil)

                                        // Present shortly after (next runloop-ish)
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 250_000_000) // ~10ms defer
                                            if selectedWord?.thai == token {
                                                showingWordDetail = true
                                            }
                                        }

                                        // Resolve English off the main thread, then update
                                        Task.detached {
                                            let eng = ThaiLexicon.resolveEnglish(token)
                                            let english = (eng != "—") ? eng : nil
                                            await MainActor.run {
                                                if selectedWord?.thai == token {
                                                    selectedWord = WordHit(thai: token, english: english, children: nil)
                                                }
                                            }
                                        }
                                    } label: {
                                        Text(token)
                                            .font(.callout)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(.quaternaryLabel))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            if showingWordDetail {
                                
                                VStack {
                                    let word = selectedWord?.thai ?? ""
                                    let norwegian: String = word.isEmpty ? "" : g.getNorwegian(thaiWord: word)

                                    // Hent engelsk kortform (første definisjon) hvis finnes
                                    let englishFull = word.isEmpty ? "—" : ThaiLexicon.resolveEnglish(word)
                                    let englishShort: String = {
                                        guard englishFull != "—" else { return "" }
                                        return englishFull.components(separatedBy: ";")
                                            .first?
                                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    }()

                                    if !word.isEmpty {
                                        
                                        VStack  {
                                            
                                            Text(" \(word) ").font(.largeTitle)
                                        
                                        Text("EN: \(englishShort.isEmpty ? "—" : englishShort) • NO: \(norwegian.isEmpty ? "—" : norwegian)")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        }
                                    }
                                
                                    
                                    
                                //Text("Detalj for ordet \(selectedWord!.thai) .. \(norwegian)").font(.caption).foregroundColor(.secondary)
                                    
                                    
                                
                                HStack(spacing: 20) {


                                    let norwegian: String = {
                                        let word = selectedWord?.thai ?? ""
                                        guard !word.isEmpty else { return "" }
                                        return g.getNorwegian(thaiWord: word)
                                    }()


                                 //       .font(.headline)
                                    Spacer()

                                    Button(action: {
                                        showingPronounceChecker = true
                                    }) {
                                        Image(systemName: "mic.circle.fill")
                                            .font(.system(size: 28))
                                    }
                                    //.buttonStyle(.bordered)
                                    .buttonStyle(FlashIconButtonStyle())

                                    Button(action: {
                                        print("🔊 Speaking (detail sheet): '\(selectedWord!.thai)'")
                                        Task {
                                            var didSpeak = false
                                            do {
                                                try await CloudTTSTest.testGoogleTTS(selectedWord!.thai)
                                                didSpeak = true
                                                print("🔊 Spoke via CloudTTSTest (detail sheet) for: \(selectedWord!.thai)")
                                            } catch {
                                                print("❌ TTS error (detail sheet): \(error)")
                                                #if canImport(AVFoundation)
                                                if let _ = Optional(g as Any) {
                                                    g.talkTh(talkText: selectedWord!.thai, rate: 0.5, language: "th-TH")
                                                    didSpeak = true
                                                    print("🔊 Spoke via global g.talkTh (detail sheet) for: \(selectedWord!.thai)")
                                                }
                                                if !didSpeak {
                                                    let utterance = AVSpeechUtterance(string: selectedWord!.thai)
                                                    utterance.voice = AVSpeechSynthesisVoice(language: "th-TH")
                                                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                                                    AVSpeechSynthesizer().speak(utterance)
                                                    didSpeak = true
                                                    print("🔊 Spoke via AVSpeechSynthesizer fallback (detail sheet) for: \(selectedWord!.thai)")
                                                }
                                                #endif
                                            }
                                        }
                                    }) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.system(size: 28))
                                    }
                                    .buttonStyle(FlashIconButtonStyle())

                                    Button {
                                        UIPasteboard.general.string = selectedWord!.thai
                                    } label: {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 28))
                                    }
                                    .buttonStyle(FlashIconButtonStyle())


                                    let openThai2English: (String) -> Void = { text in
                                        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                              let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") else { return }
                                        openURL(url)
                                    }

                                    Button {
                                        if let word = selectedWord?.thai, !word.isEmpty {
                                            openThai2English(word)
                                        }
                                    } label: {
                                        Image(systemName: "safari")
                                            .font(.system(size: 28))
                                    }
                                    .buttonStyle(FlashIconButtonStyle())
                                    
                                    
                                    Spacer()
                                  
                                }
                                }
                            }
                        }
                    }
                }

                Divider()

                // Segmented list area: its own scrollable region with fixed overlay
                VStack(alignment: .leading, spacing: 12) {
                    Text("Segmenterte deleryy:").font(.headline)

                    ScrollView {
                        SegmentedListView(
                            hits: wordHits,
                            speakingWord: $speakingWord,
                            expandedHits: $expandedHits,
                            existsInDB: { existsInDatabase(thai: $0) },
                            onSpeak: { speakWord($0) },
                            onWordTap: { hit in
                                selectedDetailWordInput = detailWordInput(for: hit)
                            }
                        )
                        .onTapGesture { }
                        .onChange(of: wordHits.map { $0.id }) { _ in
                            expandedHits.removeAll()
                        }
                        .id("SegmentedListRoot")
                        .padding(.trailing, 0)
                    }
                }
                .frame(minHeight: 400) // make sure the list area has a visible height

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .navigationTitle("Hybrid Segmentering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        
                       dismiss()
                       
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(action: { performSegmentation() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showingAdminTools = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text("")
                        }
                    }
                    .buttonStyle(.bordered)

                //    Toggle(isOn: $useAppleNLWordPreprocess) {
                //        Text("AppleNL")
                //    }
                //    .toggleStyle(.switch)
                //    .onChange(of: useAppleNLWordPreprocess) { _, _ in
                //        performSegmentation()
                //    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 700)
        .onAppear {
            print("[View] HybridSegmentationView onAppear")
            CoreDataWriteMonitor.shared.startMonitoring()
            DispatchQueue.main.async { performSegmentation() }
        }
        .onChange(of: text) { _, _ in
            print("[View] onChange(text) -> performSegmentation")
            performSegmentation()
        }
 //       .sheet(isPresented: $showingWordDetail) {
 //     //      print("[Sheet] showingWordDetail presented. selectedWord=\(String(describing: selectedWord?.thai))")
 //           if let word = selectedWord {
 //               WordDetailView(wordHit: word)
 //                   .environment(appState)
 //           } else {
 //               EmptyView()
 //           }
 //       }
        .sheet(isPresented: $showingPronounceChecker) {
            if let targetWord = selectedWordForPronunciation {
                ThaiPronounceCheckView(target: targetWord)
            } else {
                ThaiPronounceCheckView(target: text)
            }
        }
        .sheet(isPresented: $showingAdminTools) {
            AdminToolsView()
                .environment(\.managedObjectContext, context)
        }
        .sheet(item: $selectedDetailWordInput) { input in
            DetailWordView2(initialWord: input, isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .wireNotifications()
    }
}

struct MiniListScroller: View {
    let total: Int
    let onJump: (Double) -> Void
    @State private var percent: Double = 0.0

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: $percent, in: 0...1, step: 0.01)
                .rotationEffect(.degrees(-90))
                .frame(maxHeight: .infinity)
                .padding(.vertical, 4)
                .onChange(of: percent) { _, newVal in
                    onJump(newVal)
                }
        }
    }
}

// MARK: - Word Detail Sheet
struct WordDetailSheet: View {
    let hit: WordHit
    let precomputedIPA: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    // Kun for lesing av thai-oppslag — se kommentar i HybridSegmentationView. `context` brukes
    // fortsatt til lagring (CreateWordView) og skal ALDRI erstattes med speilet.
    private var gThaiLookupContext: NSManagedObjectContext { GThaiReferenceStore.shared.context }
    @Environment(AppState.self) private var appState
    @State private var syllables: [ThaiSyllable] = []
    @State private var syllableTranslations: [String] = []
    @State private var isFromPyThaiNLP: Bool = true
    @State private var showingPronounceChecker = false
    @State private var showingCreateWord = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("XXXX Orddetaljer")
                    .font(.headline)
                Spacer()

                Button(action: {
                    showingPronounceChecker = true
                }) {
                    Image(systemName: "mic.circle.fill")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    print("🔊 Speaking (detail sheet): '\(hit.thai)'")
                    Task {
                        var didSpeak = false
                        do {
                            try await CloudTTSTest.testGoogleTTS(hit.thai)
                            didSpeak = true
                            print("🔊 Spoke via CloudTTSTest (detail sheet) for: \(hit.thai)")
                        } catch {
                            print("❌ TTS error (detail sheet): \(error)")
                            #if canImport(AVFoundation)
                            if let _ = Optional(g as Any) {
                                g.talkTh(talkText: hit.thai, rate: 0.5, language: "th-TH")
                                didSpeak = true
                                print("🔊 Spoke via global g.talkTh (detail sheet) for: \(hit.thai)")
                            }
                            if !didSpeak {
                                let utterance = AVSpeechUtterance(string: hit.thai)
                                utterance.voice = AVSpeechSynthesisVoice(language: "th-TH")
                                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                                AVSpeechSynthesizer().speak(utterance)
                                didSpeak = true
                                print("🔊 Spoke via AVSpeechSynthesizer fallback (detail sheet) for: \(hit.thai)")
                            }
                            #endif
                        }
                    }
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemGray6))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(hit.thai)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("IPA:")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(precomputedIPA)
                            .font(.title3)
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Oversettelser:")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if let english = hit.english {
                            let lines = english.components(separatedBy: ";")
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(width: 30, alignment: .leading)

                                    Text(line.trimmingCharacters(in: .whitespaces))
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No translation available")
                                    .font(.body)
                                    .foregroundColor(.red)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Forslag:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    VStack(spacing: 8) {
                                        HStack(spacing: 12) {
                                            Button {
                                                lookupInChatGPT(word: hit.thai)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "brain")
                                                    Text("ChatGPT")
                                                }
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.green.opacity(0.2))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                copyWordAndShowInstruction(word: hit.thai)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "doc.on.clipboard")
                                                    Text("Copy word")
                                                }
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        Button {
                                            showingCreateWord = true
                                        } label: {
                                            HStack {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Create new word")
                                            }
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.2))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stavelse-analyse:")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if !syllables.isEmpty {
                            ForEach(Array(syllables.enumerated()), id: \.offset) { index, syllable in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text(syllable.original)
                                                .font(.system(size: 28, weight: .bold))
                                                .foregroundColor(.primary)

                                            Button(action: {
                                                speakNorsk(syllable.original)
                                            }) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: {
                                                copySyllableToClipboard(syllable.original)
                                            }) {
                                                Image(systemName: "doc.on.clipboard")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                            .buttonStyle(.plain)

                                            Circle()
                                                .fill(syllable.live ? Color.green : Color.red)
                                                .frame(width: 12, height: 12)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(ipaForSyllable(syllable))
                                                .font(.body)
                                                .foregroundColor(.purple)

                                            if index < syllableTranslations.count {
                                                Text(syllableTranslations[index])
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }

                                    if !isFromPyThaiNLP && !syllable.onset.isEmpty {
                                        HStack(spacing: 8) {
                                            VStack(alignment: .center, spacing: 2) {
                                                Text("ONSET")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(syllable.onset)
                                                    .font(.body)
                                                    .foregroundColor(consonantClassColor(for: syllable.onset))
                                            }
                                            .frame(maxWidth: .infinity)

                                            VStack(alignment: .center, spacing: 2) {
                                                Text("VOKAL")
                                                    .font(.caption2)
                                                    .fontWeight(isLongVowel(syllable.nucleus) ? .bold : .regular)
                                                    .foregroundColor(.secondary)
                                                Text(fullVowelString(for: syllable))
                                                    .font(.body)
                                            }
                                            .frame(maxWidth: .infinity)

                                            VStack(alignment: .center, spacing: 2) {
                                                Text("CODA")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text(syllable.coda != nil ? String(syllable.coda!) : "")
                                                    .font(.body)
                                            }
                                            .frame(maxWidth: .infinity)

                                            VStack(alignment: .center, spacing: 2) {
                                                Text("LIVE")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Circle()
                                                    .fill(syllable.live ? Color.green : Color.red)
                                                    .frame(width: 8, height: 8)
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Text("Laster stavelser...")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .background(Color(.systemBackground))
        .onAppear {
            let result = ThaiNLPData.lookup(hit.thai, context: gThaiLookupContext)
            isFromPyThaiNLP = result.isPreComputed
            if result.isPreComputed && !result.syllables.isEmpty {
                print("✅ Using pre-computed syllables from Python NLP: \(result.syllables)")
                syllables = result.syllables.map { syllableText in
                    ThaiSyllable(
                        onset: "",
                        nucleus: syllableText,
                        coda: nil,
                        live: true,
                        ipa: nil,
                        toneMark: nil,
                        range: 0..<syllableText.count,
                        original: syllableText,
                        start: 0,
                        end: syllableText.count
                    )
                }
            } else {
                print("⚠️ No pre-computed data - using ThaiSeg fallback")
                syllables = ThaiSeg.segmentWordIntoSyllables(hit.thai)
            }
            syllableTranslations = syllables.map { syllable in
                let english = ThaiLexicon.resolveEnglish(syllable.original)
                return english == "—" ? "—" : english
            }
            if result.isPreComputed && (result.ipa.isEmpty || result.ipa.contains("NoJson") || result.ipa == "—") {
                syllables = syllables.map { syllable in
                    if let syllableIPA = fetchIPAForSyllable(syllable.original, context: gThaiLookupContext) {
                        return ThaiSyllable(
                            onset: syllable.onset,
                            nucleus: syllable.nucleus,
                            coda: syllable.coda,
                            live: syllable.live,
                            ipa: syllableIPA,
                            toneMark: syllable.toneMark,
                            range: syllable.range,
                            original: syllable.original,
                            start: syllable.start,
                            end: syllable.end
                        )
                    }
                    return syllable
                }
            }
        }
        .sheet(isPresented: $showingPronounceChecker) {
            ThaiPronounceCheckView(target: hit.thai)
        }
        .sheet(isPresented: $showingCreateWord) {
            NavigationStack {
                CreateWordView(
                    initialThaiWord: hit.thai,
                    overrideGroupId: AppState.autoCreatedWordsGroupId
                )
                .environment(appState)
                .environment(\.managedObjectContext, context)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingCreateWord = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .wireNotifications()
    }

    private func copyToClipboard() {
        var text = ""
        text += "Thai: \(hit.thai)\n\n"
        text += "IPA: \(precomputedIPA)\n\n"
        if let english = hit.english {
            text += "Oversettelser:\n"
            let lines = english.components(separatedBy: ";")
            for (index, line) in lines.enumerated() {
                text += "\(index + 1). \(line.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            }
            text += "\n"
        }
        text += "Stavelse-analyse:\n\n"
        for (index, syllable) in syllables.enumerated() {
            text += "Stavelse \(index + 1): \(syllable.original)\n"
            text += "  IPA: \(ipaForSyllable(syllable))\n"
            text += "  Onset: \(syllable.onset)\n"
            text += "  Nucleus: \(syllable.nucleus)\n"
            text += "  Coda: \(syllable.coda ?? "—")\n"
            let consonantClass = consonantClassString(for: syllable.onset.first)
            text += "  Konsonant-klasse: \(consonantClass)\n"
            let vlen = ThaiSeg.vowelLength(for: syllable.nucleus)
            text += "  Vokal-lengde: \(vlen == .long ? "LANG" : "KORT")\n"
            text += "  Live/Dead: \(syllable.live ? "LIVE (grønn)" : "DEAD (rød)")\n\n"
        }
        #if os(iOS)
        UIPasteboard.general.string = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
    }

    private func copySyllableToClipboard(_ syllable: String) {
        #if os(iOS)
        UIPasteboard.general.string = syllable
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(syllable, forType: .string)
        #endif
      
    }

    private func speakNorsk(_ text: String) {
        print("🔊 Speaking (detail sheet): '\(text)'")
        Task {
            var didSpeak = false
            do {
                try await CloudTTSTest.testGoogleTTS(text)
                didSpeak = true
                print("🔊 Spoke via CloudTTSTest (detail sheet) for: \(text)")
            } catch {
                print("❌ TTS error (detail sheet): \(error)")
                #if canImport(AVFoundation)
                if let _ = Optional(g as Any) {
                    g.talkTh(talkText: text, rate: 0.5, language: "nb-NO")
                    didSpeak = true
                    print("🔊 Spoke via global g.talkTh (detail sheet) for: \(text)")
                }
                if !didSpeak {
                    let utterance = AVSpeechUtterance(string: text)
                    utterance.voice = AVSpeechSynthesisVoice(language: "nb-NO")
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                    AVSpeechSynthesizer().speak(utterance)
                    didSpeak = true
                    print("🔊 Spoke via AVSpeechSynthesizer fallback (detail sheet) for: \(text)")
                }
                #endif
            }
        }
    }

    private func lookupInChatGPT(word: String) {
        #if os(iOS)
        UIPasteboard.general.string = word
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
        #endif
        let prompt = "What does the Thai word '\(word)' mean? Explain the meaning, give usage examples, and explain the syllable structure if possible."
        if let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://chat.openai.com/?q=\(encodedPrompt)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func copyWordAndShowInstruction(word: String) {
        #if os(iOS)
        UIPasteboard.general.string = word
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
        #endif
    }

    private func fullVowelString(for syllable: ThaiSyllable) -> String {
        let original = syllable.original
        let onset = syllable.onset
        let nucleus = syllable.nucleus ?? ""
        let coda = syllable.coda.map { String($0) } ?? ""
        let preposedVowels: Set<Character> = ["เ", "แ", "โ", "ใ", "ไ"]
        var preposed = ""
        var postposed = nucleus
        for char in original {
            if preposedVowels.contains(char) {
                preposed.append(char)
            }
        }
        if preposed.isEmpty {
            return postposed
        } else {
            if postposed.isEmpty {
                return preposed
            } else {
                return "\(preposed)-\(postposed)"
            }
        }
    }

    private func consonantClassColor(for onset: String) -> Color {
        guard let firstChar = onset.first else { return .primary }
        let consonantClass = consonantClassString(for: firstChar)
        switch consonantClass {
        case "LOW":
            return .green
        case "HIGH":
            return .red
        case "MID":
            return .blue
        default:
            return .primary
        }
    }

    private func isLongVowel(_ nucleus: String?) -> Bool {
        guard let nucleus else { return false }
        let vlen = ThaiSeg.vowelLength(for: nucleus)
        return vlen == .long
    }
}

// MARK: - Word Detail View
struct WordDetailView: View {
    let wordHit: WordHit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    // Kun for lesing av thai-oppslag — se kommentar i HybridSegmentationView. `context` brukes
    // fortsatt til lagring (CreateWordView) og skal ALDRI erstattes med speilet.
    private var gThaiLookupContext: NSManagedObjectContext { GThaiReferenceStore.shared.context }
    @Environment(AppState.self) private var appState
    @State private var isSpeaking = false
    @State private var syllables: [ThaiSyllable] = []
    @State private var showingPronunciationChecker = false
    @State private var showingCreateWord = false
    @State private var isFromPyThaiNLP: Bool = true
    
    var body: some View {
        content
    }
    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 16) {
                        HStack {
                            Text(wordHit.thai)
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Button(action: { speakWord() }) {
                                Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                                    .font(.title)
                                    .foregroundColor(isSpeaking ? .blue : .secondary)
                            }
                            .disabled(isSpeaking)

                            Button(action: { showingPronunciationChecker = true }) {
                                Image(systemName: "mic.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let ipa = wordHit.ipa(context: gThaiLookupContext) {
                            HStack {
                                Text("IPA:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("/\(ipa)/")
                                    .font(.title3)
                                    .foregroundColor(isFromPyThaiNLP ? .primary : .blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Definisjoner")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if let english = wordHit.english {
                            let definitions = english.components(separatedBy: ";")
                            ForEach(Array(definitions.enumerated()), id: \.offset) { index, definition in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .leading)
                                    
                                    Text(definition.trimmingCharacters(in: .whitespaces))
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No translation available")
                                    .font(.body)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Forslag:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)

                                    VStack(spacing: 8) {
                                        HStack(spacing: 12) {
                                            Button {
                                                lookupInChatGPT(word: wordHit.thai)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "brain")
                                                    Text("ChatGPT")
                                                }
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.green.opacity(0.2))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                copyWordAndShowInstruction(word: wordHit.thai)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "doc.on.clipboard")
                                                    Text("Copy word")
                                                }
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        Button {
                                            showingCreateWord = true
                                        } label: {
                                            HStack {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Create new word")
                                            }
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.2))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    
                    Divider()

                    if let components = wordHit.components(context: gThaiLookupContext), !components.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ordkomponenter")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(components, id: \.self) { component in
                                HStack {
                                    Text(component)
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    
                                    Text(componentMeaning(component))
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Orddetaljer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.red)
                    }
                }
            }
            .onAppear {
                loadSyllables()
            }
        }
        .sheet(isPresented: $showingPronunciationChecker) {
            ThaiPronounceCheckView(target: wordHit.thai)
        }
        .sheet(isPresented: $showingCreateWord) {
            NavigationStack {
                CreateWordView(
                    initialThaiWord: wordHit.thai,
                    overrideGroupId: AppState.autoCreatedWordsGroupId
                )
                .environment(appState)
                .environment(\.managedObjectContext, context)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingCreateWord = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func loadSyllables() {
        let result = ThaiNLPData.lookup(wordHit.thai, context: gThaiLookupContext)
        isFromPyThaiNLP = result.isPreComputed
        if result.isPreComputed && !result.syllables.isEmpty {
            print("✅ Using pre-computed syllables from Python NLP: \(result.syllables)")
            syllables = result.syllables.map { syllableText in
                ThaiSyllable(
                    onset: "",
                    nucleus: syllableText,
                    coda: nil,
                    live: true,
                    ipa: nil,
                    toneMark: nil,
                    range: 0..<syllableText.count,
                    original: syllableText,
                    start: 0,
                    end: syllableText.count
                )
            }
            if result.ipa.isEmpty || result.ipa.contains("NoJson") || result.ipa == "—" {
                syllables = syllables.map { syllable in
                    if let syllableIPA = fetchIPAForSyllable(syllable.original, context: gThaiLookupContext) {
                        return ThaiSyllable(
                            onset: syllable.onset,
                            nucleus: syllable.nucleus,
                            coda: syllable.coda,
                            live: syllable.live,
                            ipa: syllableIPA,
                            toneMark: syllable.toneMark,
                            range: syllable.range,
                            original: syllable.original,
                            start: syllable.start,
                            end: syllable.end
                        )
                    }
                    return syllable
                }
            }
        } else {
            print("⚠️ No pre-computed data - using ThaiSeg fallback")
            syllables = ThaiSeg.segmentWordIntoSyllables(wordHit.thai)
        }
    }

    private func speakWord() {
        isSpeaking = true
        Task {
            var didSpeak = false
            do {
                try await CloudTTSTest.testGoogleTTS(wordHit.thai)
                didSpeak = true
                print("🔊 Spoke via CloudTTSTest (WordDetailView) for: \(wordHit.thai)")
            } catch {
                print("❌ Cloud TTS feil (WordDetailView): \(error)")
                #if canImport(AVFoundation)
                if let _ = Optional(g as Any) {
                    g.talkTh(talkText: wordHit.thai, rate: 0.5, language: "th-TH")
                    didSpeak = true
                    print("🔊 Spoke via global g.talkTh (WordDetailView) for: \(wordHit.thai)")
                }
                if !didSpeak {
                    let utterance = AVSpeechUtterance(string: wordHit.thai)
                    utterance.voice = AVSpeechSynthesisVoice(language: "th-TH")
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                    AVSpeechSynthesizer().speak(utterance)
                    didSpeak = true
                    print("🔊 Spoke via AVSpeechSynthesizer fallback (WordDetailView) for: \(wordHit.thai)")
                }
                #endif
            }
            await MainActor.run {
                isSpeaking = false
            }
        }
    }

    private func lookupInChatGPT(word: String) {
        #if os(iOS)
        UIPasteboard.general.string = word
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
        #endif
        let prompt = "What does the Thai word '\(word)' mean? Explain the meaning, give usage examples, and explain the syllable structure if possible."
        if let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://chat.openai.com/?q=\(encodedPrompt)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func copyWordAndShowInstruction(word: String) {
        #if os(iOS)
        UIPasteboard.general.string = word
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
        #endif
    }
    
    private func componentMeaning(_ thai: String) -> String {
        // Sanitize input
        let key = thai.precomposedStringWithCanonicalMapping
        // 1) Try Core Data for exact match of thaiWord
        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.predicate = NSPredicate(format: "thaiWord == %@", key)
        req.fetchLimit = 1
        if let found = try? gThaiLookupContext.fetch(req).first {
            if let eng = found.englishWord, !eng.isEmpty {
                let short = eng.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return short ?? "—"
            }
            // englishWord tom på akkurat dette treffet — translation1 er norsk i gThai sin
            // database, bruk den som fallback-glose.
            if let norsk = found.translation1, !norsk.isEmpty {
                let short = norsk.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                return short ?? "—"
            }
        }
        // 2) Fallback to ThaiLexicon
        let lex = ThaiLexicon.resolveEnglish(key)
        if lex != "—" {
            let short = lex.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            return short ?? "—"
        }
        return "—"
    }
}

struct SyllableRowView: View {
    let syllable: ThaiSyllable
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
            Text(syllable.original)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(minWidth: 60, alignment: .leading)
            Text("[\(ipaForSyllable(syllable))]")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(syllable.live ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

extension WordHit {
    func ipa(context: NSManagedObjectContext) -> String? {
        let result = ThaiNLPData.lookup(self.thai, context: context)
        return result.ipa
    }

    func components(context: NSManagedObjectContext) -> [String]? {
        let result = ThaiNLPData.lookup(self.thai, context: context)
        return result.syllables
    }
}

fileprivate func fetchIPAForSyllable(_ syllableText: String, context: NSManagedObjectContext) -> String? {
    let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    request.predicate = NSPredicate(format: "thaiWord == %@", syllableText)
    request.fetchLimit = 1
    do {
        guard let word = try context.fetch(request).first else { return nil }
        guard let ipaField = word.ipa, !ipaField.isEmpty else { return nil }
        if let ipaMatch = ipaField.range(of: "#ipa=([^\n]+)", options: .regularExpression) {
            let ipaString = String(ipaField[ipaMatch])
                .replacingOccurrences(of: "#ipa=", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ipaString
        }
        if !ipaField.contains("NoJson") && !ipaField.contains("*") {
            return ipaField
        }
        return nil
    } catch {
        print("❌ Error fetching IPA for syllable '\(syllableText)': \(error)")
        return nil
    }
}

fileprivate func parseSyllablesJSON(from text: String) -> [String]? {
    let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), let data = trimmed.data(using: .utf8) else {
        return nil
    }
    do {
        return try JSONDecoder().decode([String].self, from: data)
    } catch {
        print("❌ Could not parse syllables JSON: \(error)")
        return nil
    }
}

fileprivate func precomputedSyllablesFromCoreData(for thai: String, context: NSManagedObjectContext) -> [String]? {
    let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    req.predicate = NSPredicate(format: "thaiWord == %@", thai)
    req.fetchLimit = 1
    do {
        if let word = try context.fetch(req).first, let sentence = word.sentence, !sentence.isEmpty {
            if let sylls = parseSyllablesJSON(from: sentence), !sylls.isEmpty {
                return sylls
            }
        }
    } catch {
        print("❌ Error fetching precomputed syllables for \(thai): \(error)")
    }
    return nil
}

/// Reads word.syllables directly — same field as ThaiNLPData.lookup but synchronous, no semaphore, safe on any thread.
fileprivate func syllablesFromCoreData(for thai: String, context: NSManagedObjectContext) -> [String]? {
    let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    req.predicate = NSPredicate(format: "thaiWord == %@", thai)
    req.fetchLimit = 1
    do {
        if let word = try context.fetch(req).first,
           let sylls = word.syllables, !sylls.isEmpty,
           sylls.joined() == thai {
            return sylls
        }
    } catch {
        print("❌ syllablesFromCoreData error for \(thai): \(error)")
    }
    return nil
}

fileprivate func stripPoliteness(_ word: String) -> String {
    let suffixes = ["คะ", "ค่ะ", "ครับ"]
    for suffix in suffixes {
        if word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
    }
    if word.hasSuffix("ค") {
        return String(word.dropLast(1))
    }
    return word
}

// MARK: - Minimal WordRowView used by SegmentedListView
struct WordRowView: View {
    let hit: WordHit
    @Binding var speakingWord: String?
    let isExpanded: Bool
    let hasChildren: Bool
    let isChild: Bool
    let existsInDB: Bool
    let hasCharMismatch: Bool
    let onToggleExpand: () -> Void
    let onWordTap: (WordHit) -> Void
    let onSpeakTap: (String) -> Void
    
    @State private var showingPronounceChecker = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right").font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.blue)
                    .imageScale(.medium) // baseline scale
                    .font(.system(size: 22, weight: .regular)) // point size for the symbol
                    .padding(10) // small internal padding for breathing room
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 44, height: 44) // tap target
                    )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "dot.square").font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .imageScale(.medium) // baseline scale
                    .font(.system(size: 22, weight: .regular)) // point size for the symbol
                    .padding(10) // small internal padding for breathing room
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 44, height: 44) // tap target
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.thai)
                        .font(isChild ? .body : .title3)
                        .foregroundStyle(.blue)
                        .fontWeight(isChild ? .regular : .semibold)
                        .foregroundColor(.primary)
                        .onTapGesture { onWordTap(hit) }

                    Circle()
                        .fill(existsInDB ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    if hasCharMismatch {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                    }
                }
                if let eng = hit.english, !eng.isEmpty {
                    Text(eng.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? eng)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Mic / Pronounce checker button
            Button(action: {
                showingPronounceChecker = true
            }) {
                Image(systemName: "microphone.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
                    .imageScale(.medium) // baseline scale
                    .font(.system(size: 22, weight: .regular)) // point size for the symbol
                    .padding(10) // small internal padding for breathing room
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: 44, height: 44) // tap target
                    )
            }
            .buttonStyle(.plain)

            // Speaker button
            Button(action: { onSpeakTap(hit.thai) }) {
                Image(systemName: speakingWord == hit.thai ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .foregroundColor(speakingWord == hit.thai ? .blue : .secondary)
                    .imageScale(.medium)
                    .font(.system(size: 22, weight: .regular))
                    .padding(10)
                    .background(Color.clear.contentShape(Rectangle()).frame(width: 44, height: 44))
            }
            .buttonStyle(.plain)
            .disabled(speakingWord != nil && speakingWord != hit.thai)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
        )
        .sheet(isPresented: $showingPronounceChecker) {
            ThaiPronounceCheckView(target: hit.thai)
        }
    }
}

#Preview {
    HybridSegmentationView(text: "ฉันกำลังขับรถ")
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
