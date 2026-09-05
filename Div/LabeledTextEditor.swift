//
//  LabeledTextEditor.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/7/25.
//
import SwiftUI

struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.red)

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                )
        }
    }
}
