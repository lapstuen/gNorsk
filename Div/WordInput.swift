//
//  WordInput.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/7/25.
//
// import SwiftUI
import CoreData
import UIKit


struct WordInput: Identifiable {
    var id: UUID { uuid ?? UUID() }

    let objectID: NSManagedObjectID?
    let thaiWord: String
    let englishWord: String
    let ipa: String
    let sentence: String
    let tags: String
    let image: UIImage?
    let uuid: UUID?
    let translation1: String
    let translation2: String

    init(from w: ThaiWords) {
        self.objectID   = w.objectID
        self.thaiWord   = w.thaiWord ?? ""
        self.englishWord = w.englishWord ?? ""
        self.ipa = w.ipa ?? ""
        self.sentence   = w.sentence ?? ""
        if let data = w.image { self.image = UIImage(data: data) } else { self.image = nil }
        self.uuid = w.id
        self.tags = w.tags ?? ""
        self.translation1 = w.translation1 ?? ""
        self.translation2 = w.translation2 ?? ""
    }

    init(objectID: NSManagedObjectID?, thaiWord: String, englishWord: String, ipa: String = "", sentence: String, tags: String, image: UIImage?, uuid: UUID?, translation1: String, translation2: String) {
        self.objectID = objectID
        self.thaiWord = thaiWord
        self.englishWord = englishWord
        self.ipa = ipa
        self.sentence = sentence
        self.tags = tags
        self.image = image
        self.uuid = uuid
        self.translation1 = translation1
        self.translation2 = translation2
    }
}
