//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/6/25.
//
import SwiftUI


private struct ThaiMockWord: Identifiable {
    let id = UUID()
    let thaiWord: String
    let sentence: String
    let groupId: Int16
}

private struct ThaiGridItemMock: View {
    let word: ThaiMockWord
    @Binding var moveToPinnedGroup: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(word.thaiWord)
                .font(.title2)
                .bold()
            Text(word.sentence)
                .font(.subheadline)
                .foregroundColor(.gray)
            if moveToPinnedGroup {
                Text("📌 flyttes til pinned")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
