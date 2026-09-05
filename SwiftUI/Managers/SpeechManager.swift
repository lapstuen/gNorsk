import SwiftUI
import Speech
import AVFoundation
import Observation

@Observable
final class SpeechManager {
        enum Status: Equatable {    // ← etter
            case idle, requestingAuth, ready, recording, denied, unavailable
            case error(String)
        }

    var status: Status = .idle
    var transcript: String = ""

    private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    var level: Float = 0   // 0.0 → 1.0 for visning i UI

    var onTranscriptUpdate: ((String) -> Void)?
    var onTranscriptComplete: ((String) -> Void)?

    private var silenceTimer: Timer?
    private var hasReceivedFirstWord = false
    var firstWordTimeout: TimeInterval = 10.0
    var silenceAfterWordTimeout: TimeInterval = 2.0
    var audioMode: AVAudioSession.Mode = .measurement

    init(locale: Locale = Locale(identifier: "nb-NO")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        if let r = recognizer {
            print("🔎 Recognizer locale:", r.locale.identifier, "available:", r.isAvailable)
        } else {
            print("🔎 Recognizer is nil for locale \(locale.identifier)")
        }
        if recognizer == nil || !(recognizer?.isAvailable ?? false) {
            status = .unavailable
        }
    }

    @MainActor
    func setLocale(_ locale: Locale) {
        stop()
        recognizer = SFSpeechRecognizer(locale: locale)
        if recognizer == nil || !(recognizer?.isAvailable ?? false) {
            status = .unavailable
        } else {
            status = .ready
        }
    }

    @MainActor
    func requestAuth() {
        status = .requestingAuth
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                switch auth {
                case .authorized:
                    self?.status = .ready
                case .denied:        self?.status = .denied
                case .restricted:    self?.status = .unavailable
                case .notDetermined: self?.status = .idle
                @unknown default:    self?.status = .unavailable
                }
            }
        }
    }


  
    @MainActor
    func start() {
        // Avklar status først
        switch status {
        case .ready, .recording: break
        case .idle:
            requestAuth()
            return
        case .requestingAuth, .denied, .unavailable:
            return
        case .error:
            break
        }

        // Reset ev. tidligere kjøring
        stop()

        // (Valgfritt) logg opptakstillatelse
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("🎤 Record permission:", granted)
        }

        do {
            if audioEngine == nil { audioEngine = AVAudioEngine() }
            let session = AVAudioSession.sharedInstance()
            // Catalyst liker ofte .playAndRecord bedre enn .record
            try session.setCategory(.playAndRecord, mode: audioMode, options: [.duckOthers])
            // (Valgfritt) hvis du bruker USB-mic og vil være eksplisitt:
             if let usb = session.availableInputs?.first(where: { $0.portType == .usbAudio }) {
                 try? session.setPreferredInput(usb)
                 print("🎙️ Bruker input:", usb.portName)
             }
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // 1) Lag request først
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = false
            self.request = req

            // 2) Tap input og beregn nivå
            let input = audioEngine!.inputNode
            let format = input.outputFormat(forBus: 0)
            print("🎚️ Input format:", format)

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }

                // 🔊 Enkel peak-beregning (float eller int16 fallback)
                var peak: Float = 0
                if let float = buffer.floatChannelData?.pointee {
                    let n = Int(buffer.frameLength)
                    for i in 0..<n { peak = max(peak, abs(float[i])) }
                } else if let i16 = buffer.int16ChannelData?.pointee {
                    let n = Int(buffer.frameLength)
                    for i in 0..<n { peak = max(peak, Float(abs(i16[i])) / Float(Int16.max)) }
                }
                // Skaler og clamp til 0–1 for UI
                let normalized = min(1.0, peak * 20)

                // Oppdater level på main-tråden (for SwiftUI)
                Task { @MainActor in
                    self.level = normalized
                }

                // 🎤 Viktig: send buffer videre til ASR
                self.request?.append(buffer)
                print(buffer)
            }

            // 3) Start engine
            audioEngine!.prepare()
            try audioEngine!.start()
            print("🎤 Started recording, sampleRate:", format.sampleRate)

            // 4) Start task
            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let r = result {
                    Task { @MainActor in
                        self.transcript = r.bestTranscription.formattedString
                        self.onTranscriptUpdate?(r.bestTranscription.formattedString)
                        self.hasReceivedFirstWord = true
                        self.resetSilenceTimer()
                        if r.isFinal { self.handleFinalTranscript() }
                    }
                }
                if let e = error {
                    // Ignorer cancellation (vi kaller task?.cancel() selv i stop()) — kalte
                    // tidligere handleFinalTranscript() uansett, som gjorde at en forsinket
                    // "avbrutt"-feilmelding fra EN økt kunne tømme/stoppe en NY økt som
                    // rakk å starte i mellomtiden (derfor måtte man trykke Start to ganger).
                    let isCancelled = (e as NSError).code == NSUserCancelledError
                    if !isCancelled {
                        print("❌ Speech error:", e.localizedDescription)
                        Task { @MainActor in self.handleFinalTranscript() }
                    }
                }
            }

            status = .recording
            startSilenceTimer()
        } catch {
            status = .error(error.localizedDescription)
            print("❌ Start failed:", error)
        }
    }
    
    
    @MainActor
    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasReceivedFirstWord = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if case .recording = status { status = .ready }
    }

    @MainActor
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: firstWordTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleFinalTranscript()
            }
        }
    }

    @MainActor
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceAfterWordTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleFinalTranscript()
            }
        }
    }

    @MainActor
    func handleFinalTranscript() {
        guard case .recording = status else { return }
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        stop()
        onTranscriptComplete?(finalText)
    }
}

