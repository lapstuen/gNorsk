import SwiftUI

// MARK: - Catalyst: TextEditor som slår på scrolling når innholdet blir for stort
struct AdaptiveTextEditor: UIViewRepresentable {
    @Binding var text: String
    let maxHeight: CGFloat

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AdaptiveTextEditor
        init(_ parent: AdaptiveTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            AdaptiveTextEditor.updateSizing(textView, maxHeight: parent.maxHeight)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false                 // start uten intern scroll
        tv.showsVerticalScrollIndicator = true
        tv.backgroundColor = .clear
        tv.font = .preferredFont(forTextStyle: .body)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        Self.updateSizing(uiView, maxHeight: maxHeight)
    }

    // Kalkuler ønsket høyde og slå på/av intern scroll.
    static func updateSizing(_ tv: UITextView, maxHeight: CGFloat) {
        // Finn naturlig høyde gitt gjeldende bredde
        let width = tv.bounds.width > 0 ? tv.bounds.width : (tv.window?.windowScene?.screen.bounds.width ?? 800)
        let target = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fit = tv.sizeThatFits(target).height

        let needsScroll = fit > maxHeight
        if tv.isScrollEnabled != needsScroll {
            tv.isScrollEnabled = needsScroll
        }
        // Viktig: tving ny layout når innhold endres
        tv.invalidateIntrinsicContentSize()
    }
}

// MARK: - Eksempelbruk
struct EditWordView: View {
    @State private var fonetikk = """
// Normaliser inndata: trim + NFC for thailandske kombitegn
// (mye tekst her for å demonstrere scrolling) ...
"""
    @State private var thai = "โต"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {

#if targetEnvironment(macCatalyst)
                AdaptiveTextEditor(text: $fonetikk, maxHeight: 240) // <- kapp høyden her
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120, maxHeight: 240, alignment: .topLeading)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
#else
                TextEditor(text: $fonetikk)
                    .frame(minHeight: 120, maxHeight: 240, alignment: .topLeading)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
#endif

                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thai").font(.caption).foregroundStyle(.red)
                    TextField("ไทย", text: $thai)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        }
        .scrollIndicators(.visible)          // vis ytre scrollbar
        .scrollBounceBehavior(.basedOnSize)
    }
}

#Preview {
    NoneScrollingEditWordView()
}
