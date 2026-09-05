//
//  DivClasses.swift
//  gThai
//
//  Created by Geir Lapstuen on 6/17/25.
//

import SwiftUI
import AVFoundation
import UserNotifications

public var oversettelse = ""
public var utter = AVSpeechUtterance()
public var imageDefault = UIImage(systemName: "photo.artframe")!.withTintColor(.lightGray)
public var imageGlobal = UIImage(systemName: "photo.fill")

public var langForeign = "en"
public var langMotherTongue = "th"
public var group :Int16 = 1
public var languageSpeak = ""
public let antallInList = 9999
public var rate1 :Float = 0.15
public var range : UITextRange?
// public var coredataResult = [ThaiWord]()
public var wordStruct = [ThaiWords]()
public var keyboard = langForeign
public var initDate = Date()

var textViewInt = 0
var EnglishtoNorwegian: Bool = true
var EnglishtoNorwegianText: String = ""
var imagePicker: UIImagePickerController!
var groupMain = 0
var groupOk = 0
var groupNot = 0
var mic: AVAudioSession!
var micShare: AVAudioSession!
var appMic: AVAudioApplication!

public extension UITextField {
   override var textInputMode: UITextInputMode? {
      return UITextInputMode.activeInputModes.filter { $0.primaryLanguage == keyboard }.first ?? super.textInputMode
   }
}

public extension UITextView {
   override var textInputMode: UITextInputMode? {
      return UITextInputMode.activeInputModes.filter { $0.primaryLanguage == keyboard }.first ?? super.textInputMode
   }
}

class CustomTextField: UITextField {

   private func getKeyboardLanguage() -> String? {
      let lang = langForeign
      return lang // here you can choose keyboard any way you need
   }

   override var textInputMode: UITextInputMode? {
      if let language = getKeyboardLanguage() {
         for tim in UITextInputMode.activeInputModes {
            if tim.primaryLanguage!.contains(language) {
               return tim
            }
         }
      }
      return super.textInputMode
   }

   func openURLInSafari(urlString: String) {
      if let url = URL(string: urlString) {
         UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
   }


}

class CustomTextView: UITextView, UIEditMenuInteractionDelegate {

   private func getKeyboardLanguage() -> String? {
      let lang = langForeign
      return lang // here you can choose keyboard any way you need
   }


   override open func buildMenu(with builder: UIMenuBuilder) {

      builder.remove(menu: .services)
      builder.remove(menu: .format)
      builder.remove(menu: .toolbar)
         //  builder.remove(menu: .services.self)   // not work
         //  builder.remove(menu: .writingOptions)  // error
         // builder.remove(menu: .writing)  // error
      builder.remove(menu: .lookup)
      builder.remove(menu: .spelling)

      builder.remove(menu: .lookup)        // Lookup, Translate, Search Web
      builder.remove(menu: .standardEdit)  // Cut, Copy, Paste
      builder.remove(menu: .replace)       // Replace
      builder.remove(menu: .share)
      builder.remove(menu: .speech)
      builder.remove(menu: .edit)
      builder.remove(menu: .standardEdit)

      builder.remove(menu: .autoFill)
      builder.remove(menu: .services)

      builder.remove(menu: .edit)
      builder.remove(menu: .speech)
      builder.remove(menu: .substitutions)
      super.buildMenu(with: builder)

   }



   override var textInputMode: UITextInputMode? {
      if let language = getKeyboardLanguage() {
         for tim in UITextInputMode.activeInputModes {
            if tim.primaryLanguage!.contains(language) {
               return tim
            }
         }
      }
      return super.textInputMode
   }
}
