//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/22/25.
//
import SwiftUI

struct SFButtonColor: View {
    let name: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .frame(width: 90, height: 90)
                .background(color)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
