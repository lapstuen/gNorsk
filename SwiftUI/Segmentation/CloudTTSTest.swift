import Foundation
import AVFoundation
import Network

enum CloudTTSTest {
    private static var player: AVAudioPlayer?
    private static let synthesizer = AVSpeechSynthesizer()

    /// Slideren i About-skjermen ("speechRateThai") er kalibrert for Apples
    /// innebygde AVSpeechUtterance-skala (0.3...0.8, hvor ~0.5 er normalt).
    /// Google Cloud TTS sin "speakingRate" bruker en helt annen skala (1.0 =
    /// normalt tempo, opp mot 4.0 = veldig raskt) — uten denne omregningen
    /// ville selv "raskest" (0.8) fortsatt vært saktere enn Googles egen
    /// normalhastighet, som er nøyaktig det som gjorde at Norsk aldri kunne
    /// høres "rask" ut uansett hvor du satte slideren.
    private static func googleSpeakingRate(fromStoredRate stored: Double) -> Double {
        let clamped = min(max(stored, 0.3), 0.8)
        let normalized = (clamped - 0.3) / (0.8 - 0.3)   // 0...1
        return 0.6 + normalized * (2.2 - 0.6)             // ≈0.6 (sakte) ... 2.2 (raskt)
    }

    static func speakNorsk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let storedRate = UserDefaults.standard.double(forKey: "speechRateThai")
        let rate = storedRate > 0 ? googleSpeakingRate(fromStoredRate: storedRate) : 0.9

        Task {
            let hasInternet = await NetworkStatus.shared.isOnline()
            Logger.info("[TTS] speakNorsk('\(trimmed)') — internett: \(hasInternet)")

            guard hasInternet else {
                Logger.warning("[TTS] Ingen nett — avbryter uten avspilling")
                await MainActor.run {
                    Notifier.shared.show(.error, "Ingen nettverkstilgang – kan ikke spille Google-uttale")
                }
                return
            }

            do {
                try await testGoogleTTS(trimmed, rate: rate)
                Logger.success("[TTS] Google-uttale spilt av OK for '\(trimmed)'")
            } catch {
                Logger.error("[TTS] Google TTS feilet for '\(trimmed)': \(error)")
                await MainActor.run {
                    Notifier.shared.show(.error, "Google-uttale feilet: \(error.localizedDescription)")
                }
            }
        }
    }

    static func speakNorskOffline(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "nb-NO")
        let storedRate = UserDefaults.standard.double(forKey: "speechRateThai")
        utterance.rate = storedRate > 0 ? Float(storedRate) : 0.45
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AudioSession-feil lokal TTS: \(error)")
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        synthesizer.speak(utterance)
    }

    static func testGoogleTTS(_ text: String, rate: Double = 0.9, languageCode: String = "nb-NO") async throws {
        print("🚀 Starter Google TTS for: '\(text)' (rate: \(rate), language: \(languageCode))")

        let apiKey = APIConfig.googleAPIKey
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!

        let requestBody: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": languageCode,
                "ssmlGender": "FEMALE"
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": rate,
                "pitch": 0.0
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] {
                throw NSError(
                    domain: "CloudTTSTest",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "API error: \(error)"]
                )
            }

            if let audioContent = json["audioContent"] as? String,
               let audioData = Data(base64Encoded: audioContent) {
                try await playAudio(audioData)
            } else {
                throw NSError(
                    domain: "CloudTTSTest",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing audioContent"]
                )
            }
        } else {
            throw NSError(
                domain: "CloudTTSTest",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
            )
        }
    }

    private static func playAudio(_ audioData: Data) async throws {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AudioSession-feil: \(error)")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_test.mp3")
        try audioData.write(to: tempURL)

        if let p = self.player, p.isPlaying {
            p.stop()
        }

        let newPlayer = try AVAudioPlayer(contentsOf: tempURL)
        self.player = newPlayer
        newPlayer.play()

        while newPlayer.isPlaying {
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        self.player = nil
        try? FileManager.default.removeItem(at: tempURL)
    }
}

