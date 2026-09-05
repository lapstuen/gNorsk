//
//  gNorskApp.swift
//  gNorsk
//
//  Created by Claude Code
//

import SwiftUI
import Translation

@main
struct gNorskApp: App {
    @State private var appState = AppState()
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            GridView(groupId: appState.sqlGruppeId, exerciseMode: false, isRootView: true)
                .environment(appState)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    DispatchQueue.main.async {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 600, height: 660)
                            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10000, height: 10000)
                        }
                    }
                    #endif
                }
                .onOpenURL { url in
                    print("📱 gNorsk onOpenURL mottok: \(url.absoluteString), scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
                    #if canImport(UIKit)
                    if url.scheme?.lowercased() == "gnorsk", url.host?.lowercased() == "photo-result" {
                        print("📱 gNorsk: gjenkjent som gPhoto-callback, prøver å laste bilde…")
                        if let image = GPhotoIntegration.loadPhoto() {
                            print("📱 gNorsk: bilde lastet OK, størrelse \(image.size), poster .gPhotoResult")
                            NotificationCenter.default.post(
                                name: .gPhotoResult,
                                object: nil,
                                userInfo: ["image": image]
                            )
                            print("📱 gNorsk: .gPhotoResult postet")
                        } else {
                            print("📱 gNorsk: FEIL — fant ikke bilde i App Group-container")
                        }
                    } else {
                        print("📱 gNorsk: URL matchet ikke gPhoto-callback (scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil"))")
                    }
                    #endif
                }
                // Én TranslationSession-vert for hele appen — se AppleTranslationService.swift
                // for hvorfor: TranslationSession kan kun hentes via denne modifieren festet til
                // et View, så alle oversettelser (uansett hvilken skjerm som vises) går via
                // singletonen AppleTranslationService.shared, som queuer forespørsler og
                // trigger denne modifieren ved å sette `configuration`.
                .translationTask(AppleTranslationService.shared.configuration) { session in
                    await AppleTranslationService.shared.handle(session: session)
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1000, height: 1200)
        #endif
    }
}
