//
//  PhotoWrapper.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/7/25.
//
import SwiftUI

struct PhotoViewControllerWrapper: UIViewControllerRepresentable {
    var initialSearchText: String = ""
    var onSavePhoto: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = PhotoVC.instantiate()
        vc.modalPresentationStyle = .formSheet
        vc.preferredContentSize = CGSize(width: 375, height: 300)
        vc.initialSearchText = initialSearchText
        vc.onSavePhoto = { image in
            onSavePhoto(image)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
