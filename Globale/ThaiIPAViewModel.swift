//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/9/25.
//
import SwiftUI

@Observable final class ThaiIPAViewModel {
    var thaiInput: String
    var ipa: String

    init(thaiInput: String = "ดิกชันนารี่") {
        self.thaiInput = thaiInput
        self.ipa = ThaiPhonetics.ipa(for: thaiInput)
    }

    func run() {
        ipa = ThaiPhonetics.ipa(for: thaiInput)
    }
}

struct ThaiIPASheet: View {
    let thaiWord: String
    @State private var model: ThaiIPAViewModel
    
    @State private var showIPADebug = true  // midlertidig

    init(thaiWord: String) {
        self.thaiWord = thaiWord
        _model = State(initialValue: ThaiIPAViewModel(thaiInput: thaiWord))
    }

    var body: some View {
        VStack(spacing: 16) {
            
            HStack {
              //  Text("Thai → IPA (v1)")
              //      .font(.title2).bold()
              //      .foregroundColor(.blue)
               // TextField("ไทย", text: $model.thaiInput)
                //    .font(.custom("Noto Sans", size: 28))
                
                Text(model.thaiInput)
                    .font(.custom("Charis-Regular", size: 28))
                    .padding(.top, 8)
                    .foregroundColor(.green)
                
                Text(" ---> ")
                
                Text(model.ipa)
                    .font(.custom("Charis-Regular", size: 28))
                    .padding(.top, 8)
                    .foregroundColor(.red)
                
                //Text(model.ipa)

            //    Button("Konverter") { model.run() }
               //     .buttonStyle(.borderedProminent)

            }
            
            
            Toggle("IPA‑debug", isOn: $showIPADebug)
            if showIPADebug {
                ThaiIPADebugPanel(thai: thaiWord)
            }

            
        }
        .onAppear() {
            print(ThaiPhonetics.debugAnalysis("จี๋"))
        }
        .padding()
        .frame(minWidth: 420, minHeight: 100)
    }
}

extension View {
    func wireNotifications(_ notifier: Notifier = .shared) -> some View {
        self
            .overlay(alignment: .bottom) {
                if let msg = notifier.message {
                    ToastView(kind: notifier.kind, text: msg)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.snappy, value: msg)
                }
            }
    }
}

#Preview {
    ThaiIPASheet(thaiWord: "ดิกชันนารี่")
}
