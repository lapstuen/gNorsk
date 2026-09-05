//
//  DictationHelper.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/13/25.
//
import Foundation
import AVFoundation
import Speech

class DictationHelper: NSObject, ObservableObject {
   @Published var recognizedText: String = ""

   private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "nb-NO"))!
   private let audioEngine = AVAudioEngine()
   private var recognitionTask: SFSpeechRecognitionTask?
   private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var request: SFSpeechAudioBufferRecognitionRequest?

   func startDictation() {
      requestPermissions { [weak self] granted in
         guard granted, let self = self else { return }
         self.beginRecognition()
      }
   }

   
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    completion(authStatus == .authorized && micGranted)
                }
            }
        }
    }

   private func beginRecognition() {
      recognitionTask?.cancel()
      recognitionTask = nil
      recognizedText = ""

      let audioSession = AVAudioSession.sharedInstance()
      try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
      try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

      recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
      guard let recognitionRequest = recognitionRequest else { return }

      recognitionRequest.shouldReportPartialResults = true

      
       
       
       let inputNode = audioEngine.inputNode
       let format = inputNode.outputFormat(forBus: 0)
//
    //  inputNode.removeTap(onBus: 0)
    //  inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    //     recognitionRequest.append(buffer)
       
       inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
           // peak-meter kode …
           self?.request?.append(buffer)   // <- denne må matche property-navnet ditt
       }
       
    //   inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
    //       // Enkelt peak-nivå for feilsøk
    //       let frames = Int(buffer.frameLength)
    //       if let ptr = buffer.floatChannelData?[0] {
    //           var peak: Float = 0
    //           for i in 0..<frames {
    //               peak = max(peak, abs(ptr[i]))
    //           }
    //           if peak > 0.001 {
    //               print("🔊 mic peak:", peak)
    //           }
    //       }
//
    //       // Husk å sende buffer videre til request
    //       self?.request?.append(buffer)
    //   }
       
       
       
      

      recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
         if let result = result {
            DispatchQueue.main.async {
               self.recognizedText = result.bestTranscription.formattedString
            }
         }
         if error != nil || (result?.isFinal ?? false) {
            self.stopDictation()
         }
      }

      audioEngine.prepare()
      try? audioEngine.start()
       
       let req = SFSpeechAudioBufferRecognitionRequest()
       req.shouldReportPartialResults = true
       self.request = req
   }

   func stopDictation() {
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
      recognitionRequest?.endAudio()
      recognitionTask?.cancel()
      try? AVAudioSession.sharedInstance().setActive(false)
   }
}
