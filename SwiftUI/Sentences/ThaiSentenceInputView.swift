import SwiftUI

struct ThaiSentenceInputView: View {
    @Binding var sentenceText: String
    var speech: SpeechManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thai sentence:")
                .font(.headline)

            TextField("Type or speak the Thai sentence...", text: $sentenceText)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            // Show audio level while listening
            if case .recording = speech.status {
                Text("🎤 Listening...")
                    .foregroundColor(.blue)

                MicLevelView(level: speech.level)
                    .frame(height: 10)
                    .padding(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
            }
        }
        .padding()
        .onAppear {
            if case .idle = speech.status { speech.requestAuth() }
        }
        .onDisappear { speech.stop() }
    }
}

// Kopiert MicLevelView fra ThaiPronounceCheckView
struct MicLevelView: View {
    var level: Float       // 0.0–1.0
    let bars = 8
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars) { index in
                Rectangle()
                    .fill(index < Int(level * Float(bars)) ? Color.blue : Color.clear)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

