import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers
import SafariServices


/*
 @available(iOS, introduced: 8, deprecated: 100000)
 open class func authorizationStatus() -> PHAuthorizationStatus
 
 @available(iOS, introduced: 8, deprecated: 100000)
 open class func requestAuthorization(_ handler: @escaping (PHAuthorizationStatus) - Void)
 */

@MainActor
class PhotoVC: UIViewController,
               UIImagePickerControllerDelegate,
               UIDocumentPickerDelegate,
               UINavigationControllerDelegate,
                Storyboarded {
    
    var g = GlFunctions()
    var images = [UIImage]()
    var photoPosition = ""
    var poiId = UUID()
    var teller = 0
    var indexImage = 0
    var onSave: (() -> ())?  // optional funksnonsvariabel
    
    
    var onSavePhoto: ( (UIImage) -> () )?
    var initialSearchText: String = ""

    var takePhotoFirst = false
    @IBOutlet weak var imageTake: UIImageView!
    var imagePicker: UIImagePickerController!
    
    var itemProviders: [NSItemProvider] = []
    var iteratorImages: IndexingIterator<[NSItemProvider]>?
    
    var imageMain: UIImage?
    
    
    //MARK: OUTLETS
    
    @IBOutlet weak var Urltext: UITextField!
    
    
    @IBAction func endEditing(_ sender: Any) {
        print("")
    }
    
    /*
    @IBAction func textfieldChanged(_ sender: Any) {
        let stringx = Urltext.text!
    }
    */
   /*
    @IBAction func valueChanged(_ sender: Any) {
        let stringx = Urltext.text!
        if stringx.count > 0 {
            let urlx = URL(string: Urltext.text!)!.imageURL
            Urltext.text = ""
            DispatchQueue.main.async { [weak self] in
                if let imageData = try? Data(contentsOf: urlx) {
                    if let loadedImage = UIImage(data: imageData) {
                        // self!.g.insertImageIntoCoredata(image: loadedImage, poiId: self!.poiId)
                        self!.imageTake.image = loadedImage
                    }
                }
            }
        }
        
    }
    */
    @IBAction func getImageFromFiles(_ sender: Any) {
        
            // displayNextImage()
            
            
            let documentPicker2 = UIDocumentPickerViewController(forOpeningContentTypes: [.png,.jpeg],asCopy: true)
            
            documentPicker2.delegate = self
            documentPicker2.allowsMultipleSelection = false

            present(documentPicker2, animated: true)
            //            let url = Urltext.text!
            //            Urltext.text = ""
            //
            //            imageTake.loadFrom(URLAddress: url)
            //           // print("displayNextImage kommentar")
        
    }
    
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

        //  print("abcd \(urls)")
        // let directoryRootIcloud = ""
         // guard let selectedFileUrl = urls.first else { return }
        
        for url in urls {
            loadImageUrlAndSave(URLAddress: url, poiId: poiId)
            do {
                print("abcd image added \(url.path)")
                try FileManager.default.removeItem(at: url)
            } catch {
                print("abcd Could not trash the item at \(url.path)")
            }
        }
        
        //self.onSave?()
       // dismiss(animated: true)

        //   dismiss(animated: true)
        
        
        
        
        
        
    }
    
    //MARK: ACTIONS
    @IBAction func loadImage(_ sender: Any) {
        // User-initiated paste from clipboard
        if let image = UIPasteboard.general.image {
            imageTake.image = image
            imageMain = image
        } else {
            print("Ingen bilde i utklippstavlen.")
        }
    }
    @IBAction func getImagesFromLibery(_ sender: Any) {
        // prsenterer picker her! Resultat finnes i delegate didFinishPicking
        imageTake.backgroundColor = UIColor.red
        // self.performSegue(withIdentifier: "toPhotoShow", sender: nil)
        
        
            let accessLevel: PHAccessLevel = .readWrite
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { authorizationStatus in
                
                
                switch authorizationStatus {
                    
                    
                    
                case .limited:
                    print("authorizationStatus limitied")
                default:
                    DispatchQueue.main.async {
                        print("authorizationStatus \(authorizationStatus.rawValue)")
                        
                        var configuration = PHPickerConfiguration()
                        
                        configuration.filter =  .images
                        configuration.selectionLimit = 0
                        
                        let picker = PHPickerViewController(configuration: configuration)
                        picker.delegate = self
                        
                        DispatchQueue.main.async {
                            self.present(picker, animated: true)
                        }
                    }
                }
            }
        
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Kun ved faktisk lukking av PhotoVC — ikke når f.eks. Safari-visningen
        // presenteres oppå den (det ville trigget onSavePhoto og dermed lukket
        // hele sheeten under Safari-vinduet).
        guard isBeingDismissed else { return }
        if let image = imageTake?.image {
            onSavePhoto?(image)
        }
    }
    
    
    
    @IBAction func takePhoto(_ sender: UIButton) {
        takeDirectPhoto()
    }
    @IBAction func save(_ sender: UIButton) {


            guard let image = imageTake.image else { return }

            // Send bildet til SwiftUI via closure
            onSavePhoto?(image)

            // Lukk visningen
           // if let nav = navigationController {
         //       nav.popViewController(animated: true)
         //   } else {
        //        self.dismiss(animated: true, completion: nil)
        //    }

    }

    // MARK: - Image Search
    @IBAction func searchForImages(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Søk etter bilder",
            message: "Skriv inn søkeord for å finne bilder",
            preferredStyle: .alert
        )

        alert.addTextField { [weak self] textField in
            textField.text = self?.initialSearchText ?? ""
            textField.placeholder = "Søkeord"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }

        let googleAction = UIAlertAction(title: "Google Images", style: .default) { [weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let searchText = textField.text,
                  !searchText.isEmpty else { return }
            self.openImageSearch(searchText: searchText, service: .google)
        }

        let unsplashAction = UIAlertAction(title: "Unsplash", style: .default) { [weak alert] _ in
            guard let textField = alert?.textFields?.first,
                  let searchText = textField.text,
                  !searchText.isEmpty else { return }
            self.openImageSearch(searchText: searchText, service: .unsplash)
        }

        let cancelAction = UIAlertAction(title: "Avbryt", style: .cancel)

        alert.addAction(googleAction)
        alert.addAction(unsplashAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    private enum ImageSearchService {
        case google
        case unsplash
    }

    private func openImageSearch(searchText: String, service: ImageSearchService) {
        guard let encodedQuery = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let urlString: String
        switch service {
        case .google:
            urlString = "https://www.google.com/search?q=\(encodedQuery)&tbm=isch"
        case .unsplash:
            urlString = "https://unsplash.com/s/photos/\(encodedQuery)"
        }

        guard let url = URL(string: urlString) else { return }

        #if targetEnvironment(macCatalyst)
        // SFSafariViewController fungerer ikke på Mac Catalyst.
        UIApplication.shared.open(url)
        #else
        // In-app nettleser: appen forlates aldri, så vinduet her forblir intakt
        // når man går tilbake (i motsetning til UIApplication.shared.open, som
        // bakgrunner appen og kan gjøre at man havner på hovedmenyen ved retur).
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safariVC = SFSafariViewController(url: url, configuration: config)
        present(safariVC, animated: true)
        #endif
    }

    @objc func didTapView(){
        self.view.endEditing(true)
    }
    
    //MARK: -
    //MARK: - FUNCTIONS
    //MARK: -
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier]) && session.items.count == 1
    }
    



    func loadImageUrlAndSave(URLAddress: URL, poiId: UUID) {
        
        
        var image:UIImage?
        
        // DispatchQueue.main.async { [weak self] in
        if let imageData = try? Data(contentsOf: URLAddress) {
            if let loadedImage = UIImage(data: imageData) {
                image = loadedImage

               self.imageTake.image = image

                //     g.insertImageIntoCoredata(image: image!, poiId: poiId)
            }
        }
        // }
    }
    

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        let dropLocation = session.location(in: view)
        // updateLayers(forDropLocation: dropLocation)
        
        let operation: UIDropOperation
        
        if imageTake.frame.contains(dropLocation) {
            /*
             If you add in-app drag-and-drop support for the .move operation,
             you must write code to coordinate between the drag interaction
             delegate and the drop interaction delegate.
             */
            operation = session.localDragSession == nil ? .copy : .move
        } else {
            // Do not allow dropping outside of the image view.
            operation = .cancel
        }
        
        return UIDropProposal(operation: operation)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        var imagex :UIImage? = nil
        // Consume drag items (in this example, of type UIImage).
        session.loadObjects(ofClass: UIImage.self) { imageItems in
            let images = imageItems as! [UIImage]
            /*
             If you do not employ the loadObjects(ofClass:completion:) convenience
             method of the UIDropSession class, which automatically employs
             the main thread, explicitly dispatch UI work to the main thread.
             For example, you can use `DispatchQueue.main.async` method.
             */
            // let dropLocation = session.location(in: view)

            if images.count > 0 {

                imagex = images.first

                // Thread 1: Fatal error: Unexpectedly found nil while unwrapping an Optional value
                let image = imagex!
                // error draging photo into app
                // FIX Ipad: hread 1: Fatal error: Unexpectedly found nil while unwrapping an Optional value


                if imagex != nil {
                    // self.g.insertImageIntoCoredata(image: image, poiId: poiId)
                    self.imageMain = image
                    self.imageTake.image = imagex
                    //if ipad {

                    //  NotificationCenter.default.post(name: .refreshPhotoString, object: self)
                    // }
                } else {
                    print("abcd error")
                }
            }

        }

        DispatchQueue.main.async {
            self.imageTake.image = self.imageMain
            self.imageTake.setNeedsDisplay()
        }
    }
    
    //MARK: -
    //MARK: - viewDidLoad()
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()


       PHPhotoLibrary.requestAuthorization { status in
          switch status {
          case .authorized:
             print("Full tilgang gitt")
          case .limited:
             print("Begrenset tilgang – vis bildevelger")
          default:
             print("Ingen tilgang")
          }
       }

        
      // preferredContentSize = CGSize(width:600, height: 800)
       
       
        let dropInteraction = UIDropInteraction(delegate: self)
        imageTake.addInteraction(dropInteraction)
        
        let pasteControl = UIPasteControl()
        pasteControl.addTarget(self, action: #selector(handlePaste(_:)), for: .primaryActionTriggered)
        pasteControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pasteControl)
        NSLayoutConstraint.activate([
            pasteControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pasteControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
    }
    
    @objc private func handlePaste(_ sender: UIPasteControl) {
        if let image = UIPasteboard.general.image {
            imageTake.image = image
            imageMain = image
        }
    }
    
    func takePhoto() {
        // start phito direktly here!
        imagePicker.allowsEditing = true
        imagePicker =  UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .camera
        present(imagePicker, animated: true, completion: nil)
        
        
    }
    func setupGestureRecognizer() {
        let tapRecognizer = UITapGestureRecognizer()
        //  tapRecognizer.addTarget(self, action: #selector(DetailPoiVC.didTapView))
        self.view.addGestureRecognizer(tapRecognizer)
        
        //pinchGesture = UIPinchGestureRecognizer(target: photo, action: #selector(pinchedView(sender:)))
        
        //photo.isUserInteractionEnabled = true
        //photo.addGestureRecognizer(pinchGesture)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        
        
        if segue.identifier == "toPhotoShow" {
            
        }
        
    }
    override func viewDidAppear(_ animated: Bool) {
        //        if teller == 0 {
        //            teller = teller + 1
        //            // takeDirectPhoto()
        //        }
        
    }
    
    
}

