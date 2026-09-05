//
//  Group+CoreDataProperties.swift
//  gThai
//
//  Created by Macbook Pro on 12/02/2022.
//
//

import Foundation
import CoreData
import SwiftUI

// MARK: - GroupType Enum
// Fire gruppefamilier, hver med sin egen rawValue-"sone":
// Regular (negative), Frequency (1-9), Sentences (20-29), Video (30-39).
// Merk: -1 og 1 ("aktiv" Regular/Frequency) manglet tidligere som egne cases og falt feilaktig
// tilbake til .frequencyInactive via Group.type — lagt til her for å rette opp det samtidig.
enum GroupType: Int16, CaseIterable {
    case normalActive = -1  // Vanlig gruppe, aktiv
    case normalInactive = -9  // Vanlig gruppe
    case frequencyActive = 1  // Frekvensgruppe, aktiv
    case frequencyCompleted = 2  // Frekvensgruppe, fullført
    case frequencyPaused = 3  // Frekvensgruppe, pauset
    case frequencyInactive = 9   // Frekvensgruppe (standard)
    case sentence = 21  // Setningsgruppe
    case video = 31  // Videogruppe

    var displayName: String {
        switch self {
        case .normalActive: return "Regular"
        case .normalInactive: return "Inactive"
        case .frequencyActive: return "Frequency"
        case .frequencyCompleted: return "Completed"
        case .frequencyPaused: return "Paused"
        case .frequencyInactive: return "Freq."
        case .sentence: return "Sentences"
        case .video: return "Video"
        }
    }

    var color: Color {
        switch self {
        case .normalActive: return .blue
        case .normalInactive: return .gray
        case .frequencyActive: return .orange
        case .frequencyCompleted: return .blue
        case .frequencyPaused: return .orange
        case .frequencyInactive: return .gray
        case .sentence: return .green
        case .video: return .red
        }
    }

    var iconName: String {
        switch self {
        case .normalActive, .normalInactive: return "folder"
        case .frequencyActive, .frequencyInactive: return "chart.bar"
        case .frequencyCompleted: return "checkmark.circle.fill"
        case .frequencyPaused: return "pause.circle.fill"
        case .sentence: return "text.quote"
        case .video: return "play.rectangle.fill"
        }
    }

    var isFrequencyBased: Bool {
        switch self {
        case .frequencyActive, .frequencyCompleted, .frequencyPaused, .frequencyInactive: return true
        default: return false
        }
    }

    var isNormalGroup: Bool {
        switch self {
        case .normalActive, .normalInactive: return true
        default: return false
        }
    }
}

extension Group {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Group> {
        return NSFetchRequest<Group>(entityName: "Group")
    }

    @NSManaged public var groupId: Int16
    @NSManaged public var groupName: String?
    @NSManaged public var groupType: Int16
    @NSManaged public var id: UUID?
    @NSManaged public var language: String?

    // Sikker tilgang til frequencyFrom (nytt felt)
    var frequencyFrom: Int32 {
        get {
            // Sjekk om attributtet finnes i entity description
            guard entity.attributesByName["frequencyFrom"] != nil else {
                print("⚠️ frequencyFrom attributt finnes ikke i Core Data modellen")
                return 0
            }
            let val = value(forKey: "frequencyFrom") as? Int32 ?? 0
            print("📖 Leser frequencyFrom: \(val)")
            return val
        }
        set {
            guard entity.attributesByName["frequencyFrom"] != nil else {
                print("⚠️ Kan ikke lagre frequencyFrom - attributt finnes ikke")
                return
            }
            print("💾 Lagrer frequencyFrom: \(newValue)")
            setValue(newValue, forKey: "frequencyFrom")
        }
    }

    // Sikker tilgang til frequencyTo (nytt felt)
    var frequencyTo: Int32 {
        get {
            guard entity.attributesByName["frequencyTo"] != nil else {
                print("⚠️ frequencyTo attributt finnes ikke i Core Data modellen")
                return 0
            }
            let val = value(forKey: "frequencyTo") as? Int32 ?? 0
            print("📖 Leser frequencyTo: \(val)")
            return val
        }
        set {
            guard entity.attributesByName["frequencyTo"] != nil else {
                print("⚠️ Kan ikke lagre frequencyTo - attributt finnes ikke")
                return
            }
            print("💾 Lagrer frequencyTo: \(newValue)")
            setValue(newValue, forKey: "frequencyTo")
        }
    }
}

