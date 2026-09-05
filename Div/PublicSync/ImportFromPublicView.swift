// ImportFromPublicView.swift
// Lar HVEM SOM HELST med appen hente ord (og tilknyttede setninger) fra den delte
// Public-databasen inn i sin egen private database. Ord som allerede finnes lokalt
// (matchet på thaiWord-tekst, samme sjekk som resten av appen bruker) hoppes over.
// Selve import-logikken ligger i PublicImportService (delt med "Fetch words" i EditGroupView).
import SwiftUI
import CoreData

struct ImportFromPublicView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fraRankText: String = "1"
    @State private var tilRankText: String = "200"
    @State private var isRunning = false
    @State private var resultSummary: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Import from Public") {
                    TextField("From rank", text: $fraRankText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("To rank", text: $tilRankText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button {
                        runImport()
                    } label: {
                        Label("Import from Public", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(isRunning || Int(fraRankText) == nil || Int(tilRankText) == nil)

                    Text("Fetches words within the frequency range from the shared library, along with linked example sentences. Words you already have (same Thai text) are automatically skipped — no duplicates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isRunning {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing from Public...")
                                .font(.footnote)
                        }
                    }
                }

                if let summary = resultSummary {
                    Section("Result") {
                        Text(summary)
                    }
                }
            }
            .navigationTitle("Import from Public")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1000)
        #endif
    }

    private func runImport() {
        guard let minRank = Int(fraRankText), let maxRank = Int(tilRankText) else { return }

        isRunning = true
        resultSummary = nil

        Task {
            do {
                let result = try await PublicImportService.importRange(
                    minRank: minRank, maxRank: maxRank, targetGroupId: nil, context: context
                )
                await MainActor.run {
                    isRunning = false
                    resultSummary = "\(result.importedWords) words imported (\(result.skippedWords) already existed). "
                        + "\(result.importedSentences) sentences imported (\(result.skippedSentences) already existed)."
                    Notifier.shared.show(.success, "Import completed")
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    resultSummary = "Error during import: \(error.localizedDescription)"
                    Notifier.shared.show(.error, "Import failed")
                }
            }
        }
    }
}

#Preview {
    ImportFromPublicView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
