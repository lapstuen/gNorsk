//
//  InfoFieldView.swift
//  gThai
//
//  Created by Claude Code on 9/28/25.
//

import SwiftUI

struct InfoFieldView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 12) {
        InfoFieldView(label: "Example", value: "This is a value")
        InfoFieldView(label: "Long text", value: "This is a much longer text that can span multiple lines to show how the component handles long content")
        InfoFieldView(label: "Short", value: "OK")
    }
    .padding()
}