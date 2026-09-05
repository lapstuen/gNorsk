//
//  TranslateText2.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/7/25.
//
import SwiftUI

/// Tidligere kalte denne funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den delte
/// AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift). Signaturen er
/// beholdt uendret ([String], Error?) — som før inneholder resultatarrayet enten ett element
/// (oversettelsen) eller er tomt ved feil, slik at alle kallere kan stå uendret.
func translateText2(soureLanguage: String, toLanguage: String, text: String, completionHandler: @escaping ([String], Error?) -> Void) {
    AppleTranslationService.shared.translate(text: text, fromLanguage: soureLanguage, toLanguage: toLanguage) { result in
        DispatchQueue.main.async {
            if let result {
                completionHandler([result], nil)
            } else {
                completionHandler([], NSError(domain: "Translation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not translate"]))
            }
        }
    }
}
