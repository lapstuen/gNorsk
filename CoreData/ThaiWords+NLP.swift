//
//  ThaiWords+NLP.swift
//  gThai
//
//  NLP (Natural Language Processing) extensions for ThaiWords
//  Handles syllable segmentation and IPA data from PyThaiNLP
//

import Foundation
import CoreData

extension ThaiWords {

    // MARK: - Syllables Storage

    enum SyllableStorageDiagnostic: Equatable {
        case empty(rawSentence: String?)
        case malformed(rawSentence: String?)
        case found([String])
    }

    /// Get syllables as array
    /// Stored in `sentence` field as JSON array: ["เข้า", "ร่วม"]
    var syllables: [String]? {
        get {
            guard let json = sentence, !json.isEmpty else { return nil }
            // 1. Try JSON first: ["กระ","ดาษ","ชำ","ระ"]
            if let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return decoded
            }
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            // 2. Bracket format: [กระ ][ดาษ][ชำ][ ระ]
            if trimmed.contains("][") {
                let parts = trimmed.components(separatedBy: "][")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")) }
                    .filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts
            }
            // 3. Comma format: [กระ, ดาษ, ชำ, ระ]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = trimmed.dropFirst().dropLast()
                let parts = inner.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts
            }
            // 4. Space format: กระ ดาษ ชำ ระ
            if trimmed.contains(" ") && !trimmed.contains("[") {
                let parts = trimmed.components(separatedBy: " ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.count >= 2 {
                    return parts
                }
            }
            return nil
        }
        set {
            guard let syllables = newValue else {
                sentence = nil
                return
            }
            guard let data = try? JSONEncoder().encode(syllables) else {
                sentence = nil
                return
            }
            sentence = String(data: data, encoding: .utf8)
        }
    }

    /// Returns a diagnostic state so callers can tell empty storage from parse failure.
    func syllableStorageDiagnostic() -> SyllableStorageDiagnostic {
        guard let json = sentence else {
            return .empty(rawSentence: nil)
        }

        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty(rawSentence: json)
        }

        if let decoded = syllables, !decoded.isEmpty {
            return .found(decoded)
        }

        return .malformed(rawSentence: json)
    }

    /// Check if word has syllable data
    var hasSyllables: Bool {
        return syllables != nil && !(syllables?.isEmpty ?? true)
    }

    // MARK: - NLP Metadata

    /// Source of NLP data (stored in `notes` field)
    /// Format: "nlp:PyThaiNLP|2025-01-10T12:00:00Z"
    var nlpSource: String? {
        get {
            guard let notes = notes else { return nil }
            let components = notes.components(separatedBy: "|")
            if let nlpPart = components.first, nlpPart.hasPrefix("nlp:") {
                return nlpPart.replacingOccurrences(of: "nlp:", with: "")
            }
            return nil
        }
        set {
            var components = notes?.components(separatedBy: "|") ?? []

            // Remove old nlp source (first component if it starts with "nlp:")
            if let first = components.first, first.hasPrefix("nlp:") {
                components.removeFirst()
            }

            // Add new nlp source at the beginning
            if let source = newValue {
                components.insert("nlp:\(source)", at: 0)
            }

            notes = components.isEmpty ? nil : components.joined(separator: "|")
        }
    }

    /// Last NLP update date (stored in `notes` field)
    var nlpUpdatedAt: Date? {
        get {
            guard let notes = notes else { return nil }
            let components = notes.components(separatedBy: "|")
            // Date is second component
            if components.count >= 2 {
                let formatter = ISO8601DateFormatter()
                return formatter.date(from: components[1])
            }
            return nil
        }
        set {
            var components = notes?.components(separatedBy: "|") ?? []

            // Ensure we have at least nlp source
            if components.isEmpty || !components[0].hasPrefix("nlp:") {
                components.insert("nlp:unknown", at: 0)
            }

            // Remove old date if exists (second component)
            if components.count >= 2 {
                components.remove(at: 1)
            }

            // Add new date as second component
            if let date = newValue {
                let formatter = ISO8601DateFormatter()
                let dateString = formatter.string(from: date)
                components.insert(dateString, at: 1)
            }

            notes = components.isEmpty ? nil : components.joined(separator: "|")
        }
    }

    // MARK: - Convenience Methods

    /// Check if NLP data is complete (has both syllables and IPA)
    var hasCompleteNLPData: Bool {
        return hasSyllables && ipa != nil && ipa != "—" && ipa != "⚠️ Mangler IPA"
    }

    /// Get syllables or generate them using ThaiSeg
    func getSyllablesOrGenerate() -> [String] {
        // Return cached syllables if available
        if let cached = syllables, !cached.isEmpty {
            return cached
        }

        // Generate using ThaiSeg
        guard let thai = thaiWord else { return [] }
        let generated = ThaiSeg.segmentWordIntoSyllables(thai)
        return generated.map { $0.original }
    }

    /// Update NLP data from PyThaiNLP result
    func updateNLPData(syllables: [String], ipa: String?, source: String = "PyThaiNLP") {
        self.syllables = syllables
        if let ipa = ipa, ipa != "⚠️ Mangler IPA" {
            self.ipa = ipa
        }
        self.nlpSource = source
        self.nlpUpdatedAt = Date()
    }
}

// MARK: - Batch Operations

extension ThaiWords {

    /// Find all words that need NLP data updates
    static func fetchWordsNeedingNLPUpdate(context: NSManagedObjectContext) -> [ThaiWords] {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        // Find words without syllables or IPA
        request.predicate = NSPredicate(format: "thaiWord != nil AND (sentence == nil OR ipa == nil OR ipa == '—')")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ThaiWords.thaiWord, ascending: true)]

        do {
            return try context.fetch(request)
        } catch {
            print("❌ Error fetching words needing NLP update: \(error)")
            return []
        }
    }

    /// Get statistics about NLP data coverage
    static func getNLPStatistics(context: NSManagedObjectContext) -> (total: Int, withSyllables: Int, withIPA: Int, complete: Int) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord != nil")

        do {
            let allWords = try context.fetch(request)
            let total = allWords.count
            let withSyllables = allWords.filter { $0.hasSyllables }.count
            let withIPA = allWords.filter { $0.ipa != nil && $0.ipa != "—" }.count
            let complete = allWords.filter { $0.hasCompleteNLPData }.count

            return (total, withSyllables, withIPA, complete)
        } catch {
            print("❌ Error fetching NLP statistics: \(error)")
            return (0, 0, 0, 0)
        }
    }
}
