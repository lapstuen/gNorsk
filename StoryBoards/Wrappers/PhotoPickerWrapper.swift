//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/15/25.
import SwiftUI
import UIKit

//
struct PhotoPickerWrapper: UIViewControllerRepresentable {
   var onSave: ([UIImage]) -> Void

   func makeUIViewController(context: Context) -> PhotoVC {
      let vc = PhotoVC.instantiate() // ✅ Bruker storyboard!

         // Tilpasset: Pakker bildet i array hvis bare ett
      vc.onSavePhoto = { bilde in
         onSave([bilde]) // ✅ sender som array til SwiftUI
      }

      return vc
   }

   func updateUIViewController(_ uiViewController: PhotoVC, context: Context) {
         // vanligvis tom
   }
}
