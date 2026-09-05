//
//  NonScrollingTextEditor.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/15/25.
//


import SwiftUI

// MARK: - Non-scrolling TextEditor (kun Catalyst)
struct NonScrollingTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false            // <- nøkkelen
        tv.showsVerticalScrollIndicator = false
        tv.backgroundColor = .clear
        tv.font = .preferredFont(forTextStyle: .body)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

// MARK: - Eksempel
struct NoneScrollingEditWordView: View {
    @State private var fonetikk = """
// Normaliser inndata: trim + NFC for thailandske kombitegn
// ...
"""
    @State private var thai = "โต"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {

#if targetEnvironment(macCatalyst)
                // Gjør TextEditor ikke-scrollende i Catalyst
                NonScrollingTextEditor(text: $fonetikk)
                    .frame(minHeight: 100, alignment: .topLeading)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
#else
                // iOS kan fint scrolle inni editoren hvis du ønsker
                TextEditor(text: $fonetikk)
                    .frame(minHeight: 220, alignment: .topLeading)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
#endif

                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thai")
                        .font(.caption).foregroundStyle(.red)
                    TextField("ไทย", text: $thai)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        }
        // 3) Vis scrollbar i hovedvinduet
        .scrollIndicators(.visible)               // iOS 17+ / macOS 14+ (Catalyst)
        .scrollBounceBehavior(.basedOnSize)       // føles mer "mac"
    }
}

#Preview {
    EditWordView()
}
