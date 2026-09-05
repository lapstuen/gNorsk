//
//  func.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/4/25.
//


//
//  ThaiTone.swift
//  gThai
//

import Foundation

// MARK: - Toneberegning (tekstlig navn, norsk)
public func finnThaiTone(consonantClass: String,
                  liveSyllable: Bool,
                  ToneMark: String,
                  lognVowel: Bool) -> String {

    let cls = consonantClass.uppercased()

    let mapMidHigh: [String: String] = [
        "่": "Lav",
        "้": "Fallende",
        "๊": "Høy",
        "๋": "Stigende"
    ]
    let mapLow: [String: String] = [
        "่": "Fallende",
        "้": "Høy",
        "๊": "Stigende",
        "๋": "Høy"
    ]

    if let mark = ToneMark.first.map(String.init), !mark.isEmpty {
        if cls == "LOW", let tone = mapLow[mark] { return tone }
        if let tone = mapMidHigh[mark] { return tone }
    }

    switch cls {
    case "MID":
        return liveSyllable ? "Midt" : "Lav"
    case "HIGH":
        return liveSyllable ? "Stigende" : "Lav"
    case "LOW":
        if liveSyllable { return "Midt" }
        else { return lognVowel ? "Fallende" : "Høy" }
    default:
        return "Midt"
    }
}

// MARK: - Mapping fra norsk streng → enum
public func toneEnum(from s: String) -> ThaiTone {
    switch s {
    case "Høy":       return .high
    case "Lav":       return .low
    case "Fallende":  return .falling
    case "Stigende":  return .rising
    case "Midt": fallthrough
    default:          return .mid
    }
}