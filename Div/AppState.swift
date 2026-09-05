// AppState.swift
// Holder global app-tilstand for valgt gruppe
import SwiftUI
import CoreData
import Observation

@Observable class AppState {

   // var activeSheet: SheetType? = nil

    /// Group ID for automatically created words from Hybrid Segmentation
    /// Words created via "Lage nytt ord" button when translation is missing
    /// #xAutoCreatedWords
    static let autoCreatedWordsGroupId: Int16 = 210

    /// Fallback group ID for words imported from the shared Public CloudKit database
    /// that don't have a valid frequencyRank (1...4000) to place them in one of the
    /// auto-seeded frequency groups — see FrequencyGroupSeeder ("No Group", id 1040).
    static let publicImportGroupId: Int16 = FrequencyGroupSeeder.noGroupId

    var refreshToken: UUID = UUID()
    // Lagres persistent slik at appen kan starte direkte i Griden for sist valgte
    // gruppe (i stedet for å nullstilles til "ingen gruppe" ved hver oppstart).
    // gThaiApp.swift bygger GridView direkte med appState.sqlGruppeId ved oppstart — FØR
    // MainAppView/SelectGroup i det hele tatt kjører. Normaliseringen (følgegruppe → sann
    // hovedgruppe) må derfor skje her, ikke bare der brukeren aktivt velger en gruppe,
    // ellers gjenoppstår en gammel lagret følgegruppe-ID hver eneste oppstart.
    private static func initialCurrentGroupId() -> Int16 {
        let storedGroupId = Group.resolvedBaseGroupId(for: GlFunctions().getCurrentGroupID())
        if storedGroupId > 0 {
            return storedGroupId
        }

        let fallbackGroupId = Group.resolvedBaseGroupId(for: Int16(UserDefaults.standard.integer(forKey: "lastValgtGruppeId")))
        return fallbackGroupId > 0 ? fallbackGroupId : 0
    }

    private static func initialCurrentGroupName(for groupId: Int16) -> String {
        let storedName = GlFunctions().getCurrentGroupName(groupId: groupId)
        if storedName != "Ikke satt" {
            return storedName
        }
        return UserDefaults.standard.string(forKey: "lastValgtGruppeNavn") ?? ""
    }

    var valgtGruppeId: Int16 = initialCurrentGroupId() {
        didSet {
            UserDefaults.standard.set(Int(valgtGruppeId), forKey: "lastValgtGruppeId")
        }
    }
    var pinnedGruppeId: Int16 = 0
    var valgtGruppeNavn: String = initialCurrentGroupName(for: initialCurrentGroupId()) {
        didSet {
            UserDefaults.standard.set(valgtGruppeNavn, forKey: "lastValgtGruppeNavn")
        }
    }
    // Starter likt med valgtGruppeId slik at Griden viser riktig gruppe ved oppstart.
    var sqlGruppeId: Int16 = initialCurrentGroupId()
    var currentWordID: NSManagedObjectID? = nil
    var oppdateringFerdig: Bool = false
    var visAlleDetaljer: Bool = true
    var suppressNextUpdateError = false
    var sessionResults: [UUID: Bool] = [:]

    // For å trigger automatisk søk når ord allerede finnes
    var pendingSearchText: String?

    // Åpne GridView direkte med spesifikke ord (brukes fra TranslationView)
    var pendingOpenGrid: Bool = false
    var pendingGridWordIDs: [NSManagedObjectID] = []

    // Husker siste valgte filter i SelectGroup (ikke lagres til disk)
    var selectGroupFilterKey: String = "G"

   /*
    // ⬇️ NY vedvarende status for denne økten
    var sessionResults: [UUID: Bool] = [:]

    // ⬇️ Behold gamle metodenavnet for å slippe å endre andre filer
    func markResult(id: UUID, success: Bool) {
        sessionResults[id] = success
        refreshToken = UUID()   // tving re-render i Grid
    }

    // Rydd alt når du forlater testen
    func clearSessionResults() {
        sessionResults.removeAll()
        refreshToken = UUID()
    }
    */
}

/// Skiller admin (full tilgang) fra vanlig bruker (kun bruksfunksjoner: bla/øve/søke/grupper).
/// Admin-status lagres i NSUbiquitousKeyValueStore, som synkroniserer automatisk mellom
/// enheter som er logget inn med samme iCloud-konto — altså dine egne enheter, ikke andres.
@Observable
final class AdminManager {
    static let shared = AdminManager()

    /// Endre PIN-koden her ved behov.
    private let pin = "1955"
    private let storageKey = "isAdminMode"
    private let store = NSUbiquitousKeyValueStore.default

    private(set) var isAdmin: Bool

    private init() {
        isAdmin = store.bool(forKey: storageKey)
        store.synchronize()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isAdmin = self.store.bool(forKey: self.storageKey)
        }
    }

    @discardableResult
    func enable(pin entered: String) -> Bool {
        guard entered == pin else { return false }
        isAdmin = true
        store.set(true, forKey: storageKey)
        store.synchronize()
        return true
    }

    func disable() {
        isAdmin = false
        store.set(false, forKey: storageKey)
        store.synchronize()
    }
}
