//
//  UIViewController+Instantiate.swift
//  gThai
//
//  Created by Geir Lapstuen on 6/13/25.
//

import UIKit

protocol Storyboarded {
   static func instantiate() -> Self
}

extension Storyboarded where Self: UIViewController {
   static func instantiate() -> Self {
         // "PreviewVC" -> "Preview"
      let fullName = String(describing: self) // f.eks. "PreviewVC"
      guard fullName.hasSuffix("VC") else {
         fatalError("Class name must end with 'VC'")
      }

      let storyboardName = String(fullName.dropLast(2)) // f.eks. "Preview"
      let storyboard = UIStoryboard(name: storyboardName, bundle: .main)

     // print("ViewController with ID \(fullName) not found in \(storyboardName).storyboard")
      guard let vc = storyboard.instantiateViewController(withIdentifier: fullName) as? Self else {
         print("ViewController with ID \(fullName) not found in \(storyboardName).storyboard")
         fatalError("ViewController with ID \(fullName) not found in \(storyboardName).storyboard")
      }

      return vc
   }
}
