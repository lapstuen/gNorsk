import SwiftUI
import CoreData

struct WordDetailAnalyzer: View {
    @Environment(\.managedObjectContext) private var context

    let thaiWord: String
    @State private var matches: [(substring: String, english: String?)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
           // Text("Thai-ord").font(.headline)
          //  Text(thaiWord).font(.largeTitle).padding(.bottom)

           // Button("Vis detaljerte deler") {
           //     analyzeComponents()
           // }

            if matches.isEmpty {
                Text("No known parts found.")
                    .italic()
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognized parts:").font(.headline)

                    ForEach(matches, id: \.substring) { entry in
                        HStack {
                            Text(entry.substring)
                                .font(.title3)
                                .bold()

                            Spacer()

                            if let meaning = entry.english {
                                Text(meaning)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            } else {
                                Text("❓")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top)
            }
        }.background(.red)
        .padding()
    }

    //private func analyzeComponents()
    private func analyzeComponents() {
        Task { @MainActor in
            let text = thaiWord
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !text.isEmpty else {
                self.matches = []
                return
            }

            // 🔎 Hjelper: finnes del i DB?
            func existsInDB(_ s: String) -> Bool {
                let req = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
                req.predicate   = NSPredicate(format: "thaiWord == %@", s)
                req.resultType  = .countResultType
                req.fetchLimit  = 1
                do { return try context.count(for: req) > 0 }
                catch { print("Count feil for \(s): \(error)"); return false }
            }

            // 🔎 Hjelper: hent engelsk (kan være tom)
            func englishFromDB(_ s: String) -> String? {
                let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
                req.predicate  = NSPredicate(format: "thaiWord == %@", s)
                req.fetchLimit = 1
                do { return try context.fetch(req).first?.englishWord }
                catch { print("Fetch eng feil for \(s): \(error)"); return nil }
            }

            var out: [(String, String?)] = []
            var i = text.startIndex

            while i < text.endIndex {
                var hit: (String, String?)? = nil
                var j = i

                // bygg prefiks og stopp ved første DB‑treff
                while j < text.endIndex {
                    j = text.index(after: j)
                    let slice = String(text[i..<j]).precomposedStringWithCanonicalMapping
                    if existsInDB(slice) {
                        hit = (slice, englishFromDB(slice))    // hent engelsk samtidig
                        break
                    }
                }

                if let h = hit {
                    out.append(h)   // (substring, english?)
                    i = j           // hopp forbi funnet ord
                } else {
                    i = text.index(after: i) // ingen treff → gå ett tegn frem
                }
            }

            self.matches = out
        }
    }
}
