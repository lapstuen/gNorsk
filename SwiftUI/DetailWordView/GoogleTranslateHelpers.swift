//
//  GoogleTranslateHelpers.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/20/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private let googleTranslateWebBase = "https://translate.google.com/?sl=no&tl=en&text=%@&op=translate"
private let googleTranslateAppBase = "googletranslate://translate?source=no&target=en&text=%@"

private var isGoogleTranslateAppInstalled: Bool {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    guard let scheme = URL(string: "googletranslate://") else { return false }
    return UIApplication.shared.canOpenURL(scheme)
    #else
    return false
    #endif
}

/// Build a Google Translate URL for a Thai word.
/// On iOS, returns the native app deep link if the app is installed; otherwise web URL.
func googleTranslateURL(for word: String) -> URL? {
    guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    let template = isGoogleTranslateAppInstalled ? googleTranslateAppBase : googleTranslateWebBase
    return URL(string: String(format: template, encoded))
}

/// Open a single word in Google Translate using an injected OpenURLAction.
@MainActor
func openGoogleTranslate(_ word: String, using openURL: OpenURLAction) {
    if let url = googleTranslateURL(for: word) {
        openURL(url)
    }
}

/// Open many words with a tiny delay so the browser doesn’t block them.
@MainActor
func openGoogleTranslateBatch(_ terms: [String], using openURL: OpenURLAction) async {
    for t in terms {
        if let url = googleTranslateURL(for: t) {
            openURL(url)
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 s
        }
    }
}