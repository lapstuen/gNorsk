//
//  MyUniformTextFieldModifier.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/16/25.
//


import SwiftUI

struct MyUniformTextFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    // felles farger
    private let bg = Color.blue.opacity(0.12)
    private let border = Color.blue.opacity(0.55)

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        base(content)
            .frame(maxWidth: 220)             // matcher knapp på Catalyst
            .font(.system(size: 15))
        #elseif os(macOS)
        base(content)
            .frame(maxWidth: 180)             // matcher knapp på macOS
            .font(.system(size: 13))
        #else
        base(content)
            .frame(maxWidth: .infinity)       // matcher knapp på iOS
            .font(.system(size: 18))
        #endif
    }

    @ViewBuilder
    private func base(_ content: Content) -> some View {
        content
            .textFieldStyle(.plain)            // vi lager vår egen chrome
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isFocused ? border : Color.clear, lineWidth: 1)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            )
            .focused($isFocused)               // for fokus-border
    }
}

extension View {
    func uniformTextField() -> some View {
        modifier(MyUniformTextFieldModifier())
    }
}