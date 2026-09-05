//
//  ThaiWord.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/1/25.

import SwiftUI

var allJSONWords: [ThaiWordJSON] = []

struct ThaiWordJSON: Codable, Identifiable {
    var id: String { word }  // bruker ordet som unik ID
    let word: String
    let ipa: String
    let english: String
    let rank: Int
    let frequency: Double
    let dpRank: Double
    let example: String
}


