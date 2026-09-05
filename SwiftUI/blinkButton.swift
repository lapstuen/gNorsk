//
//  blinkButton.swift
//  gThai
//
//  Created by Geir Lapstuen on 11/3/26.
//

import SwiftUI

public struct FlashIconButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .green : .gray)
            .scaleEffect(configuration.isPressed ? 1.12 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct FlashIconButton: View {
    public let systemName: String
    public let action: () -> Void

    public init(systemName: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 28))
        }
        .buttonStyle(FlashIconButtonStyle())
    }
}

#Preview {
    FlashIconButton(systemName: "star.fill") {
        print("Trykket")
    }
    .padding()
}
