import UIKit

extension UIAlertController {
    
    /// Lager en alert med OK-knapp og valgfri auto-dismiss
    static func alert(title: String, msg: String, target: UIViewController? = nil, dismissAfter: TimeInterval? = nil) -> UIAlertController {
        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        if let target = target {
            target.present(alert, animated: true) {
                if let dismissAfter = dismissAfter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter) {
                        alert.dismiss(animated: true)
                    }
                }
            }
        }
        return alert
    }

    /// Legger til en handling og returnerer `self` for chaining
    func withAction(_ title: String, style: UIAlertAction.Style = .default, handler: ((UIAlertAction) -> Void)? = nil) -> UIAlertController {
        self.addAction(UIAlertAction(title: title, style: style, handler: handler))
        return self
    }

    /// Legger til en "Avbryt"-knapp og returnerer `self` for chaining
    func withCancel(title: String = "Avbryt", handler: ((UIAlertAction) -> Void)? = nil) -> UIAlertController {
        self.addAction(UIAlertAction(title: title, style: .cancel, handler: handler))
        return self
    }
}
