//
//  AppleTranslationService.swift
//  gNorsk
//
//  Delt oversettelsestjeneste som bruker Apples on-device Translation-rammeverk
//  (iOS 17.4+, norsk bokmål/svensk/dansk/thai lagt til i iOS 27) i stedet for det
//  tidligere uoffisielle Google-endepunktet (translate.googleapis.com/translate_a/single
//  ?client=gtx) som ble rate-limitet/blokkert av Google under vanlig bruk.
//
//  `TranslationSession` kan kun hentes via SwiftUI-modifieren `.translationTask(_:action:)`
//  festet til et View — det finnes ingen fristående klasse man kan instansiere direkte.
//  Løsningen her: én sesjon-vertsplass festes til app-roten (gNorskApp.swift, alltid montert
//  så lenge appen kjører), og all oversettelse — fra View-kode og fra vanlige klasser som
//  GlFunctions — går via denne singletonen. Ett språkpar dekkes av én sesjon om gangen, så
//  forespørsler køes og prosesseres sekvensielt.
//
import Foundation
import Translation

@Observable
final class AppleTranslationService {
    static let shared = AppleTranslationService()
    private init() {}

    private(set) var configuration: TranslationSession.Configuration?

    private var pending: (text: String, completion: (String?) -> Void)?
    private var queue: [(text: String, from: String, to: String, completion: (String?) -> Void)] = []

    /// Oversetter `text` og returnerer resultatet via `completion`. Ved enhver feil (tom tekst,
    /// ustøttet språkpar, on-device-oversettelse som feiler) kalles `completion(nil)` — kalleren
    /// skal da vise en feilmelding og la feltet stå tomt/uendret, ikke late som kildeteksten var
    /// en gyldig oversettelse.
    func translate(text: String, fromLanguage: String, toLanguage: String, completion: @escaping (String?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil)
            return
        }
        queue.append((
            text: trimmed,
            from: Self.appleLanguageIdentifier(for: fromLanguage),
            to: Self.appleLanguageIdentifier(for: toLanguage),
            completion: completion
        ))
        if pending == nil {
            processNext()
        }
    }

    /// Google-oversettelseskodene brukt ellers i prosjektet ("no", "th", "en", "zh-CN", ...) er
    /// stort sett gyldige BCP-47-koder, med ett kjent unntak: Apples norsk-variant er spesifikt
    /// Bokmål ("nb"), ikke den generiske makrospråk-koden "no".
    private static func appleLanguageIdentifier(for code: String) -> String {
        code == "no" ? "nb" : code
    }

    private func processNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        pending = (text: next.text, completion: next.completion)
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: next.from),
            target: Locale.Language(identifier: next.to)
        )
    }

    /// Kalles fra `.translationTask`-modifieren festet til app-roten.
    @MainActor
    func handle(session: TranslationSession) async {
        guard let pending else { return }
        do {
            let response = try await session.translate(pending.text)
            pending.completion(response.targetText)
        } catch {
            pending.completion(nil)
        }
        self.pending = nil
        processNext()
    }
}
