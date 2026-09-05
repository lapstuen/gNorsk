import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Google Translate URL helpers

func googleTranslateURL(for word: String) -> URL? {
    guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    return URL(string: "https://translate.google.com/?sl=no&tl=en&text=\(encoded)&op=translate")
}

/// On iOS: tries the native app first, falls back to web if not installed.
/// On Mac Catalyst: opens web directly.
@MainActor
func openGoogleTranslate(_ word: String, targetLang: String = "en", using openURL: OpenURLAction) {
    guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
    let webURL = URL(string: "https://translate.google.com/?sl=no&tl=\(targetLang)&text=\(encoded)&op=translate")

    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    if let appURL = URL(string: "googletranslate://?sl=no&tl=\(targetLang)&text=\(encoded)") {
        UIApplication.shared.open(appURL, options: [:]) { success in
            guard !success, let web = webURL else { return }
            DispatchQueue.main.async { openURL(web) }
        }
        return
    }
    #endif

    if let web = webURL { openURL(web) }
}

// MARK: - Button

struct GoogleTranslateButton: View {
    let thaiWord: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Look up in Google Translate") {
            openGoogleTranslate(thaiWord, using: openURL)
        }
        .font(.title)
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    GoogleTranslateButton(thaiWord: "มอง")
}
