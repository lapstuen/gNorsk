//
//  AddSentenceView.swift
//  gThai
//
//  Created by GitHub Copilot on 9/10/25.
//

import SwiftUI
import CoreData
import UIKit

/// Gruppe for setninger som legges til som tilleggsinformasjon til andre ord
/// Disse skal IKKE blandes med øvelsesgrupper. Brukt også fra CreateWordView når den
/// åpnes i "lenket setning"-modus (linkedWord er satt) — se CreateWordView.swift.
let kSentencesForWordsGroupID: Int16 = 129  // #xSentencesForWords

struct AddSentenceView: View {
    let word: ThaiWords
    
    
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var thaiSentence = ""
    @State private var englishTranslation = ""
    @State private var morsmaal = ""
    @State private var isTranslating = false
    @State private var existingWord: ThaiWords? = nil
    @State private var speech = SpeechManager(locale: Locale(identifier: "nb-NO"))
    @State private var linkExists: Bool = false
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk

    private func checkIfSentenceExists() {
        let trimmed = thaiSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            existingWord = nil
            return
        }

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetch.predicate = NSPredicate(format: "thaiWord == %@", trimmed)
        fetch.fetchLimit = 1

        do {
            let results = try context.fetch(fetch)
            existingWord = results.first
            if let existing = existingWord {
                linkExists = existing.hasTag(word.thaiWord ?? "")
            } else {
                linkExists = false
            }
        } catch {
            existingWord = nil
            linkExists = false
        }
    }

    /// Ved enhver feil kalles `completion(nil)` — kalleren skal vise en feilmelding og la feltet
    /// stå tomt, ikke late som kildeteksten var en gyldig oversettelse. Tidligere kalte denne
    /// funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den delte
    /// AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
    private func translateText(text: String, fromLanguage: String, toLanguage: String, completion: @escaping (String?) -> Void) {
        AppleTranslationService.shared.translate(text: text, fromLanguage: fromLanguage, toLanguage: toLanguage, completion: completion)
    }

    private var clipboardHasStrings: Bool {
        UIPasteboard.general.hasStrings
    }

    private var clipboardHasThaiText: Bool {
        readPasteboardThaiOrNil() != nil
    }

    private func pasteMorsmaalFromClipboard() {
        guard let first = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            Notifier.shared.show(.error, "The clipboard is empty.")
            return
        }
        morsmaal = first
    }

    private func pasteThaiSentenceFromClipboard() {
        guard let first = readPasteboardThaiOrNil() else {
            Notifier.shared.show(.error, "The clipboard must contain only Thai characters.")
            return
        }
        thaiSentence = first
    }

    private func lookupThaiAndEnglishFromMorsmaal(sourceText: String, saveAfterLookup: Bool) {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        let sourceLanguage = morsmaalLanguage.translationCode
        let needsThai = thaiSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsEnglish = englishTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsThai || needsEnglish else {
            if saveAfterLookup { saveSentence() }
            return
        }

        isTranslating = true
        var resolvedThai = thaiSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedEnglish = englishTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        var translationFailed = false
        let group = DispatchGroup()

        if needsThai {
            group.enter()
            translateText(text: source, fromLanguage: sourceLanguage, toLanguage: "th") { translation in
                DispatchQueue.main.async {
                    if let translation {
                        resolvedThai = translation
                        self.thaiSentence = translation
                    } else {
                        translationFailed = true
                    }
                    group.leave()
                }
            }
        }

        if needsEnglish {
            group.enter()
            translateText(text: source, fromLanguage: sourceLanguage, toLanguage: "en") { translation in
                DispatchQueue.main.async {
                    if let translation {
                        resolvedEnglish = translation
                        self.englishTranslation = translation
                    } else {
                        translationFailed = true
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.isTranslating = false
            if translationFailed {
                Notifier.shared.show(.error, "Translation failed — fill in the missing field(s) manually and save again.")
                return
            }
            if saveAfterLookup {
                self.saveSentence()
            }
        }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Thai-ordet som tittel
                    Text(word.thaiWord ?? "")
                        .font(.system(size: 40, weight: .bold))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("Native language (\(morsmaalLanguage.label))")
                                .font(.headline)
                            Spacer()
                            Button {
                                pasteMorsmaalFromClipboard()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonBorderShape(.capsule)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .disabled(!clipboardHasStrings)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            TextField("Type the native text...", text: $morsmaal, axis: .vertical)
                                .font(.title2.bold())
                                .lineLimit(2...4)

                            Button {
                                lookupThaiAndEnglishFromMorsmaal(sourceText: morsmaal, saveAfterLookup: false)
                            } label: {
                                if isTranslating {
                                    ProgressView()
                                        .frame(width: 44, height: 44)
                                } else {
                                    Label("Lookup", systemImage: "sparkles")
                                        .font(.headline)
                                        .frame(width: 90, height: 44)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
                        }

                        if !morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Google Translate can fill Thai and English from this field.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Thai sentence")
                                .font(.headline)
                            Spacer()
                            Button {
                                pasteThaiSentenceFromClipboard()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonBorderShape(.capsule)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .disabled(!clipboardHasThaiText)
                        }

                        ThaiSentenceInputView(sentenceText: $thaiSentence, speech: speech)
                    }
                    .padding(.horizontal)
                    .onChange(of: speech.transcript) { _, newTranscript in
                        if !newTranscript.isEmpty {
                            // Kan like gjerne være et enkeltord/synonym som en hel setning her —
                            // behandles derfor likt: Apples talegjenkjenning kapitaliserer alltid
                            // første bokstav, det rettes tilbake til liten forbokstav.
                            thaiSentence = newTranscript.prefix(1).lowercased() + newTranscript.dropFirst()
                        }
                    }

                    if let existing = existingWord {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("The word already exists in the database")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }

                            // Show existing tags
                            if !existing.tagsArray.isEmpty {
                                Text("Current tags: \(existing.tagsDisplayString)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if linkExists {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("'\(word.thaiWord ?? "")' is already linked to this word")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Engelsk oversettelse
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("English translation:")
                                .font(.headline)
                            if isTranslating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }

                        TextField("English translation...", text: $englishTranslation)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .disabled(isTranslating)
                    }
                    .padding(.horizontal)
                    
                    //Spacer(minLength: 30)
                    
                    // Lagre knapp - avhengig av om ordet finnes eller ikke
                    if let existing = existingWord {
                        // Ordet finnes allerede - legg til kobling
                        let tagAlreadyExists = linkExists

                        Button {
                            addTagToExistingWord(existing)
                        } label: {
                            Text(tagAlreadyExists ? "Already linked" : "Save link")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(tagAlreadyExists ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(tagAlreadyExists)
                    } else {
                        // Nytt ord - lagre som vanlig
                        Button {
                            // Stopper mikrofonen automatisk her — brukeren skulle
                            // tidligere selv huske å trykke "Stop" før "Save
                            // sentence" virket som forventet.
                            speech.stop()
                            if !morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                lookupThaiAndEnglishFromMorsmaal(sourceText: morsmaal, saveAfterLookup: true)
                            } else if englishTranslation.isEmpty && !thaiSentence.isEmpty {
                                translateAndSave()
                            } else {
                                saveSentence()
                            }
                        } label: {
                            Text(isTranslating ? "Translating..." : "Save sentence")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((!thaiSentence.isEmpty || !morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !isTranslating ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled((thaiSentence.isEmpty && morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isTranslating)
                    }

                    Spacer(minLength: 40)

                    // Start og Stopp knapper for tale-input
                    HStack(spacing: 16) {
                        Button {
                            speech.start()
                        } label: {
                            Text("Start")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Button {
                            speech.stop()
                        } label: {
                            Text("Stop")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Add sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                speech.stop()
                Notifier.shared.hide()
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 750, minHeight: 900)
        #endif
        .wireNotifications()
    }
    
    private func translateAndSave() {
        guard !thaiSentence.isEmpty else { return }

        isTranslating = true

        translateText(text: thaiSentence, fromLanguage: "th", toLanguage: "en") { [self] translation in
            DispatchQueue.main.async {
                self.isTranslating = false
                guard let translation else {
                    Notifier.shared.show(.error, "Translation failed — fill in English manually and save again.")
                    return
                }
                self.englishTranslation = translation
                self.saveSentence()
            }
        }
    }

    private func addTagToExistingWord(_ existing: ThaiWords) {
        let currentWordText = word.thaiWord ?? ""
        existing.addTag(currentWordText)

        do {
            try context.save()
            print("Tag '\(currentWordText)' added to existing word '\(existing.thaiWord ?? "")'")
            Notifier.shared.show(.success, "Link added!")
            dismiss()
        } catch {
            print("Error saving tag: \(error)")
            Notifier.shared.show(.error, "Could not save link")
        }
    }

    private func saveSentence() {
        let trimmedThai = thaiSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMorsmaal = morsmaal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThai.isEmpty || !trimmedMorsmaal.isEmpty else { return }

        // Perform existence check only at save-time to avoid interrupting typing/pasting
        checkIfSentenceExists()
        if let existing = existingWord {
            if linkExists {
                Notifier.shared.show(.success, "Link already saved!")
                dismiss()
                return
            }

            addTagToExistingWord(existing)
            return
        }

        let g = GlFunctions()
        let currentWordText = word.thaiWord ?? ""

        // If the native-language field is the source, translate to Thai/English first.
        if trimmedThai.isEmpty, !trimmedMorsmaal.isEmpty {
            lookupThaiAndEnglishFromMorsmaal(sourceText: trimmedMorsmaal, saveAfterLookup: true)
            return
        }

        // Lagre setning i dedikert gruppe (#xSentencesForWords)
        // Dette sikrer at setninger ikke blandes med øvelsesgruppene
        let success = g.insertWordIntoCoreDataNoImage(
            id: UUID(),
            thaiword: trimmedThai,
            englishword: englishTranslation.isEmpty ? "Auto-translation failed" : englishTranslation,
            tag: currentWordText,
            groupId: kSentencesForWordsGroupID,
            wordType: 1
        )

        if success {
            print("Sentence saved: '\(trimmedThai)' with tag '\(currentWordText)'")
            Notifier.shared.show(.success, "Sentence saved!")
            dismiss()
        } else {
            print("Error saving sentence")
            Notifier.shared.show(.error, "Could not save sentence")
            isTranslating = false
        }
    }

}


#Preview {
    let context = PersistenceController.preview.container.viewContext
    let testWord = ThaiWords(context: context)
    testWord.thaiWord = "สวัสดี"
    testWord.englishWord = "Hello"

    return AddSentenceView(word: testWord)
        .environment(\.managedObjectContext, context)
}
