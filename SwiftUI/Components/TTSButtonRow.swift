//
//  TTSButtonRow.swift
//  gThai
//
//  Created by Claude on 12/4/25.
//

import SwiftUI
import AVFoundation

/// En rad med uttale-knapper fra forskjellige TTS-kilder
/// Brukes for å sammenligne uttale når én kilde gir feil resultat
struct TTSButtonRow: View {
    let text: String
    let openURL: OpenURLAction

    // Hold referanse til synthesizer så den ikke blir deallokert
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        HStack(spacing: 10) {
            // === DIREKTE LYD (TTS) ===

   //         // 1. Google Cloud TTS (API)
   //         Button {
   //             CloudTTSTest.speakNorsk(text)
   //         } label: {
   //             VStack {
   //                 Image(systemName: "cloud.fill")
   //                     .font(.system(size: 20))
   //           //      Text("")
   //           //          .font(.caption2)
   //             }
   //         }
   //         .buttonStyle(.bordered)
   //         .tint(.blue)

            // 2. Apple Narisa (Enhanced voice)
            Button {
                g.talkTh(talkText: text, rate: 0.5, language: "nb-NO")
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20))
               //     Text("")
                //        .font(.caption2)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // 3. Apple Kanya (Compact voice)
            Button {
                speakWithKanya(text)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20))
                //    Text("")
               //         .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .tint(.mint)

            Divider()
                .frame(height: 30)

            // === WEBSIDE-OPPSLAG ===

            // 4. Forvo - Ekte uttaler fra native speakers
            Button {
                openForvo(text)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 20))
                 //   Text("")
                //        .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .tint(.purple)

            // 5. Papago (Naver)
            Button {
                openPapago(text)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "p.circle.fill")
                        .font(.system(size: 20))
                  //  Text("")
                  //      .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .tint(.green)

            // 6. Google Translate
            Button {
                tapGoogleTranslate(text)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 20))
              //      Text("")
              //          .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)

            // 7. Thai2English.com
            Button {
                openThai2English(text)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "globe.asia.australia")
                        .font(.system(size: 20))
              //      Text("")
              //          .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(.vertical, 8)
    }

    // MARK: - TTS Helpers

    private func speakWithKanya(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let storedRate = UserDefaults.standard.double(forKey: "speechRateThai")
        utterance.rate = storedRate > 0 ? Float(storedRate) : 0.4

        // Prøv Kanya-stemmen
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.nb-NO.Nora") {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "nb-NO")
        }

        synthesizer.speak(utterance)
    }

    private func openThai2English(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") else { return }
        openURL(url)
    }

    private func openForvo(_ text: String) {
        // Forvo trenger thai-tekst direkte i URL-en (ikke percent-encoded)
        // Bruker search i stedet for word for bedre kompatibilitet
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://forvo.com/search/\(encoded)/no/") else { return }
        openURL(url)
    }

    private func tapGoogleTranslate(_ text: String) {
        openGoogleTranslate(text, using: openURL)
    }

    private func openPapago(_ text: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://papago.naver.com/?sk=no&tk=en&st=\(encoded)") else { return }
        openURL(url)
    }
}

#Preview {
    TTSButtonRow(text: "ขนาด", openURL: OpenURLAction { _ in .handled })
        .padding()
}
