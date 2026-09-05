//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/22/25.
//
import SwiftUI

struct IconTextButton: View {
    let imageName: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)

                Text(title)
                    .font(.headline)
                    .bold()
            }
            .frame(width: 120, height: 120)
            .background(color)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SFTextButtonLarge: View {
    let systemName: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)

                Text(title)
                    .font(.headline)
                    .bold()
            }
            .frame(width: 380, height: 70)
            .background(color)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SFTextButton: View {
    let systemName: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)

                Text(title)
                    .font(.headline)
                    .bold()
            }
            .frame(width: 120, height: 120)
            .background(color)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


