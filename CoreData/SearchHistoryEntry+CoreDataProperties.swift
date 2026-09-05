//
//  SearchHistoryEntry+CoreDataProperties.swift
//  gThai
//

import Foundation
import CoreData

extension SearchHistoryEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SearchHistoryEntry> {
        NSFetchRequest<SearchHistoryEntry>(entityName: "SearchHistoryEntry")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var searchText: String?
    @NSManaged public var usedAt: Date?
}
