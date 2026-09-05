//
//  testPreview.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/22/25.
//

import SwiftUI

struct SheetContentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Inside sheet 👋")
                .font(.title)

            Button(action: {
                dismiss()
            }) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct MainPreviewView: View {
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Text("This is the main view")
                .font(.title)

            Button("Open sheet") {
                showSheet = true
            }
            .buttonStyle(.bordered)

        }
        .sheet(isPresented: $showSheet) {
            SheetContentView()
        }
        .padding()
    }
}

#Preview {
    MainPreviewView()
}
