import SwiftUI
import Speech

@MainActor
class SentenceInputViewModel: ObservableObject {
    @Published var sentenceText: String = ""
    @Published var speechManager = SpeechManager(locale: Locale(identifier: "th-TH"))
    
    func startListening() {
        speechManager.start()
    }
    
    func stopListening() {
        if !speechManager.transcript.isEmpty {
            sentenceText = speechManager.transcript
        }
        speechManager.stop()
    }
}