// MARK: - GroupType Helpers
extension Group {

    var type: GroupType {
        get { GroupType(rawValue: groupType) ?? .frequencyInactive }
        set { groupType = newValue.rawValue }
    }

    // Sjekker faktisk GroupType-case fremfor bare fortegn på groupType — et rent fortegns-sjekk
    // holdt så lenge det bare fantes to familier (negativ=normal, positiv=frekvens), men bryter nå
    // som Sentences (21) og Video (31) også er positive rawValues uten å være frekvensgrupper.
    var isFrequencyGroup: Bool {
        type.isFrequencyBased
    }

    var isNormalGroup: Bool {
        type.isNormalGroup
    }

    var isSentenceGroup: Bool {
        type == .sentence
    }

    var isVideoGroup: Bool {
        type == .video
    }

    /// Konverterer til vanlig gruppe (ikke frekvensbasert)
    func makeNormalGroup() {
        groupType = GroupType.normalInactive.rawValue
    }

    /// Konverterer til frekvensgruppe
    func makeFrequencyGroup() {
        groupType = GroupType.frequencyInactive.rawValue
    }

    /// Konverterer til setningsgruppe
    func makeSentenceGroup() {
        groupType = GroupType.sentence.rawValue
    }

    /// Konverterer til videogruppe
    func makeVideoGroup() {
        groupType = GroupType.video.rawValue
    }

    /// Setter gruppen til fullført (kun frekvensgrupper)
    func markCompleted() {
        groupType = GroupType.frequencyCompleted.rawValue
    }

    /// Setter gruppen til pauset (kun frekvensgrupper)
    func pause() {
        groupType = GroupType.frequencyPaused.rawValue
    }
}

// MARK: - Batch Operations
extension Group {

    /// Beregner frekvensintervallet (min, max) for en gruppe basert på ordenes frekvenstag
    /// Returnerer nil hvis gruppen ikke har noen ord med frekvenstag
    static func frequencyRange(for groupId: Int16, context: NSManagedObjectContext) -> (min: Int, max: Int)? {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %d AND sentence BEGINSWITH[c] '#'", groupId)

        do {
            let words = try context.fetch(request)
            var minRank = Int.max
            var maxRank = Int.min

            for word in words {
                if let rank = word.extractFrequencyRank() {
                    minRank = min(minRank, rank)
                    maxRank = max(maxRank, rank)
                }
            }

            if minRank <= maxRank {
                return (minRank, maxRank)
            }
        } catch {
            print("❌ Feil ved beregning av frekvensintervall: \(error)")
        }
        return nil
    }

    /// Parser frekvensintervall fra gruppenavn (format: "0000-0050" eller "0051-0100")
    /// Returnerer nil hvis navnet ikke matcher formatet
    static func parseFrequencyRangeFromName(_ name: String?) -> (min: Int, max: Int)? {
        guard let name = name else { return nil }

        // Match format NNNN-NNNN (4 digits - 4 digits)
        let pattern = #"^(\d{4})-(\d{4})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              match.numberOfRanges == 3,
              let minRange = Range(match.range(at: 1), in: name),
              let maxRange = Range(match.range(at: 2), in: name),
              let minVal = Int(name[minRange]),
              let maxVal = Int(name[maxRange])
        else { return nil }

        return (minVal, maxVal)
    }

    /// Henter frekvensintervall for gruppen fra lagrede felt
    /// Returnerer nil hvis gruppen ikke faktisk er en frekvensgruppe, eller hvis
    /// frequencyFrom/frequencyTo begge er 0 (ikke satt). Uten isFrequencyGroup-sjekken kunne en
    /// gruppe som tidligere var frekvensgruppe (og fortsatt har gamle from/to-verdier liggende),
    /// men som siden er endret til f.eks. Video eller Regular, feilaktig fortsette å bli
    /// frekvens-fargelagt i gitteret.
    func getFrequencyRange() -> (min: Int, max: Int)? {
        guard isFrequencyGroup else { return nil }
        // Sjekk om frekvensintervall er satt (begge 0 betyr ikke satt)
        if frequencyFrom == 0 && frequencyTo == 0 {
            return nil
        }
        return (Int(frequencyFrom), Int(frequencyTo))
    }

