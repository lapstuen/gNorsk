//
//  ToastView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/10/25.
//
import SwiftUI

struct ToastView: View {
    let kind: NoticeKind
    let text: String

    private var bg: Color {
        switch kind {
        case .info:    return .blue.opacity(0.85)
        case .success: return .green.opacity(0.85)
        case .warning: return .orange.opacity(0.9)
        case .error:   return .red.opacity(0.95)
        }
    }
    private var icon: String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).imageScale(.large)
            Text(text).lineLimit(3)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 8, y: 4)
    }
}

struct ErrorBanner: View {
    let title: String
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.octagon.fill").imageScale(.large).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 10, y: 6)
        .padding(.horizontal)
    }
}
