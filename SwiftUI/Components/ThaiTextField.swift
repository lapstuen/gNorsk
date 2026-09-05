//
//  ThaiTextField.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/15/25.
//
import SwiftUI
import UIKit

struct ThaiTextField: UIViewRepresentable {
   @Binding var text: String

   func makeUIView(context: Context) -> UITextField {
      let textField = UITextField()
      textField.font = UIFont.systemFont(ofSize: 26, weight: .semibold)
     // textField.borderStyle = .roundedRect
      textField.adjustsFontSizeToFitWidth = false
    //  textField.minimumFontSize = 22
      textField.delegate = context.coordinator
      return textField
   }

   func updateUIView(_ uiView: UITextField, context: Context) {
      uiView.text = text
   }

   func makeCoordinator() -> Coordinator {
      Coordinator(self)
   }

   class Coordinator: NSObject, UITextFieldDelegate {
      var parent: ThaiTextField

      init(_ parent: ThaiTextField) {
         self.parent = parent
      }

      func textFieldDidChangeSelection(_ textField: UITextField) {
         parent.text = textField.text ?? ""
      }
   }
}
