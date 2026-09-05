import SwiftUI
import CoreData

public enum SentencesListEnumTag {
    public static let file = "SentencesListView.swift"
    public static let version = "2025-09-09"
}

struct SentencesListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppState.self) private var appState

    private let baseWord: String?
    @FetchRequest private var sentences: FetchedResults<ThaiWords>

    /// Viser ALLE setninger som er tagget med *{grunnord}, uansett groupId.
    init(baseWord: String?) {
        self.baseWord = baseWord

        let tagPred = wordTagContainsPredicate(for: baseWord) ?? NSPredicate(value: false)

        _sentences = FetchRequest<ThaiWords>(
            sortDescriptors: [NSSortDescriptor(keyPath: \ThaiWords.insertDate, ascending: false)],
            predicate: tagPred,
            animation: .default
        )
    }

    var body: some View {
        List {
            if sentences.isEmpty {
                ContentUnavailableView(
                    "No sentences yet",
                    systemImage: "text.quote",
                    description: Text("Use “Paste sentence” to add one.")
                )
            } else {
                ForEach(sentences) { item in
                    // Enkel, ren rad: kun thai-tekst
                    NavigationLink {
                        // PUSHer direkte til detalj
                        DetailWordView(initialWord: WordInput(from: item), isNested: false)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.thaiWord ?? "—")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(baseWord ?? "Sentences")
    }
}

#Preview {
    NavigationStack {
        SentencesListView(baseWord: "ที่")
            .environment(AppState())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
