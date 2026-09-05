//
//  Sentences+helpers.swift
//  gThai
//
//  Created by ChatGPT on 2025-09-08.
//

import Foundation
import CoreData
import UIKit

enum SentenceHelpers {
    
    // MARK: - Validation
    static func isValidThaiText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        let thaiRange = trimmed.unicodeScalars.filter { scalar in
            return (0x0E00...0x0E7F).contains(scalar.value) // Thai Unicode range
        }
        
        return thaiRange.count > trimmed.count / 2 // At least 50% Thai characters
    }
    
    // Check if ThaiWords entry exists
    static func thaiWordExists(_ thaiText: String, in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord == %@", thaiText)
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking ThaiWords existence: \(error)")
            return false
        }
    }
    
    // MARK: - Add Sentence as ThaiWords entry
    static func addThaiWordSentence(_ sentenceText: String, baseWord: ThaiWords, context: NSManagedObjectContext) -> Bool {
        // Double-check it doesn't exist
        guard !thaiWordExists(sentenceText, in: context) else {
            return false
        }
        
        let newEntry = ThaiWords(context: context)
        
        // Required fields
        newEntry.id = UUID()
        newEntry.thaiWord = sentenceText
        newEntry.englishWord = ""  // Empty - user can fill later
        newEntry.tags = "*\(baseWord.thaiWord ?? "")"  // Tag with base word
        newEntry.groupId = baseWord.groupId  // Same group as base word
        
        // Optional fields with defaults
        newEntry.insertDate = Date()
        newEntry.sentence = ""
        newEntry.notes = "Auto-generated sentence"
        newEntry.language = "th"
        newEntry.star = false
        
        // SRS fields (spaced repetition)
        newEntry.easiness = 2.5
        newEntry.repetitions = 0
        newEntry.lapses = 0
        newEntry.lastResult = 0
        newEntry.frequencyRank = 0
        
        do {
            try context.save()
            return true
        } catch {
            print("Error saving ThaiWords sentence: \(error)")
            return false
        }
    }
    
    // MARK: - Clipboard Helper (your existing functionality)
    static func addSentenceFromClipboard(for word: ThaiWords, context: NSManagedObjectContext) -> Bool {
        guard let clipboardText = UIPasteboard.general.string else { return false }
        
        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidThaiText(trimmed) else { return false }
        
        return addThaiWordSentence(trimmed, baseWord: word, context: context)
    }
}

// MARK: - Tags

/// Lager *tag fra grunnord. Returnerer nil hvis grunnord er tomt.
@inline(__always)
public func makeWordTag(fromThaiWord base: String?) -> String? {
    let trimmed = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : "*\(trimmed)"
}

/// Legger til `newTag` i space-separert `tags` uten duplikater.
public func appendTag(_ newTag: String, to existing: String?) -> String {
    var set = Set((existing ?? "").split(separator: " ").map(String.init))
    set.insert(newTag)
    return set.joined(separator: " ")
}

/// Sørger for at *{grunnord} finnes i `existing`.
public func ensureWordTag(_ base: String?, in existing: String?) -> String? {
    guard let tag = makeWordTag(fromThaiWord: base) else { return existing }
    return appendTag(tag, to: existing)
}

// MARK: - Pasteboard

private func isThaiOnly(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    
    // Check if ALL characters are Thai (stricter than isValidThaiText)
    for scalar in trimmed.unicodeScalars {
        let value = scalar.value
        // Thai Unicode range + common punctuation/spaces
        let isThaiChar = (0x0E00...0x0E7F).contains(value)
        let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
        let isPunctuation = CharacterSet.punctuationCharacters.contains(scalar)
        
        if !isThaiChar && !isSpace && !isPunctuation {
            return false
        }
    }
    
    // Must have at least some Thai characters
    let thaiCount = trimmed.unicodeScalars.filter { scalar in
        return (0x0E00...0x0E7F).contains(scalar.value)
    }.count
    
    return thaiCount > 0
}

/// Leser utklippstavlen og returnerer trimmed streng **kun** hvis den er ren thai.
public func readPasteboardThaiOrNil() -> String? {
    #if canImport(UIKit)
    let raw = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    #else
    let raw = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    #endif
    return isThaiOnly(raw) ? raw : nil
}

// MARK: - Predikat for “Vis setninger”

/// Predikat som matcher `tags` CONTAINS *{grunnord}
public func wordTagContainsPredicate(for base: String?) -> NSPredicate? {
    guard let tag = makeWordTag(fromThaiWord: base) else { return nil }
    return NSPredicate(format: "tags CONTAINS %@", tag)
}

// MARK: - Opprett setning fra utklippstavle


public enum SentenceUpsertResult {
    case created          // ny rad laget
    case taggedExisting   // fant rad; la til ny tag
    case alreadyTagged    // fant rad; tag fantes fra før (ingen endring)
    case invalidClipboard // tom/ikke-thai
    case saveFailed       // Core Data save feilet
}

/// Lager/oppdaterer en `ThaiWords` fra utklippstavlen.
/// - Ser først etter eksisterende `thaiWord == paste`.
/// - Hvis finnes: legger til *{grunnord} i `tags` (uten duplikat).
/// - Hvis ikke: oppretter ny rad (groupId=84) med `thaiWord` og tag.
/// - Returnerer en detaljert status.
@discardableResult
public func createSentenceFromPasteboard(
    context: NSManagedObjectContext,
    baseThaiWord: String?,
    groupId: Int16 = 84
) -> SentenceUpsertResult {
    guard let paste = readPasteboardThaiOrNil() else { return .invalidClipboard }

    // 1) Finn eksisterende rad med samme tekst
    let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
    fetch.predicate = NSPredicate(format: "thaiWord == %@", paste)
    fetch.fetchLimit = 1

    do {
        if let existing = try context.fetch(fetch).first {
            // Oppdater tags på eksisterende rad
            let newTags = ensureWordTag(baseThaiWord, in: existing.tags)
            if newTags == existing.tags {
                return .alreadyTagged
            } else {
                existing.tags = newTags
                try context.save()
                return .taggedExisting
            }
        } else {
            // 2) Lag ny rad
            let sentence = ThaiWords(context: context)
            sentence.thaiWord   = paste
            sentence.groupId    = groupId   // hardkodet for test
            sentence.tags       = ensureWordTag(baseThaiWord, in: sentence.tags)
            sentence.insertDate = Date()
            try context.save()
            return .created
        }
    } catch {
        NSLog("createSentenceFromPasteboard save/fetch error: \(error)")
        return .saveFailed
    }
}