//MARK: EXTENSIONS
extension UIImage {
    func resizeWithPercent(percentage: CGFloat) -> UIImage? {
        let imageView = UIImageView(frame: CGRect(origin: .zero, size: CGSize(width: size.width * percentage, height: size.height * percentage)))
        imageView.contentMode = .scaleAspectFit
        imageView.image = self
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        imageView.layer.render(in: context)
        guard let result = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        UIGraphicsEndImageContext()
        return result
    }
    func resizeWithWidth(width: CGFloat) -> UIImage? {
        let imageView = UIImageView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))))
        imageView.contentMode = .scaleAspectFit
        imageView.image = self
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        imageView.layer.render(in: context)
        guard let result = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        UIGraphicsEndImageContext()
        return result
    }
}

extension PhotoVC: UITextFieldDelegate, UIDropInteractionDelegate {
    func takeDirectPhoto() {
#if targetEnvironment(simulator)
        // your code
        // Log("No camera")
#else
        imagePicker =  UIImagePickerController()
        imagePicker.allowsEditing = false
        imagePicker.delegate = self
        imagePicker.sourceType = .camera
        imagePicker.showsCameraControls = true
        
        present(imagePicker, animated: true, completion: nil)
#endif
        
    }
    @IBAction func imageGetFromLibrary(_ sender: UIButton) {
        
        imagePicker =  UIImagePickerController()
        imagePicker.allowsEditing = false
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        // imagePicker.sourceType = .
        present(imagePicker, animated: true, completion: nil)
    }
    
