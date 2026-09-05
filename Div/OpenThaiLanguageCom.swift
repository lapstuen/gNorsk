//
//  OpenThaiLanguageCom.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/9/25.
//
import SwiftUI

@MainActor
func openThaiLanguage(word: String,
                      mode: OpenMode = .search,
                      openURL: OpenURLAction) {
    // Kopier til utklippstavlen (samme som du gjorde)
    UIPasteboard.general.string = word

    // Bygg URL
    let url: URL?
    switch mode {
    case .home:
        url = URL(string: "http://www.thai-language.com")
    case .search:
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        url = URL(string: "http://www.google.com/search?q=site:thai-language.com%20\(encoded)")
    }

    // Åpne
    if let url { openURL(url) }
}

// Valg for hva knappen skal gjøre
enum OpenMode { case home, search }

// Eksempelbruk i SwiftUI:
struct ThaiLanguageButtonsDemo: View {
    @Environment(\.openURL) private var openURL
    let thaiWord: String

    var body: some View {
        HStack(spacing: 12) {
            Button("✪ thai-language (home)") {
                openThaiLanguage(word: thaiWord, mode: .home, openURL: openURL)
            }
            .buttonStyle(.borderedProminent)

            Button("Search on thai-language") {
                openThaiLanguage(word: thaiWord, mode: .search, openURL: openURL)
            }
            .buttonStyle(.bordered)
        }
        .font(.title3)
    }
}
