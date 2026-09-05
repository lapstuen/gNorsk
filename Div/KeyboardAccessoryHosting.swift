/*
import SwiftUI
import UIKit

struct KeyboardAccessoryHosting<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> HostingController {
        let vc = HostingController(rootView: AnyView(content))
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ uiViewController: HostingController, context: Context) {
        uiViewController.rootView = AnyView(content)
    }

    final class HostingController: UIViewController {
        var rootView: AnyView {
            didSet {
                accessoryHosting.rootView = rootView
                accessoryHosting.view.invalidateIntrinsicContentSize()
            }
        }

        private let accessoryHosting: UIHostingController<AnyView>
        private let hiddenTextField = UITextField(frame: .zero)

        init(rootView: AnyView) {
            self.rootView = rootView
            self.accessoryHosting = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)

            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false

            hiddenTextField.isHidden = true
            hiddenTextField.isUserInteractionEnabled = false
            hiddenTextField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hiddenTextField)

            NSLayoutConstraint.activate([
                hiddenTextField.widthAnchor.constraint(equalToConstant: 0),
                hiddenTextField.heightAnchor.constraint(equalToConstant: 0),
                hiddenTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hiddenTextField.topAnchor.constraint(equalTo: view.topAnchor)
            ])

            accessoryHosting.view.backgroundColor = .clear
            hiddenTextField.inputAccessoryView = accessoryHosting.view
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hiddenTextField.becomeFirstResponder()
        }
    }
}
*/
