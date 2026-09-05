// FrequencyGroupSeeder.swift
// Oppretter faste, forhåndsdefinerte grupper på FØRSTE oppstart av appen (på enhver installasjon),
// slik at import fra Public kan plassere ord automatisk uten at brukeren må tenke på grupper.
//
// Grupper (faste groupId 1000–1045, like på alle installasjoner):
//   1000–1039  "#0001-0100" ... "#3901-4000"  (40 frekvensgrupper, á 100 ord)
//   1040       "No Group"   (fallback for ord uten gyldig frekvensrank, f.eks. 1-4000)
//   1041       "Group 1"
//   1042       "Group 2"
//   1043       "@Noun"
//   1044       "@Verb"
//   1045       "@Adjective"
import CoreData

enum FrequencyGroupSeeder {

    static let frequencyGroupBaseId: Int16 = 1000
    static let bucketSize: Int32 = 100
    static let bucketCount = 40
    static let maxRank: Int32 = Int32(bucketCount) * bucketSize  // 4000

    static let noGroupId: Int16 = 1040
    static let group1Id: Int16 = 1041
    static let group2Id: Int16 = 1042
    static let nounGroupId: Int16 = 1043
    static let verbGroupId: Int16 = 1044
    static let adjectiveGroupId: Int16 = 1045

    /// Returnerer groupId for frekvensbøtta et gitt ord hører hjemme i, eller nil hvis
    /// frequencyRank er 0/ugyldig eller utenfor 1...4000 (da brukes `noGroupId` som fallback).
    static func groupId(forFrequencyRank frequencyRank: Int32) -> Int16? {
        guard frequencyRank >= 1, frequencyRank <= maxRank else { return nil }
        let bucketIndex = Int((frequencyRank - 1) / bucketSize)
        return frequencyGroupBaseId + Int16(bucketIndex)
    }

    private static func bucketName(forIndex index: Int) -> String {
        let from = index * Int(bucketSize) + 1
        let to = (index + 1) * Int(bucketSize)
        return String(format: "#%04d-%04d", from, to)
    }

    /// Engangs-seeding: oppretter alle 46 gruppene hvis de ikke allerede finnes. Trygt å kalle flere ganger.
    static func seedIfNeeded(context: NSManagedObjectContext) {
        let key = "frequencyGroupsSeedDone_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let existingRequest: NSFetchRequest<Group> = Group.fetchRequest()
        existingRequest.predicate = NSPredicate(format: "groupId >= %d AND groupId <= %d", frequencyGroupBaseId, adjectiveGroupId)
        let existingIds = Set((try? context.fetch(existingRequest))?.map(\.groupId) ?? [])

        func createGroupIfMissing(id: Int16, name: String, type: GroupType, from: Int32 = 0, to: Int32 = 0) {
            guard !existingIds.contains(id) else { return }
            let group = Group(context: context)
            group.id = UUID()
            group.groupId = id
            group.groupName = name
            group.groupType = type.rawValue
            group.frequencyFrom = from
            group.frequencyTo = to
        }

        for index in 0..<bucketCount {
            let from = Int32(index * Int(bucketSize) + 1)
            let to = Int32((index + 1) * Int(bucketSize))
            createGroupIfMissing(
                id: frequencyGroupBaseId + Int16(index), name: bucketName(forIndex: index),
                type: .frequencyInactive, from: from, to: to
            )
        }

        createGroupIfMissing(id: noGroupId, name: "No Group", type: .normalInactive)
        createGroupIfMissing(id: group1Id, name: "Group 1", type: .normalInactive)
        createGroupIfMissing(id: group2Id, name: "Group 2", type: .normalInactive)
        createGroupIfMissing(id: nounGroupId, name: "@Noun", type: .normalInactive)
        createGroupIfMissing(id: verbGroupId, name: "@Verb", type: .normalInactive)
        createGroupIfMissing(id: adjectiveGroupId, name: "@Adjective", type: .normalInactive)

        do {
            try context.save()
            print("✅ FrequencyGroupSeeder: opprettet forhåndsdefinerte grupper")
        } catch {
            print("❌ FrequencyGroupSeeder: feil under lagring: \(error)")
            return // ikke marker som ferdig hvis lagring feilet
        }
        UserDefaults.standard.set(true, forKey: key)
    }
}
