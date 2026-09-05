//
//  StatView.swift
//  gThai
//
//  Simple stat display component
//

import SwiftUI

struct StatView: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    HStack(spacing: 12) {
        StatView(title: "New", value: "5", color: .blue)
        StatView(title: "Learned", value: "3", color: .green)
        StatView(title: "Retry", value: "2", color: .orange)
    }
    .padding()
}
