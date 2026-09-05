//
//  MarkdownEditorWrapper.swift
//  gThai
//
//  SwiftUI wrapper for MarkdownViewController
//  Presents it EXACTLY like gInfo does (using UIKit present)
//

import SwiftUI
import UIKit

struct MarkdownEditorWrapper: UIViewControllerRepresentable {
    @Binding var markdownText: String
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> WrapperViewController {
        return WrapperViewController(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: WrapperViewController, context: Context) {
        if isPresented && !context.coordinator.isPresenting {
            context.coordinator.presentMarkdown(from: uiViewController, currentText: markdownText)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(markdownText: $markdownText, isPresented: $isPresented)
    }

    // Wrapper VC for presenting
    class WrapperViewController: UIViewController {
        let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        @Binding var markdownText: String
        @Binding var isPresented: Bool
        var isPresenting = false
        weak var markdownVC: MarkdownViewController?

        init(markdownText: Binding<String>, isPresented: Binding<Bool>) {
            self._markdownText = markdownText
            self._isPresented = isPresented
        }

        func presentMarkdown(from viewController: UIViewController, currentText: String) {
            guard !isPresenting else { return }
            isPresenting = true

            let vc = MarkdownViewController()
            markdownVC = vc

            // EXACTLY like gInfo
            vc.modalPresentationStyle = .formSheet
            vc.preferredContentSize = CGSize(width: 1075, height: 1300)
            vc.markdownText = currentText

            print("DEBUG: Åpner markdown-editor med \(currentText.count) tegn")
            print("DEBUG: Innhold: '\(currentText.prefix(100))...')")

            // Set delegate to catch dismissal by swipe/gesture
            vc.presentationController?.delegate = self

            vc.onSave = { [weak self] newText, _, _, _ in
                guard let self = self else { return }
                print("DEBUG: onSave kalt med \(newText.count) tegn")
                print("DEBUG: Nytt innhold: '\(newText.prefix(100))...')")
                DispatchQueue.main.async {
                    self.markdownText = newText
                    print("DEBUG: Oppdaterte markdownText binding")
                    // If already dismissed by swipe, just clean up
                    if viewController.presentedViewController != nil {
                        viewController.presentedViewController?.dismiss(animated: true) {
                            self.isPresented = false
                            self.isPresenting = false
                        }
                    } else {
                        self.isPresented = false
                        self.isPresenting = false
                    }
                }
            }

            viewController.present(vc, animated: true)
        }

        // Called when user dismisses by swiping down or tapping outside
        // Note: viewWillDisappear (which calls saveIfNeeded) is called BEFORE this
        // so onSave has already been called and markdownText updated
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            DispatchQueue.main.async {
                // Just clean up the presentation state
                // The text has already been saved via onSave callback in viewWillDisappear
                self.isPresented = false
                self.isPresenting = false
            }
        }
    }
}
