//
//  ThaiSyllable.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

// MARK: - Datastruktur for én stavelse
public struct ThaiSyllable: Identifiable, Equatable, Hashable, Sendable {
    public let id = UUID()
    public let onset: String
    public let nucleus: String
    public let coda: String?
    public let live: Bool
    public let ipa: String?
    public let toneMark: Character?

    // hvor i originalstrengen stavelsen kom fra
    public let range: Range<Int>
    public let original: String

    // bakoverkompatibelt
    public let start: Int
    public let end: Int
}