    @IBAction func imageGetFromLibraryEdit(_ sender: UIButton) {
        
        imagePicker =  UIImagePickerController()
        imagePicker.allowsEditing = true
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true, completion: nil)
        //        imagePicker =  UIImagePickerController()
        //        imagePicker.allowsEditing = false
        //        imagePicker.delegate = self
        //        imagePicker.sourceType = .savedPhotosAlbum
        //        present(imagePicker, animated: true, completion: nil)
        
        
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } else {
            let alert = UIAlertController(title: "Saved!", message: "Image saved successfully", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        var selectedImage: UIImage?
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
            self.imageTake.image = selectedImage!
            picker.dismiss(animated: true, completion: nil)
            
           // let imageFull = selectedImage!
           // let imageSmall = imageFull.resizeWithWidth(width: 390)!

        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
            self.imageTake.image = selectedImage!
            picker.dismiss(animated: true, completion: nil)
            
           // let imageFull = selectedImage!
           // let imageSmall = imageFull.resizeWithWidth(width:90)!
            
            
            
            // 7 self.dismiss(animated: true, completion: nil)
            //  refreshCollectionView()
        }
    }
    /*    func savePhotoOption() {
     //
     //
     //           let imageUrl = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.referenceURL)] as! URL
     //           let imageUrls = [imageUrl]
     //           PHPhotoLibrary.shared().performChanges( {
     //                let imageAssetToDelete = PHAsset.fetchAssets(withALAssetURLs: imageUrls, options: nil)
     //                PHAssetChangeRequest.deleteAssets(imageAssetToDelete)
     //            },
     //                completionHandler: { success, error in
     //                print("Finished deleting asset. %@", (success ? "Success" : error!))
     //            })
     //            }
     //            let image =  info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage
     //            if let imageFullSize = image {
     //                let imagex = imageFullSize.resizeWithWidth(width: 200)!
     //                ximagex)
     //                if g.saveImageToFile(image: imagex, poiId: id) {
     //                    g.insertImagesIntoCoreData2(poiId: Int32(id), insertDate: Date(), myImage: imageFullSize,myImageFull: imageFullSize, myDescription: "Test")
     //                    print("Saved image: \(id)")
     //                }
     //            }
     //    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
     //    // Local variable inserted by Swift 4.2 migrator.
     //      let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)
     //        if picker.sourceType == .camera {
     //            print("camera")// Do something with an image from the camera
     //            imagePicker.dismiss(animated: true, completion: nil)
     //            imageTake.image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage
     //        }
     //        else {
     //            // Do something with an image from another source
     //        imagePicker.dismiss(animated: true, completion: nil)
     //        imageTake.image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage
     //        let imageUrl = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.referenceURL)] as! URL
     //        let imageUrls = [imageUrl]
     //
     //        PHPhotoLibrary.shared().performChanges( {
     //            let imageAssetToDelete = PHAsset.fetchAssets(withALAssetURLs: imageUrls, options: nil)
     //            PHAssetChangeRequest.deleteAssets(imageAssetToDelete)
     //        },
     //            completionHandler: { success, error in
     //            print("Finished deleting asset. %@", (success ? "Success" : error!))
     //        })
     //        }
     //        let image =  info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage
     //        if let imageFullSize = image {
     //            let imagex = imageFullSize.resizeWithWidth(width: 200)!
     //            print(imagex)
     //            if g.saveImageToFile(image: imagex, poiId: id) {
     //                g.insertImagesIntoCoreData2(poiId: Int32(id), insertDate: Date(), myImage: imageFullSize,myImageFull: imageFullSize, myDescription: "Test")
     //                print("Saved image: \(id)")
     //            }
     //        }
     //    }
     */
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
    return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
    return input.rawValue
}
extension PhotoVC: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        // her må det loopes gjennom resultatsettet!
        let itemProviders = results.map(\.itemProvider)
        //       iteratorImages = itemProviders.makeIterator()
        
        for provider in itemProviders {
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { (image, error) in
                    DispatchQueue.main.async {
                        
                       
                          //TODO: 
                          //MARK: todo
                        //TODO: check with new release
                        //                            print("abcd errror: \(String(describing: error))")
                        //                            print("abcd image: \(String(describing: image))")
                        
                        
                        if let image = image as? UIImage {
                            // self.imageView.image = image
                            self.imageTake.image = image
                            
                          //  let imageFull = image
                            // let imageSmall = imageFull.resizeWithWidth(width: 90)!
                            // self.g.insertImagesIntoCoreData2(poiId: self.poiId, insertDate: Date(), myImage: imageSmall, myImageFull: imageFull, myDescription: self.photoPosition)
                        }
                    }
                }
            }
        }
    }
}
extension UIImageView {
    func loadFrom(URLAddressString: String) {
        guard let url = URL(string: URLAddressString) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            if let imageData = try? Data(contentsOf: url) {
                if let loadedImage = UIImage(data: imageData) {
                    self?.image = loadedImage
                }
            }
        }
    }
    
    func loadFrom(URLAddress: URL) {
        
        
        DispatchQueue.main.async { [weak self] in
            if let imageData = try? Data(contentsOf: URLAddress) {
                if let loadedImage = UIImage(data: imageData) {
                    self?.image = loadedImage
                }
            }
        }
    }
}
extension URL {
    var imageURL: URL {
        if let url = UIImage.urlToStoreLocallyAsJPEG(named: self.path) {
            // this was created using UIImage.storeLocallyAsJPEG
            return url
        } else {
            // check to see if there is an embedded imgurl reference
            for query in query?.components(separatedBy: "&") ?? [] {
                let queryComponents = query.components(separatedBy: "=")
                if queryComponents.count == 2 {
                    if queryComponents[0] == "imgurl", let url = URL(string: queryComponents[1].removingPercentEncoding ?? "") {
                        return url
                    }
                }
            }
            return self.baseURL ?? self
        }
    }
}
extension UIImage {
    private static let localImagesDirectory = "UIImage.storeLocallyAsJPEG"
    
    static func urlToStoreLocallyAsJPEG(named: String) -> URL? {
        var name = named
        let pathComponents = named.components(separatedBy: "/")
        if pathComponents.count > 1 {
            if pathComponents[pathComponents.count-2] == localImagesDirectory {
                name = pathComponents.last!
            } else {
                return nil
            }
        }
        if var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            url = url.appendingPathComponent(localImagesDirectory)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                url = url.appendingPathComponent(name)
                if url.pathExtension != "jpg" {
                    url = url.appendingPathExtension("jpg")
                }
                return url
            } catch let error {
                print("UIImage.urlToStoreLocallyAsJPEG \(error)")
            }
        }
        return nil
    }
}

import UIKit






