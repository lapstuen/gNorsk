//
//  languageClass.swift
//  gThai
//
//  Created by Macbook Pro on 13/02/2022.
//

import Foundation

public struct language {
    var name: String
    var langCode: String
    var favorit: String?

    init(_ langx:String,_ code:String) {
        name = langx
        langCode = code
    }
}


import UIKit

class TopBarView: UIView {

   let backButton = UIButton(type: .system)
   let titleLabel = UILabel()
   let starButton = UIButton(type: .system)

   override init(frame: CGRect) {
      super.init(frame: frame)
      setupView()
   }

   required init?(coder: NSCoder) {
      super.init(coder: coder)
      setupView()
   }

   private func setupView() {
      backgroundColor = .systemBackground

         // Back button

      let config = UIImage.SymbolConfiguration(pointSize: 33, weight: .regular)
      let image = UIImage(systemName: "arrowshape.left.circle.fill", withConfiguration: config)

      backButton.setImage(image, for: .normal)


      backButton.tintColor = .systemBlue
      backButton.translatesAutoresizingMaskIntoConstraints = false

         // Title label
      titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
      titleLabel.textAlignment = .center
      titleLabel.lineBreakMode = .byTruncatingTail
      titleLabel.translatesAutoresizingMaskIntoConstraints = false

         // Star button

      let config2 = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
      let image2 = UIImage(systemName: "menucard", withConfiguration: config2)
      starButton.setImage(image2, for: .normal)


      addSubview(backButton)
      addSubview(titleLabel)
      addSubview(starButton)

      NSLayoutConstraint.activate([
         // Back button
         backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
         backButton.centerYAnchor.constraint(equalTo: centerYAnchor),

         // Star button
         starButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
         starButton.centerYAnchor.constraint(equalTo: centerYAnchor),

         // Title label centered
         titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
         titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
         titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140)
      ])
   }

   func setTitle(_ text: String) {
      titleLabel.text = text
   }
}


import UIKit

class BottomBarView: UIView {

   //let searchButton = UIButton()
   let normalButton = UIButton()
   let waitButton = UIButton()
   let canButton = UIButton()
  // let confirmButton = UIButton()

   override init(frame: CGRect) {
      super.init(frame: frame)
      setup()
   }

   required init?(coder: NSCoder) {
      super.init(coder: coder)
      setup()
   }

   private func setup() {
      backgroundColor = UIColor.systemGray6.withAlphaComponent(0.95)

      let stack = UIStackView(arrangedSubviews: [
         normalButton, waitButton, canButton
      ])
      stack.axis = .horizontal
      stack.distribution = .equalSpacing
      stack.alignment = .center
      stack.spacing = 20
      stack.translatesAutoresizingMaskIntoConstraints = false

      addSubview(stack)

      NSLayoutConstraint.activate([
         stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
         stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
         stack.topAnchor.constraint(equalTo: topAnchor),
         stack.bottomAnchor.constraint(equalTo: bottomAnchor)
      ])

         // Symboler
    //  searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)


      let config = UIImage.SymbolConfiguration(pointSize: 33, weight: .regular)
      let image = UIImage(systemName: "text.magnifyingglass", withConfiguration: config)
      normalButton.setImage(image, for: .normal)

     // normalButton
     //    .setImage(UIImage(systemName: "text.magnifyingglass"), for: .normal)
      //waitButton.setImage(UIImage(systemName: "hourglass"), for: .normal)


      let image3 = UIImage(systemName: "hourglass", withConfiguration: config)
      waitButton.setImage(image3, for: .normal)


      let image2 = UIImage(systemName: "checkmark", withConfiguration: config)
      canButton.setImage(image2, for: .normal)



     // canButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
    //  confirmButton.setImage(UIImage(systemName: "checkmark"), for: .normal)

   }
}
