//
//  SelectingTextEditor.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/16/25.
//
import SwiftUI
import UIKit

struct SelectingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var onWordSelected: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.font = .systemFont(ofSize: 30)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectingTextEditor
        init(_ parent: SelectingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let ns = textView.text as NSString
            let sel = textView.selectedRange

            // Hvis brukeren har markert noe: bruk det
            if sel.length > 0 {
                let s = ns.substring(with: sel)
                parent.onWordSelected(s)
                return
            }

            // Ellers: finn “ordet” ved caret (avgrenset av blank/punkt.)
            let delims = CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)

            var start = sel.location
            while start > 0,
                  let u = Unicode.Scalar(ns.character(at: start - 1)),
                  !delims.contains(u) {
                start -= 1
            }

            var end = sel.location
            while end < ns.length,
                  let u = Unicode.Scalar(ns.character(at: end)),
                  !delims.contains(u) {
                end += 1
            }

            if end > start {
                let token = ns.substring(with: NSRange(location: start, length: end - start))
                parent.onWordSelected(token)
            }
        }
    }
}
