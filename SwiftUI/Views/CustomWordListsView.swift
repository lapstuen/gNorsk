//
//  CustomWordListsView.swift
//  gThai
//

import SwiftUI
import CoreData

private struct WordListCatalogEntry: Decodable, Identifiable {
    let name: String
    let file: String
    var id: String { file }
}

struct CustomWordListsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WordList.name, ascending: true)]
    ) private var myLists: FetchedResults<WordList>

    @AppStorage("customWordListsIndexURL") private var indexURLString: String = ""

    @State private var catalog: [WordListCatalogEntry] = []
    @State private var isLoadingCatalog = false
    @State private var isLoadingList = false
    @State private var loadingFile: String?
    @State private var errorMessage: String?

    @State private var matchedIDs: [NSManagedObjectID] = []
    @State private var loadedListName = ""
    @State private var showGrid = false

    @State private var editingList: WordList?
    @State private var showCreateList = false

    var body: some View {
        NavigationStack {
            List {
                Section("My Lists") {
                    ForEach(myLists) { list in
                        HStack {
                            Button {
                                practice(list)
                            } label: {
                                HStack {
                                    Text(list.name ?? "Untitled")
                                    Spacer()
                                    Text("\(list.wordsArray.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingList = list
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                context.delete(list)
                                try? context.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(list)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingList = list
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    Button {
                        showCreateList = true
                    } label: {
                        Label("New list", systemImage: "plus.circle")
                    }
                }

                Section("Source") {
                    TextField("https://example.com/lists/index.json", text: $indexURLString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Button {
                        Task { await loadCatalog() }
                    } label: {
                        if isLoadingCatalog {
                            ProgressView()
                        } else {
                            Text("Load list of lists")
                        }
                    }
                    .disabled(indexURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingCatalog)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }

                if !catalog.isEmpty {
                    Section("Available lists") {
                        ForEach(catalog) { entry in
                            Button {
                                Task { await loadList(entry) }
                            } label: {
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    if isLoadingList && loadingFile == entry.file {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isLoadingList)
                        }
                    }
                }
            }
            .navigationTitle("Word Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showGrid) {
                GridView(filtrerteId: matchedIDs, listName: loadedListName, exerciseMode: true, onBack: { showGrid = false })
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    .navigationTitle(loadedListName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $showCreateList) {
                WordListEditorView(list: nil)
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 600, minHeight: 700)
                    #endif
            }
            .sheet(item: $editingList) { list in
                WordListEditorView(list: list)
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 600, minHeight: 700)
                    #endif
            }
        }
    }

    private func matchWords(_ words: [String]) -> [NSManagedObjectID] {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord IN %@", words)
        let matches = (try? context.fetch(request)) ?? []

        var seen = Set<String>()
        var ids: [NSManagedObjectID] = []
        for word in matches {
            guard let text = word.thaiWord, !seen.contains(text) else { continue }
            seen.insert(text)
            ids.append(word.objectID)
        }
        return ids
    }

    private func practice(_ list: WordList) {
        matchedIDs = matchWords(list.wordsArray)
        loadedListName = list.name ?? "Untitled"
        showGrid = true
    }

    private func resolvedURL(forFile file: String, relativeTo indexURL: URL) -> URL? {
        if let direct = URL(string: file), direct.scheme != nil {
            return direct
        }
        return indexURL.deletingLastPathComponent().appendingPathComponent(file)
    }

    private func loadCatalog() async {
        errorMessage = nil
        guard let url = URL(string: indexURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid URL."
            return
        }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            catalog = try JSONDecoder().decode([WordListCatalogEntry].self, from: data)
            if catalog.isEmpty {
                errorMessage = "The index file contained no lists."
            }
        } catch {
            catalog = []
            errorMessage = "Could not load the index file: \(error.localizedDescription)"
        }
    }

    private func loadList(_ entry: WordListCatalogEntry) async {
        errorMessage = nil
        guard let indexURL = URL(string: indexURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let fileURL = resolvedURL(forFile: entry.file, relativeTo: indexURL) else {
            errorMessage = "Invalid file URL for '\(entry.name)'."
            return
        }
        isLoadingList = true
        loadingFile = entry.file
        defer {
            isLoadingList = false
            loadingFile = nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: fileURL)
            let words = try JSONDecoder().decode([String].self, from: data)

            matchedIDs = matchWords(words)
            loadedListName = entry.name
            showGrid = true
        } catch {
            errorMessage = "Could not load '\(entry.name)': \(error.localizedDescription)"
        }
    }
}

/// Oppretter en ny liste, eller redigerer navn/ord på en eksisterende.
private struct WordListEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let list: WordList?

    @State private var name: String
    @State private var wordsText: String

    init(list: WordList?) {
        self.list = list
        _name = State(initialValue: list?.name ?? "")
        _wordsText = State(initialValue: list?.wordsArray.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("List name", text: $name)
                }
                Section("Words (one per line)") {
                    TextEditor(text: $wordsText)
                        .frame(minHeight: 300)
                }
            }
            .navigationTitle(list == nil ? "New list" : "Edit list")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target = list ?? WordList(context: context)
        if list == nil {
            target.id = UUID()
            target.createdDate = Date()
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.setWords(Self.parseWordsInput(wordsText))
        try? context.save()
        dismiss()
    }

    /// Tolker teksten i ord-feltet ord for ord, ikke basert på et gjettet format for
    /// HELE teksten — det tåler at man limer inn en blanding av vanlig tekst og
    /// JSON-fragmenter (f.eks. fra web, eller "Copy word list (JSON)" fra gruppevisningen)
    /// uten at klammer/anførselstegn blir en del av selve ordet.
    static func parseWordsInput(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