/// Normaliserer thai-tekst for sammenligning (enkelt, utvid ved behov)
private func normalizeThai(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
     .precomposedStringWithCanonicalMapping
     .lowercased()
}

/// SwiftUI-view som starter lytting automatisk og matcher mot target
struct ThaiPronounceCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechManager(locale: Locale(identifier: "nb-NO"))
    let target: String

    
    private var matched: Bool {
        let spoken = normalizeThai(speech.transcript)
        let goal   = normalizeThai(target)
        guard !spoken.isEmpty, !goal.isEmpty else { return false }

        // KUN denne retningen: målsetningen må være fullstendig inneholdt i det som er sagt
        // så langt. Det motsatte (goal.contains(spoken)) var feilen — siden "spoken" er den
        // delvise, voksende live-transkripsjonen, er den nesten alltid en prefiks av målet
        // helt i starten av ytringen, så "OK" trigget straks du sa første ord.
        return spoken.contains(goal)
    }
    
 //   private var matched: Bool {
  //      normalizeThai(speech.transcript) == normalizeThai(target)
 //   }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                TextField("Say the word…", text: .constant(speech.transcript))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Text(target)
                    .font(.title2).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if matched {
                Text("OK 👏👍 ✅")
                    .font(.system(size: 48, weight: .semibold))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            dismiss()
                        }
                    }
            } else {
                Text("Speak Norwegian – microphone active.").font(.headline)
            }

            HStack(spacing: 12) {
                if case .recording = speech.status {
                    Button {
                        speech.stop()
                    } label: { Label("Stopp", systemImage: "stop.fill") }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        speech.`start`()
                    } label: { Label("Start", systemImage: "mic.fill") }
                    .buttonStyle(.borderedProminent)
                }
                
                MicLevelView(level: speech.level)
                    .frame(height: 60)
                    .onAppear {
                        if case .idle = speech.status { speech.requestAuth() }
                    }
                    .onDisappear { speech.stop() }
            }

            // enkel statusindikator
            Text(statusText(speech.status))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            // Stillhets-timeren i SpeechManager er laget for "si ett ord/en setning og send"
            // (andre vinduer) — her skal vi derimot bare fortsette å lytte og sammenligne live
            // mot målsetningen, uten at en kort pause tømmer det du allerede har sagt.
            speech.firstWordTimeout = 3600
            speech.silenceAfterWordTimeout = 3600
            if case .idle = speech.status { speech.requestAuth() }
            // auto-start når klar:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if case .ready = speech.status { speech.start() }
            }
        }
        .onDisappear { speech.stop() }
    }

    private func statusText(_ s: SpeechManager.Status) -> String {
        switch s {
        case .idle: return "Idle"
        case .requestingAuth: return "Requesting speech recognition access…"
        case .ready: return "Ready"
        case .recording: return "Listening…"
        case .denied: return "Access denied (SFSpeechRecognizer)"
        case .unavailable: return "Not available on this device/locale"
        case .error(let m): return "Error: \(m)"
        }
    }
    
    struct MicLevelView: View {
        var level: Float       // 0.0–1.0
        let bars = 12

        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let filled = Float(i + 1) <= level * Float(bars)
                    Capsule()
                        .fill(filled ? .green : .gray.opacity(0.3))
                        .frame(width: 6, height: CGFloat(i + 3) * 6) // stigende høyder
                }
            }
            .animation(.easeOut(duration: 0.08), value: level)
            .accessibilityLabel("Microphone level")
        }
    }
}

#Preview {
    // Preview: bruker mock-target, selve talegjenkjenningen kjører ikke i Preview.
    ThaiPronounceCheckView(target: "จำ")
        .frame(width: 600, height: 320)
}
