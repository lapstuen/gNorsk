import UIKit

extension ThaiWords {
   var uiImage: UIImage {
      get {
         if let data = image, let img = UIImage(data: data) {
            return img
         }
         return UIImage(systemName: "photo")!
      }
      set {
         image = newValue.jpegData(compressionQuality: 0.8)
      }
   }
}
