import SwiftUI
import CoreData


struct WordHit: Identifiable {
    let id = UUID()
    let thai: String
    let english: String?
    var children: [WordHit]? = nil  // For compound words with syllable breakdowns

    init(thai: String, english: String?, children: [WordHit]? = nil) {
        self.thai = thai
        self.english = english
        self.children = children
    }
}


// MARK: - 1) Kjerne: prefiks-scan med "lookup(word) -> Bool"
func prefixScan(_ rawText: String, lookup: (String) -> Bool) -> [String] {
    let text = rawText.precomposedStringWithCanonicalMapping
    var out: [String] = []
    var i = text.startIndex

    while i < text.endIndex {
        var found: String? = nil
        var j = i
        while j < text.endIndex {             // bygg prefiks
            j = text.index(after: j)
            let slice = String(text[i..<j]).precomposedStringWithCanonicalMapping
            if lookup(slice) {                 // 🔎 direkte DB-lookup pr. delstreng
                found = slice
                break                          // første (korteste) prefiks-treff
            }
        }
        if let word = found {
            out.append(word)
            i = j                               // hopp forbi funnet ord
        } else {
            i = text.index(after: i)            // ingen treff -> ett tegn frem
        }
    }
    return out
}

@MainActor
func coreDataLookup(word: String,
                    in context: NSManagedObjectContext) -> WordHit? {
    let normalized = word.precomposedStringWithCanonicalMapping
    let req = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
    req.predicate = NSPredicate(format: "thaiWord == %@", normalized)
    req.fetchLimit = 1
    do {
        if let obj = try context.fetch(req).first {
            let eng = obj.value(forKey: "englishWord") as? String
            return WordHit(thai: normalized, english: eng)
        }
    } catch {
        print("🛑 Lookup feilet for \(normalized): \(error)")
    }
    return nil
}

// MARK: - 2) Core Data-oppslag (eksakt likhet, fetchLimit=1, count)
@MainActor
func coreDataExists(word: String, in context: NSManagedObjectContext) -> Bool {
    let normalized = word.precomposedStringWithCanonicalMapping
    let req = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
    req.predicate = NSPredicate(format: "thaiWord == %@", normalized)
    req.resultType = .countResultType
    req.fetchLimit = 1
    do {
        return try context.count(for: req) > 0
    } catch {
        print("🛑 DB lookup feilet for «\(normalized)»: \(error)")
        return false
    }
}

// MARK: - Treffstruktur (thai + engelsk)


// MARK: - Prefiks-scan med lookup som returnerer WordHit?
func prefixScanHits(_ rawText: String,
                    lookup: (String) -> WordHit?) -> [WordHit] {
    let text = rawText.precomposedStringWithCanonicalMapping
    var out: [WordHit] = []
    var i = text.startIndex

    while i < text.endIndex {
        var found: WordHit? = nil
        var j = i
        while j < text.endIndex {
            j = text.index(after: j)
            let slice = String(text[i..<j]).precomposedStringWithCanonicalMapping
            if let hit = lookup(slice) {
                found = hit
                break
            }
        }
        if let hit = found {
            out.append(hit)
            i = j
        } else {
            i = text.index(after: i)
        }
    }
    return out
}

// MARK: - 3) Presentasjon i DetailView (bytt inn her)
struct DetailViewWithDBSegmentation: View {
    @Environment(\.managedObjectContext) private var context

    let thaiText: String
    let mockLookup: ((String) -> WordHit?)?   // 👈 legg til

    @State private var hits: [WordHit] = []

    // 👇 init som støtter mock i #Preview (default = nil → bruk DB)
    init(thaiText: String, mockLookup: ((String) -> WordHit?)? = nil) {
        self.thaiText = thaiText
        self.mockLookup = mockLookup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(thaiText)
                //.font(Font.custom("Chilanka", size: 48))
                .font(.largeTitle)
                .textSelection(.enabled)
                .padding(.bottom, 8)
            // Text("Foreslåtte deler").font(.caption)
            if hits.isEmpty {
                Text("No words found.").foregroundStyle(.secondary)
            } else {
                ForEach(hits) { hit in
                    HStack {
                        Text(hit.thai).font(Font.custom("Chilanka", size: 32))
                        if let eng = hit.english, !eng.isEmpty {
                            Text("→ \(eng)").foregroundStyle(.secondary)
                                .font(.largeTitle)
                        }
                    }
                }
            }
//            Text("Large Title").font(.largeTitle)
//                            Text("Title").font(.title)
//                            Text("Title2").font(.title2) // available iOS 14
//                            Text("Title3").font(.title3) // available iOS 14
//
//                            Divider()
//
//                            Text("Headline").font(.headline)
//                            Text("Subheadline").font(.subheadline)
            Button("Copy to clipboard") {
                UIPasteboard.general.string = self.thaiText
            }
            
            Spacer()
        }
        .padding()
        .task(id: thaiText) {
            if let mock = mockLookup {
                hits = prefixScanHits(thaiText, lookup: mock)
            } else {
                hits = prefixScanHits(thaiText) { slice in
                    coreDataLookup(word: slice, in: context)
                }
            }
        }.background(.white)
        
        
    }
}

//#Preview {
//    // Preview bruker en "mock lookup"
//    let mock: (String) -> WordHit? = { s in
//        switch s {
//        case "ฉัน": return WordHit(thai: s, english: "I")
//        case "เข้า": return WordHit(thai: s, english: "enter")
//        case "อพาร์ทเมนท์": return WordHit(thai: s, english: "apartment")
//        default: return nil
//        }
//    }
//    return DetailViewWithDBSegmentation(thaiText: "ฉันเข้าอพาร์ทเมนท์")
//        .task {
//            // Simulerer segmentering i preview
//        }
//}

// MARK: - 4) #Preview som VIRKER (bruker mock-ordbok, ikke DB)
#Preview {
    DetailViewWithDBSegmentation(
        thaiText: "ฉันเข้าอพาร์ทเมนท์",
        mockLookup: { s in
            switch s {
            case "ฉัน": return WordHit(thai: s, english: "I")
            case "เข้า": return WordHit(thai: s, english: "enter")
            case "อพาร์ทเมนท์": return WordHit(thai: s, english: "apartment")
            default: return nil
            }
        }
    )
}
