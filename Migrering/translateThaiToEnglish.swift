//
//  GTTestError.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/26/25.
//
//AIzaSyBEgeRWhaA5dF21yJrUZAHvdX0y2CH3kUI    google
//AIzaSyBEgeRWhaA5dF21yJrUZAHvdX0y2CH3kUI    app

import Foundation

enum GTError: Error { case noKey, badStatus(Int), badPayload }

func translateThaiToEnglish(_ text: String) async throws -> String? {
    let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ?? ""
    guard !key.isEmpty else { throw GTError.noKey }

    var req = URLRequest(url: URL(string: "https://translation.googleapis.com/language/translate/v2?key=\(key)")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    struct Body: Encodable { let q: String, source: String, target: String, format: String }
    req.httpBody = try JSONEncoder().encode(Body(q: text, source: "th", target: "en", format: "text"))

    let (data, resp) = try await URLSession.shared.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard code == 200 else { throw GTError.badStatus(code) }

    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    let dataObj = json?["data"] as? [String: Any]
    let translations = dataObj?["translations"] as? [[String: Any]]
    return translations?.first?["translatedText"] as? String
}
