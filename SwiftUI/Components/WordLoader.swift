//
//  WordLoader.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/1/25.
//
import SwiftUI

func loadJsonFile() -> [ThaiWordJSON] {
    guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json") else {
        print("❌ Fant ikke thai_top_4000.json i bundle!")
        return []
    }

    do {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([ThaiWordJSON].self, from: data)
        print("✅ Lest inn \(decoded.count) ord fra JSON")
        return decoded
    } catch {
        print("❌ Feil under lesing: \(error)")
        return []
    }
}