    /// Setter frekvensintervall for gruppen
    func setFrequencyRange(from: Int, to: Int) {
        frequencyFrom = Int32(from)
        frequencyTo = Int32(to)
    }

    /// Sjekker om gruppen har et definert frekvensintervall
    var hasFrequencyRange: Bool {
        frequencyFrom > 0 || frequencyTo > 0
    }

    // Safe accessor for image (added in model v5)
    var groupImage: Data? {
        get {
            guard entity.attributesByName["image"] != nil else { return nil }
            return value(forKey: "image") as? Data
        }
        set {
            guard entity.attributesByName["image"] != nil else { return }
            setValue(newValue, forKey: "image")
        }
    }

    var groupUIImage: UIImage? {
        guard let data = groupImage else { return nil }
        return UIImage(data: data)
    }

    // Safe accessor for youtubeUrl (added in model v4)
    var youtubeUrl: String? {
        get {
            guard entity.attributesByName["youtubeUrl"] != nil else { return nil }
            return value(forKey: "youtubeUrl") as? String
        }
        set {
            guard entity.attributesByName["youtubeUrl"] != nil else { return }
            setValue(newValue, forKey: "youtubeUrl")
        }
    }

    /// Converts "1:04" or "10:33" → seconds (64, 633)
    static func timestampToSeconds(_ timestamp: String) -> Int? {
        let parts = timestamp.components(separatedBy: ":")
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
            return m * 60 + s
        }
        if parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) {
            return h * 3600 + m * 60 + s
        }
        return nil
    }

    /// Builds a YouTube URL with optional timestamp.
    static func youtubeURL(baseUrl: String, seconds: Int? = nil) -> URL? {
        var urlStr = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = seconds {
            urlStr += (urlStr.contains("?") ? "&" : "?") + "t=\(t)"
        }
        return URL(string: urlStr)
    }

    /// Opens YouTube at optional timestamp. Works with youtube.com and youtu.be URLs.
    static func openYouTube(baseUrl: String, seconds: Int? = nil) {
        guard let url = youtubeURL(baseUrl: baseUrl, seconds: seconds) else { return }
        UIApplication.shared.open(url)
    }

    /// Extracts the YouTube video ID from watch/short/embed/youtu.be URLs, tolerant of
    /// extra query params (&t=, &list=) and share suffixes (?si=).
    static func youtubeVideoID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed) else { return nil }
        if comps.host?.contains("youtu.be") == true {
            let id = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let parts = comps.path.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(where: { $0 == "embed" || $0 == "shorts" }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    /// Følgegrupper (Word/Ok, groupId % 3 != 0) skal aldri fungere som en "hovedgruppe" —
    /// resolver til den faktiske hovedgruppens ID (groupId - groupId % 3).
    /// Frekvensgrupper (1000+) er ikke del av tripletter og skal derfor bevares som de er.
    static func resolvedBaseGroupId(for groupId: Int16) -> Int16 {
        guard groupId < FrequencyGroupSeeder.frequencyGroupBaseId else {
            return groupId
        }

        let offset = groupId % 3
        return offset == 0 ? groupId : groupId - offset
    }

    /// Shared chronological sort used by GridView's video-group list, DetailWordView's
    /// prev/next sibling navigation, and the synced-transcript view. Words with a
    /// parseable `notes` timestamp sort by seconds; otherwise falls back to string compare.
    static func sortedChronologically(_ words: [ThaiWords]) -> [ThaiWords] {
        words.sorted { a, b in
            let aN = a.notes ?? "", bN = b.notes ?? ""
            if let aS = timestampToSeconds(aN), let bS = timestampToSeconds(bN) {
                return aS != bS ? aS < bS : (a.thaiWord ?? "") < (b.thaiWord ?? "")
            }
            return aN.localizedStandardCompare(bN) == .orderedAscending
        }
    }
}

