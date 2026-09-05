//
//  ThaiPronunciationView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/18/25.
//


// ThaiPronunciationView.swift
import SwiftUI

struct ThaiPronunciationView: View {
    @Binding var thaiWord: String
    @Binding var selectedSnippet: String
    @Binding var ipaSnippet: String
    let sentenceInput: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fonetic and tags")

            HStack {
                Button("Go") {
                    let probe = selectedSnippet.isEmpty ? sentenceInput : selectedSnippet
                    ipaSnippet = ThaiPhonetics.ipa(for: probe)
                }
                Text("IPA: \(ipaSnippet)")
                    .font(.title)
                    .foregroundColor(.blue)
            }
            .padding(.top, 8)
        }
    }
}