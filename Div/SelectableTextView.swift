import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    var placeholder: String = ""

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = true
        tv.font = .systemFont(ofSize: 17)
        tv.backgroundColor = .secondarySystemBackground
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // placeholder-ish
        if text.isEmpty {
            tv.text = placeholder
            tv.textColor = .secondaryLabel
        } else {
            tv.text = text
            tv.textColor = .label
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // sync tekst og placeholder
        if text.isEmpty {
            if uiView.text != placeholder {
                uiView.text = placeholder
                uiView.textColor = .secondaryLabel
            }
        } else if uiView.text != text {
            uiView.text = text
            uiView.textColor = .label
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectableTextView
        init(_ parent: SelectableTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if tv.text == parent.placeholder {
                tv.text = ""
                tv.textColor = .label
            }
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            updateSelection(from: tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            updateSelection(from: tv)
        }

        private func updateSelection(from tv: UITextView) {
            guard let range = tv.selectedTextRange,
                  let snippet = tv.text(in: range),
                  snippet != parent.placeholder else {
                parent.selectedText = ""
                return
            }
            parent.selectedText = snippet
        }
    }
}
