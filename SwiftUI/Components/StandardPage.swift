//
//  StandardPage.swift
//  gThai
//
//  Standard page wrapper for all new views
//  Handles centering, max-width, padding - works on iPhone, iPad, and Mac
//

import SwiftUI

/// Standard page wrapper that works across all platforms
/// Use this for all new views instead of hardcoding sizes
struct StandardPage<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = 700, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: maxWidth)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Variant without automatic ScrollView (for when you need custom scrolling)
struct StandardPageNoScroll<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = 700, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

// MARK: - Preview
#Preview("Standard Page") {
    StandardPage {
        VStack(spacing: 20) {
            Text("Standard Page Example")
                .font(.largeTitle)

            Text("This page automatically centers content and limits width to 700pt.")
                .multilineTextAlignment(.center)

            Button("Button Example") {
                print("Tapped")
            }
            .buttonStyle(.borderedProminent)

            ForEach(1...20, id: \.self) { i in
                Text("Item \(i)")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

#Preview("Without Scroll") {
    StandardPageNoScroll {
        VStack(spacing: 20) {
            Text("No Auto-Scroll")
                .font(.largeTitle)

            Text("Use StandardPageNoScroll when you need custom scroll behavior")
                .multilineTextAlignment(.center)
        }
    }
}
