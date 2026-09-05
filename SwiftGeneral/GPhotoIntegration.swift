import Foundation
import CoreData
#if canImport(UIKit)
import UIKit

extension Notification.Name {
    static let gPhotoResult = Notification.Name("gPhotoPhotoResult")
}

struct GPhotoIntegration {
    /// ObjectID til ordet/kortet som sist ba om et bilde fra gPhoto. Brukes av mottakere
    /// (f.eks. hvert kort i griden) til å sjekke at et innkommet .gPhotoResult faktisk var
    /// ment for dem, siden NotificationCenter broadcaster til ALLE lyttere samtidig.
    /// Uten denne sjekken vil ethvert bilde som kommer tilbake bli brukt av alle kort som
    /// tilfeldigvis lytter på notifikasjonen, ikke bare det ene kortet som trykket knappen.
    static var pendingTargetID: NSManagedObjectID?

    static var isAvailable: Bool {
        guard let url = URL(string: "gphoto://take") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func openForPhoto(target: NSManagedObjectID? = nil, caller: String = "gNorsk", fallback: @escaping () -> Void = {}) {
        pendingTargetID = target
        let callback = "gnorsk://photo-result"
        guard let encoded = callback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "gphoto://take?callback=\(encoded)&caller=\(caller)") else {
            print("📸 GPhotoIntegration: FEIL — klarte ikke bygge gphoto://take URL")
            fallback()
            return
        }
        print("📸 GPhotoIntegration: åpner \(url.absoluteString)")
        UIApplication.shared.open(url, options: [:]) { success in
            print("📸 GPhotoIntegration: UIApplication.open ferdig, success=\(success)")
            if !success {
                DispatchQueue.main.async { fallback() }
            }
        }
    }

    /// Åpner gPhoto sin editor direkte på et eksisterende bilde (f.eks. for å tegne på en pil),
    /// i stedet for kamera/velger-flyten som "take" bruker. Bildet sendes over på pasteboard —
    /// gPhoto plukker det opp der og hopper rett til editoren. Når brukeren er ferdig, sendes
    /// det redigerte bildet tilbake via samme callback/pasteboard-mekanisme som "Hent fra gPhoto".
    static func openForEdit(image: UIImage, target: NSManagedObjectID? = nil, caller: String = "gNorsk", fallback: @escaping () -> Void = {}) {
        pendingTargetID = target
        UIPasteboard.general.image = image
        let callback = "gnorsk://photo-result"
        guard let encoded = callback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "gphoto://edit?callback=\(encoded)&caller=\(caller)") else {
            print("📸 GPhotoIntegration: FEIL — klarte ikke bygge gphoto://edit URL")
            fallback()
            return
        }
        print("📸 GPhotoIntegration: åpner (edit) \(url.absoluteString)")
        UIApplication.shared.open(url, options: [:]) { success in
            print("📸 GPhotoIntegration: UIApplication.open (edit) ferdig, success=\(success)")
            if !success {
                DispatchQueue.main.async { fallback() }
            }
        }
    }

    static func loadPhoto() -> UIImage? {
        guard let image = UIPasteboard.general.image else {
            print("📸 GPhotoIntegration.loadPhoto: FEIL — ingen bilde på pasteboard")
            return nil
        }
        UIPasteboard.general.items = []
        print("📸 GPhotoIntegration.loadPhoto: OK, hentet bilde fra pasteboard, størrelse \(image.size)")
        return image
    }
}
#endif
