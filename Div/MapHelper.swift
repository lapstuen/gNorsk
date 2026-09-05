//
//  MapHelper.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/14/25.
//


import CoreData

func objectIDs(forThaiWords words: [String], in context: NSManagedObjectContext) -> [NSManagedObjectID] {
    guard !words.isEmpty else { return [] }
    let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
    req.predicate = NSPredicate(format: "thaiWord IN %@", words)
    req.resultType = .managedObjectIDResultType
    req.returnsDistinctResults = true
    do {
        return try context.fetch(req)
    } catch {
        print("🛑 Klarte ikke mappe ThaiWordJson til objectIDs: \(error.localizedDescription)")
        return []
    }
}