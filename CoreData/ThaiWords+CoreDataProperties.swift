//
//  ThaiWords+CoreDataProperties.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/27/25.
//
//

public import Foundation
public import CoreData


public typealias ThaiWordsCoreDataPropertiesSet = NSSet

extension ThaiWords {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ThaiWords> {
        return NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
    }

    @NSManaged public var dateOne: Date?
    @NSManaged public var dateTwo: Date?
    @NSManaged public var englishWord: String?
    @NSManaged public var groupId: Int16
    @NSManaged public var id: UUID?
    @NSManaged public var image: Data?
    @NSManaged public var insertDate: Date?
    @NSManaged public var sentence: String?
    @NSManaged public var star: Bool
    @NSManaged public var thaiWord: String?
    @NSManaged public var dueAt: Date?
    @NSManaged public var easiness: Double
    @NSManaged public var frequencyRank: Int32
    @NSManaged public var ipa: String?
    @NSManaged public var language: String?
    @NSManaged public var lapses: Int32
    @NSManaged public var lastResult: Int16
    @NSManaged public var lastReviewedAt: Date?
    @NSManaged public var learningState: Int16
    @NSManaged public var learningStep: Int16
    @NSManaged public var modifiedDate: Date?
    @NSManaged public var notes: String?
    @NSManaged public var repetitions: Int32
    @NSManaged public var tags: String?
    @NSManaged public var translation1: String?
    @NSManaged public var translation2: String?
    @NSManaged public var wordType: Int16

}

extension ThaiWords : Identifiable {

}

// MARK: - WordType
// 0 = word, 1 = sentence
extension ThaiWords {
    var isSentence: Bool { wordType == 1 }

    /// Detects wordType from English text: no spaces → word (0), spaces → sentence (1).
    static func detectWordType(english: String) -> Int16 {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(" ") ? 1 : 0
    }
}

// MARK: - Frequency Rank Extraction
extension ThaiWords {

    /// Henter frekvensranken fra sentence-feltet hvis det starter med #NNNN
    /// Returnerer nil hvis ingen gyldig frekvenstag finnes
    func extractFrequencyRank() -> Int? {
        guard let s = sentence?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              !s.contains("*NoJson"),
              let first = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first,
              first.count == 5,
              first.first == "#"
        else { return nil }

        let digits = first.dropFirst()
        guard digits.allSatisfy(\.isNumber),
              let rank = Int(digits)
        else { return nil }

        return rank
    }

    /// Sjekker om ordet er innenfor et gitt frekvensintervall
    /// Sjekker først frequencyRank-feltet, deretter parser fra sentence
    /// Returnerer true hvis ordet ikke har frekvensrank (vanlige ord)
    func isWithinFrequencyRange(min: Int, max: Int) -> Bool {
        // Først sjekk frequencyRank-feltet direkte
        if frequencyRank > 0 {
            return Int(frequencyRank) >= min && Int(frequencyRank) <= max
        }
        // Fallback: prøv å parse fra sentence
        guard let rank = extractFrequencyRank() else {
            return true // Ord uten frekvensrank er alltid "innenfor"
        }
        return rank >= min && rank <= max
    }

    /// Henter frekvensrank - først fra feltet, deretter fra sentence
    func getFrequencyRank() -> Int? {
        if frequencyRank > 0 {
            return Int(frequencyRank)
        }
        return extractFrequencyRank()
    }
}

// MARK: - Tag Management (for relaterte ord)
extension ThaiWords {

    /// Henter alle tags som array
    var tagsArray: [String] {
        guard let tags = tags, !tags.isEmpty else { return [] }
        // Fjern komma foran og bak, split på komma
        let trimmed = tags.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        return trimmed.components(separatedBy: ",").filter { !$0.isEmpty }
    }

    /// Setter tags fra array (lagrer som ",tag1,tag2,")
    func setTags(_ newTags: [String]) {
        if newTags.isEmpty {
            tags = nil
        } else {
            tags = "," + newTags.joined(separator: ",") + ","
        }
    }

    /// Legger til en tag (unngår duplikater)
    func addTag(_ tag: String) {
        var current = tagsArray
        if !current.contains(tag) {
            current.append(tag)
            setTags(current)
        }
    }

    /// Fjerner en tag
    func removeTag(_ tag: String) {
        var current = tagsArray
        current.removeAll { $0 == tag }
        setTags(current)
    }

    /// Sjekker om ordet har en spesifikk tag
    func hasTag(_ tag: String) -> Bool {
        tagsArray.contains(tag)
    }

    /// Formattert visning av tags (uten ekstra komma)
    var tagsDisplayString: String {
        tagsArray.joined(separator: ", ")
    }
}

// MARK: - Enhanced Learning System Extensions
extension ThaiWords {

    // Safe access to learning state with fallback
    var safeLearningState: Int16 {
        get {
            if self.responds(to: Selector("learningState")) {
                return self.value(forKey: "learningState") as? Int16 ?? 0
            }
            return 0 // Default to "new" state
        }
        set {
            if self.responds(to: Selector("learningState")) {
                self.setValue(newValue, forKey: "learningState")
            }
            // Ignore if property doesn't exist
        }
    }

    // Safe access to learning step with fallback
    var safeLearningStep: Int16 {
        get {
            if self.responds(to: Selector("learningStep")) {
                return self.value(forKey: "learningStep") as? Int16 ?? 0
            }
            return 0 // Default to first step
        }
        set {
            if self.responds(to: Selector("learningStep")) {
                self.setValue(newValue, forKey: "learningStep")
            }
            // Ignore if property doesn't exist
        }
    }

    // Helper to check if enhanced learning properties are available
    var hasEnhancedLearningProperties: Bool {
        return self.responds(to: Selector("learningState")) &&
               self.responds(to: Selector("learningStep"))
    }
}


