import SwiftUI
import CoreData

struct AdminToolsView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) var dismiss

    @State private var entriesWithoutValidEnglish: [ThaiWordsCleanup.Entry] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Admin Tools")
                    .font(.title)
                    .bold()

                Text("Scan and delete ThaiWords entries that lack valid English translations.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 20) {
                    Button("Scan") {
                        entriesWithoutValidEnglish = ThaiWordsCleanup.findEntriesWithoutValidEnglish(context: context)
#if canImport(UIKit)
                        Notifier.shared.show(.info, "Scan complete: \(entriesWithoutValidEnglish.count) entries found without valid English.")
#endif
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete") {
                        guard !entriesWithoutValidEnglish.isEmpty else { return }
#if canImport(UIKit)
                        let deletedCount = entriesWithoutValidEnglish.count
                        ThaiWordsCleanup.deleteEntries(entriesWithoutValidEnglish, context: context)
                        entriesWithoutValidEnglish.removeAll()
                        Notifier.shared.show(.success, "Deletion complete: deleted \(deletedCount) entries.")
#else
                        ThaiWordsCleanup.deleteEntries(entriesWithoutValidEnglish, context: context)
                        entriesWithoutValidEnglish.removeAll()
#endif
                    }
                    .buttonStyle(.bordered)
                    .disabled(entriesWithoutValidEnglish.isEmpty)
                }

                Text("Entries found: \(entriesWithoutValidEnglish.count)")
                    .font(.headline)
                    .padding(.top)

                if !entriesWithoutValidEnglish.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entriesWithoutValidEnglish.prefix(100), id: \.objectID) { entry in
                                Text(entry.thaiWord)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .frame(maxHeight: 300)
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

#if DEBUG
struct AdminToolsView_Previews: PreviewProvider {
    static var previewContext: NSManagedObjectContext = {
        let container = NSPersistentContainer(name: "Model")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        }
        return container.viewContext
    }()

    static var previews: some View {
        AdminToolsView()
            .environment(\.managedObjectContext, previewContext)
    }
}
#endif