final class NetworkStatus {
    static let shared = NetworkStatus()

    func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "NetworkStatusMonitor")

            monitor.pathUpdateHandler = { path in
                let online = path.status == .satisfied
                monitor.cancel()
                continuation.resume(returning: online)
            }

            monitor.start(queue: queue)
        }
    }
}


/*
import Foundation
import AVFoundation

enum CloudTTSTest {
    // Sterk referanse til spiller for robust avspilling
    private static var player: AVAudioPlayer?

    /// Énlinjes fasade: kall denne fra hvor som helst.
    /// - Den starter en Task internt (ingen async/await nødvendig hos kalleren).
    /// - Bruker Google Cloud TTS uten fallback (brukeren kan velge andre kilder manuelt)
    static func speakThai(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                try await testGoogleTTS(trimmed)
            } catch {
                print("⚠️ Cloud TTS feilet: \(error)")
                // Ingen fallback - brukeren kan velge andre TTS-kilder manuelt
            }
        }
    }

    // MARK: - Google Cloud Text-to-Speech Test
    static func testGoogleTTS(_ text: String) async throws {
        print("🚀 Starter Google TTS for: '\(text)'")

        // Du trenger en API key fra Google Cloud Console
        let apiKey = APIConfig.googleAPIKey
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!

        // Google Cloud TTS - bruker Neural2-C som er bekreftet å fungere
        let requestBody: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "th-TH",
                "name": "th-TH-Neural2-C",  // Neural2-C fungerer (bekreftet i APIConfig)
                "ssmlGender": "FEMALE"
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": 0.9,   // Litt saktere for tydelighet
                "pitch": 0.0           // Nøytral pitch - viktig for tonespråk!
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("📡 Sender request til Google...")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")
        }
        print("📦 Mottok data: \(data.count) bytes")

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("📋 JSON keys: \(json.keys)")

            if let error = json["error"] {
                print("❌ API Error: \(error)")
                throw NSError(domain: "CloudTTSTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "API error: \(error)"])
            }

            if let audioContent = json["audioContent"] as? String,
               let audioData = Data(base64Encoded: audioContent) {
                print("🎵 Audio data: \(audioData.count) bytes")
                try await playAudio(audioData)
            } else {
                print("❌ Ingen audioContent funnet i response")
                throw NSError(domain: "CloudTTSTest", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing audioContent"])
            }
        } else {
            throw NSError(domain: "CloudTTSTest", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
    }

    // MARK: - Azure Cognitive Services Test (uendret)
    static func testAzureTTS(_ text: String) async throws {
        let apiKey = "YOUR_AZURE_API_KEY_HERE"
        let region = "eastus"
        let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")!

        let ssml = """
        <speak version='1.0' xml:lang='th-TH'>
            <voice xml:lang='th-TH' xml:gender='Female' name='th-TH-PremwadaNeural'>
                \(text)
            </voice>
        </speak>
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.httpBody = ssml.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        try await playAudio(data)
    }

    // MARK: - Audio Player Helper
    private static func playAudio(_ audioData: Data) async throws {
        print("🔊 Starter audio playback...")

        // Session lik g.talkTh (duckOthers for bedre UX)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ AudioSession-feil: \(error)")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_test.mp3")
        try audioData.write(to: tempURL)
        print("💾 Skrev audio til: \(tempURL)")

        if let p = self.player, p.isPlaying { p.stop() }

        let newPlayer = try AVAudioPlayer(contentsOf: tempURL)
        self.player = newPlayer
        print("🎹 AVAudioPlayer opprettet, duration: \(newPlayer.duration)")

        newPlayer.play()
        print("▶️ Player.play() kalt, isPlaying: \(newPlayer.isPlaying)")

        while newPlayer.isPlaying {
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        print("⏹️ Avspilling ferdig")
        self.player = nil
        try? FileManager.default.removeItem(at: tempURL)
        // valgfritt: try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
*/


