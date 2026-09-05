//
//  test3.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/22/25.
//

import SwiftUI

struct SheetWithXCloseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack {
                Text("Inside sheet with X button")
                    .font(.title)
                    .padding()
                Spacer()
            }

            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 32))
                    .foregroundColor(.gray.opacity(0.8))
                    .padding()
                    .foregroundStyle(Color(.systemBlue))
            }
            .zIndex(1) // 🔑 Sikrer at knappen er klikkbar
        }
    }
}

struct MainPreviewWithX: View {
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Text("View with X button in sheet")
                .font(.title)

            Button("Open sheet") {
                showSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showSheet) {
            SheetWithXCloseView()
        }
        .padding()
    }
}

#Preview {
    MainPreviewWithX()
}
