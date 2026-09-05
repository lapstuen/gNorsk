//
//  SentenceListView.swift
//  gThai
//
//  Created by Claude Code on 9/27/25.
//

import SwiftUI
import CoreData


    
    struct SentenceListView: View {
        let tag: String
        @Environment(\.managedObjectContext) private var context
        @Environment(\.dismiss) private var dismiss
        @Environment(AppState.self) private var appState
        @State private var showingAddSentence = false
        @State private var showingDebugInfo = false
        @State private var debugWords: [ThaiWords] = []

        @FetchRequest var sentences: FetchedResults<ThaiWords>
        
        init(tag: String) {
            self.tag = tag
            // Søk med komma rundt for å matche hele ord: ",ถูก," i ",ถูก,ต้อง,"
            // Også søk etter gamle format uten komma (bakoverkompatibilitet)
            let searchTagNew = ",\(tag),"
            let searchTagOld = tag

            // Debug: logg søket
            print("🔍 SentenceListView søker etter tag: '\(tag)'")
            print("🔍 searchTagNew: '\(searchTagNew)'")
            print("🔍 searchTagOld: '\(searchTagOld)'")

            // Bruk enkel CONTAINS - dette bør finne alle som har taggen et sted i tags-feltet
            self._sentences = FetchRequest(
                entity: ThaiWords.entity(),
                sortDescriptors: [NSSortDescriptor(keyPath: \ThaiWords.insertDate, ascending: false)],
                predicate: NSPredicate(format: "tags CONTAINS %@", tag)
            )
        }
        
        var body: some View {
            NavigationStack {
                VStack {
                    // Debug: vis antall resultater
                    let _ = print("🔍 Fant \(sentences.count) setninger for tag '\(tag)'")
                    let _ = {
                        for s in sentences.prefix(5) {
                            print("   - '\(s.thaiWord ?? "?")' tags: '\(s.tags ?? "nil")'")
                        }
                    }()

                    if sentences.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("No sentences found")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Create sentences with the word '\(tag)' to see them here")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(sentences, id: \.self) { sentence in
                                SentenceRowView(sentence: sentence, tag: tag)
                            }
                        }
                    }
                }
                .navigationTitle("Sentences with '\(tag)'")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack {
                            Button {
                                showingAddSentence = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            Button {
                                loadDebugInfo()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            Button {
                                openginfo()
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            Button {
                                dismiss()
                            } label: {
                                Label("Exit", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAddSentence) {
                    if let word = fetchWordForTag() {
                        CreateWordView(linkedWord: word)
                            .environment(appState)
                            .environment(\.managedObjectContext, context)
                            #if !targetEnvironment(macCatalyst)
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                            #endif
                    } else {
                        Text("Could not find the word '\(tag)'")
                            .padding()
                    }
                }
                .sheet(isPresented: $showingDebugInfo) {
                    TagDebugInfoView(tag: tag, words: debugWords)
                }
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 840, minHeight: 1040)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }

        private func fetchWordForTag() -> ThaiWords? {
            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate = NSPredicate(format: "thaiWord == %@", tag)
            req.fetchLimit = 1
            return try? context.fetch(req).first
        }

        private func loadDebugInfo() {
            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate = NSPredicate(format: "tags CONTAINS %@", tag)
            req.sortDescriptors = [NSSortDescriptor(keyPath: \ThaiWords.thaiWord, ascending: true)]

            do {
                debugWords = try context.fetch(req)
                showingDebugInfo = true
            } catch {
                print("🛑 Feil ved henting av debug info: \(error)")
            }
        }
        
        private func openginfo() {
            #if os(iOS) || targetEnvironment(macCatalyst)
            let textParam = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
            let urlString = "ginfo://word?text=\(textParam)"
            guard let url = URL(string: urlString) else {
                print("❌ Ugyldig URL-format: \(urlString)")
                return
            }
            if UIApplication.shared.canOpenURL(url) {
                print("✅ Åpner: \(urlString)")
                UIApplication.shared.open(url)
            } else {
                print("❌ ginfo:// kan IKKE åpnes – legg inn 'ginfo' i Info.plist > LSApplicationQueriesSchemes")
            }
            #else
            print("⚠️ ginfo:// åpning støttes ikke på denne plattformen.")
            #endif
        }
    }

    struct SentenceRowView: View {
        let sentence: ThaiWords
        let tag: String
        @State private var showingEdit = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Thai sentence
                Text(sentence.thaiWord ?? "")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.primary)
                
                // English translation
                if let english = sentence.englishWord, !english.isEmpty {
                    Text(english)
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Spacer()
                    
                    // Speak button
                    Button {
                        speakNorsk(sentence.thaiWord ?? "")
                    } label: {
                        Label("Read aloud", systemImage: "speaker.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    // Edit button
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
            // fullScreenCover (ikke sheet): denne visningen presenteres fra INNENFOR
            // SentenceListView, som selv typisk er presentert som et ark — en sheet nøstet i en
            // annen sheet blir på iPad ofte tvunget til en liten, kompakt visning uansett
            // presentationDetents/frame. fullScreenCover unngår dette, men støtter ikke sveip for
            // å lukke, derfor lukkeknappen i overlay.
            .fullScreenCover(isPresented: $showingEdit) {
                DetailWordViewWrapper(objectID: sentence.objectID)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 900, minHeight: 1200)
                    #else
                    .frame(minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 900 : nil,
                           minHeight: UIDevice.current.userInterfaceIdiom == .pad ? UIScreen.main.bounds.height * 0.9 : nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
                    .overlay(alignment: .topLeading) {
                        Button {
                            showingEdit = false
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
        }
        
        private func speakNorsk(_ text: String) {
            // Use the existing CloudTTSTest.speakNorsk function
            CloudTTSTest.speakNorsk(text)
        }
    }
    
    // Wrapper to open DetailWordView with an existing ThaiWords object
    // Bruker isNested: true for å få mindre vindu (ca 90% av SentenceListView)
    struct DetailWordViewWrapper: View {
        let objectID: NSManagedObjectID
        @Environment(\.managedObjectContext) private var context

        var body: some View {
            if let thaiWord = try? context.existingObject(with: objectID) as? ThaiWords {
                let wordInput = WordInput(from: thaiWord)
                DetailWordView(initialWord: wordInput, isNested: true)
            } else {
                Text("Could not load word")
            }
        }
    }

    // Debug info view som viser alle ord med en gitt tag
    struct TagDebugInfoView: View {
        let tag: String
        let words: [ThaiWords]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack {
                            Text("Tag:")
                                .fontWeight(.semibold)
                            Text(tag)
                                .font(.title2)
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Text("Word count:")
                                .fontWeight(.semibold)
                            Text("\(words.count)")
                                .font(.title3)
                                .foregroundColor(words.isEmpty ? .red : .green)
                            Spacer()
                        }
                    } header: {
                        Text("Information")
                    }

                    if !words.isEmpty {
                        Section {
                            ForEach(words, id: \.objectID) { word in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(word.thaiWord ?? "?")
                                        .font(.headline)

                                    if let english = word.englishWord, !english.isEmpty {
                                        Text(english)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    if let tags = word.tags, !tags.isEmpty {
                                        Text("Tags: \(tags)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }

                                    Text("Group: \(g.getGroupname(groupId: word.groupId))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Words containing '\(tag)'")
                        }
                    } else {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                Text("No words found with this tag")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                }
                .navigationTitle("Tag Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            #if !targetEnvironment(macCatalyst)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

// MARK: - Preview
#Preview("With sentences") {
    let context = PersistenceController.preview.container.viewContext

    // Create sample sentences with tag "กิน"
    let sentence1 = ThaiWords(context: context)
    sentence1.id = UUID()
    sentence1.thaiWord = "ฉันกินข้าว"
    sentence1.englishWord = "I eat rice"
    sentence1.tags = "กิน"
    sentence1.groupId = 129
    sentence1.insertDate = Date()

    let sentence2 = ThaiWords(context: context)
    sentence2.id = UUID()
    sentence2.thaiWord = "เขากินอาหาร"
    sentence2.englishWord = "He eats food"
    sentence2.tags = "กิน"
    sentence2.groupId = 129
    sentence2.insertDate = Date().addingTimeInterval(-3600)

    try? context.save()

    return SentenceListView(tag: "กิน")
        .environment(\.managedObjectContext, context)
}

#Preview("Without sentences") {
    SentenceListView(tag: "ไม่มี")
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

