//
//  ThaiPartsToolbar.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/20/25.
//


//
//  ThaiPartsToolbar.swift
//  gThai
//

import SwiftUI

struct ThaiPartsToolbar: View {
    let canLookup: Bool
    let lookedUp: Bool
    let isCheckingExternal: Bool
    let onDBLookup: () -> Void
    let onExternal: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Parts from the text")
                .font(.headline)

            Spacer()

            Button(action: onDBLookup) {
                Label("Look up in DB", systemImage: "internaldrive")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canLookup || lookedUp)

            Button(action: onExternal) {
                if isCheckingExternal {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Search externally", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!lookedUp || isCheckingExternal)
        }
    }
}

#if DEBUG
struct ThaiPartsToolbar_Previews: PreviewProvider {
    static var previews: some View {
        SwiftUI.Group {
            ThaiPartsToolbar(
                canLookup: true,
                lookedUp: false,
                isCheckingExternal: false,
                onDBLookup: {},
                onExternal: {}
            )
            .padding()
            .previewDisplayName("Ready for DB lookup")

            ThaiPartsToolbar(
                canLookup: true,
                lookedUp: true,
                isCheckingExternal: true,
                onDBLookup: {},
                onExternal: {}
            )
            .padding()
            .previewDisplayName("Searching externally…")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
