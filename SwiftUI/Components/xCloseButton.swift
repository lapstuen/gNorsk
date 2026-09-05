//
//  xCloseButton.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/22/25.
//

import SwiftUI

struct XCloseButton: View {
    let alignment: Alignment
    let action: () -> Void

    init(alignment: Alignment = .topLeading, action: @escaping () -> Void) {
        self.alignment = alignment
        self.action = action
    }

    var body: some View {
        // Dette gjør at knappen er klikkbar – og ikke hele overlayen!
        Button(action: action) {
            Image(systemName: "x.square")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.8))
                .padding(16)
                .contentShape(Rectangle()) // viktig for å gjøre hele området klikkbart
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .allowsHitTesting(true) // sikre
        .zIndex(1)
    }
}
