//
//  CurrentGroup+CoreDataProperties.swift
//  gThai
//
//  Created by Macbook Pro on 11/02/2022.
//
//

import Foundation
import CoreData


extension CurrentGroup {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CurrentGroup> {
        return NSFetchRequest<CurrentGroup>(entityName: "CurrentGroup")
    }

    @NSManaged public var groupId: Int16
    @NSManaged public var number: Int16

}
