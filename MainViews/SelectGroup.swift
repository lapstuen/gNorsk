import SwiftUI
import CoreData

// Unngå navnekollisjon med SwiftUI.Group
// typealias CDGroup = Group

struct SelectGroup: View {

    @Bindable var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onSelect: (CDGroup) -> Void

    // Standard: skjul @/#/$-grupper
    @State private var groupPredicate: NSPredicate =
        NSPredicate(format: "NOT (groupName BEGINSWITH[c] '@' OR groupName BEGINSWITH[c] '#' OR groupName BEGINSWITH[c] '$')")

    // G/@/# skal bare vise de ekte (base-)gruppene, ikke vente/ok-følgegruppene.
    // "* Alle" / "% Alle" / "▶️" viser fortsatt absolutt alt, inkl. følgegrupper.
    @State private var skjulFolgegrupper: Bool = true
    @State private var groups: [CDGroup] = []
    @State private var allGroupIds: Set<Int16> = []
    @State private var iRedigeringsmodus: Bool = false
    @State private var redigerGruppe: CDGroup?
    @State private var visAlleModusAktiv: Bool = false
    @State private var searchText: String = ""

    // Større kolonner på iPad for å vise hele gruppenavnet
  //  private var columns: [GridItem] {
  //      let minWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 220 : 150
  //      return [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
  //  }
    
    private var columns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Én kolonne på iPhone
            return [GridItem(.flexible(), spacing: 16)]
        } else {
            // Adaptive på iPad/Mac
            let minWidth: CGFloat = 320
            return [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
        }
    }

    var body: some View {
        VStack {
            headerButtons
            ScrollView { groupGridView.padding() }
        }
        .onAppear {
            applyFilter(appState.selectGroupFilterKey)
            loadAllGroupIds()
            loadGroups()
        }
        .onChange(of: groupPredicate) { loadGroups() }
        .onChange(of: visAlleModusAktiv) { loadGroups() }
        .onChange(of: searchText) { loadGroups() }
        .sheet(item: $redigerGruppe, onDismiss: {
            loadAllGroupIds()
            loadGroups()
        }) { group in
            EditGroupView(
                gruppe: group,
                visRedigeringsSkjema: Binding(
                    get: { redigerGruppe != nil },
                    set: { if !$0 { redigerGruppe = nil } }
                ),
                redigeringsmodus: $iRedigeringsmodus,
                buttonColor: .blue
            )
            .environment(appState)
            .environment(\.managedObjectContext, context)
    #if os(macOS) || targetEnvironment(macCatalyst)
            .frame(minWidth: 400, minHeight: 1200)
    #else
            .frame(minWidth: 300)
    #endif
            .padding()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // Swipe ned for å gå tilbake
                    if value.translation.height > 120 &&
                       abs(value.translation.width) < 50 &&
                       value.predictedEndTranslation.height > 200 {
                        dismiss()
                    }
                }
        )
    }

    @State private var showResetAllAlert = false

    // MARK: Header

    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button("←") { dismiss() }
                .buttonStyle(.bordered)

            Button {
                createNewGroup()
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .padding(2)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            Spacer()

            Button("G") {
                applyFilter("G")
            }.buttonStyle(.bordered)
             .fontWeight(appState.selectGroupFilterKey == "G" ? .bold : .regular)

            Button("@") {
                applyFilter("@")
            }.buttonStyle(.bordered)
             .fontWeight(appState.selectGroupFilterKey == "@" ? .bold : .regular)

            Button("#") {
                applyFilter("#")
            }.buttonStyle(.bordered)
             .fontWeight(appState.selectGroupFilterKey == "#" ? .bold : .regular)

            Menu {
                Button("* All (alphabetical)") {
                    applyFilter("*")
                }
                Button("% All (by ID)") {
                    applyFilter("%")
                }
                Divider()
                Button("▶️ YouTube") {
                    applyFilter("▶️")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .padding(2)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal)
    }

    // MARK: Grid
    private var groupGridView: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(groups), id: \.objectID) { group in
                GroupCardView(
                    group: group,
                    appState: appState,
                    iRedigeringsmodus: iRedigeringsmodus,
                    visGroupId: visAlleModusAktiv,
                    allGroupIds: allGroupIds,
                    onTap: { handleGroupTap(group) },
                    onEdit: {
                        let g = GlFunctions()
                        g.deleteCurrentGroupCoreData()
                        g.insertCurrentGroupIntoCoreData(groupId: group.groupId, number: 0)
                        redigerGruppe = group
                    },
                    onTogglePin: { togglePin(for: group) }
                )
            }
        }
        .background(.white)
    }
    // MARK: Filter
    private func applyFilter(_ key: String) {
        appState.selectGroupFilterKey = key
        switch key {
        case "@":
            visAlleModusAktiv = false
            skjulFolgegrupper = true
            groupPredicate = NSPredicate(format: "groupName BEGINSWITH[c] '@'")
        case "#":
            visAlleModusAktiv = false
            skjulFolgegrupper = true
            groupPredicate = NSPredicate(format: "groupName BEGINSWITH[c] '#'")
        case "*":
            visAlleModusAktiv = false
            skjulFolgegrupper = false
            groupPredicate = NSPredicate(value: true)
        case "%":
            visAlleModusAktiv = true
            skjulFolgegrupper = false
            groupPredicate = NSPredicate(value: true)
        case "▶️":
            visAlleModusAktiv = false
            skjulFolgegrupper = false
            groupPredicate = NSPredicate(format: "groupName BEGINSWITH '▶️'")
        default: // "G"
            visAlleModusAktiv = false
            skjulFolgegrupper = true
            groupPredicate = NSPredicate(
                format: "NOT (groupName BEGINSWITH[c] '@' OR groupName BEGINSWITH[c] '#' OR groupName BEGINSWITH[c] '$')"
            )
        }
    }

    // MARK: Data

    private func createNewGroup() {
        let newGroupId = GlFunctions().createNewGroupId()
        let req = NSFetchRequest<CDGroup>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", newGroupId)
        req.fetchLimit = 1
        guard let newGroup = try? context.fetch(req).first else {
            print("❌ Fant ikke ny gruppe med id \(newGroupId)")
            return
        }
        iRedigeringsmodus = true
        redigerGruppe = newGroup
    }

    private func loadAllGroupIds() {
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        req.resultType = .dictionaryResultType
        req.propertiesToFetch = ["groupId"]
        if let results = try? context.fetch(req) as? [[String: Any]] {
            allGroupIds = Set(results.compactMap { $0["groupId"] as? Int16 })
        }
    }

    private func handleGroupTap(_ group: CDGroup) {
        if iRedigeringsmodus {
            redigerGruppe = group
        } else {
            let resolved = resolveBaseGroup(for: group)
            let g = GlFunctions()
            g.deleteCurrentGroupCoreData()
            g.insertCurrentGroupIntoCoreData(groupId: resolved.groupId, number: 0)
            onSelect(resolved)
            dismiss()
        }
    }

    private func resolveBaseGroup(for group: CDGroup) -> CDGroup {
        let baseId = Group.resolvedBaseGroupId(for: group.groupId)
        guard baseId != group.groupId else { return group }
        let req = NSFetchRequest<CDGroup>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", baseId)
        req.fetchLimit = 1
        return (try? context.fetch(req).first) ?? group
    }

    private func loadGroups() {
        let request = NSFetchRequest<CDGroup>(entityName: "Group")
        request.sortDescriptors = visAlleModusAktiv
            ? [NSSortDescriptor(keyPath: \CDGroup.groupId, ascending: true)]
            : [NSSortDescriptor(keyPath: \CDGroup.groupName, ascending: true)]

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            request.predicate = groupPredicate
        } else {
            // Søk alltid i alle grupper når søkefeltet er aktivt
            request.predicate = NSPredicate(format: "groupName CONTAINS[c] %@", trimmed)
        }

        do {
            var fetched = try context.fetch(request)
            // Core Data-predikater støtter ikke modulo, så følgegruppe-filteret
            // gjøres i Swift etter at fetchen er kjørt.
            if skjulFolgegrupper {
                fetched = fetched.filter { !isCompanionGroupName($0.groupName) }
            }
            groups = fetched
        } catch {
            print("❌ Feil ved henting av grupper:", error.localizedDescription)
        }
    }

    // MARK: Pin

    private func togglePin(for group: CDGroup) {
        if appState.pinnedGruppeId == group.groupId {
            appState.pinnedGruppeId = 0
        } else {
            appState.pinnedGruppeId = group.groupId
        }
        appState.refreshToken = UUID()

        // Persistér ev. til Core Data hvis ønsket:
        // let g = GlFunctions()
        // g.insertPinnedGroupIntoCoreData(groupId: appState.pinnedGruppeId)
    }
}

// Følgegrupper (Word/Ok) opprettes alltid med "$" foran navnet (se
// GLFunctions.createNewGroupId()) — det er det pålitelige signalet, ikke
// groupId % 3, siden createNewGroupId() bare bruker "høyeste ID + 1" og derfor
// ikke garanterer at hovedgruppens ID er delelig med 3.
private func isCompanionGroupName(_ name: String?) -> Bool {
    (name ?? "").hasPrefix("$")
}

// MARK: - GroupCardView
private struct GroupCardView: View {
    @ObservedObject var group: CDGroup
    let appState: AppState
    let iRedigeringsmodus: Bool
    var visGroupId: Bool = false
    var allGroupIds: Set<Int16> = []
    let onTap: () -> Void
    let onEdit: () -> Void
    let onTogglePin: () -> Void

    private var valgtId: Int16 { appState.valgtGruppeId }
    private var pinnedId: Int16 { appState.pinnedGruppeId }
    private var erValgt: Bool { valgtId == group.groupId }
    private var erPinned: Bool { pinnedId == group.groupId }
    private var groupType: GroupType { group.type }

    private var isFrequencyGroup: Bool {
        group.groupId >= FrequencyGroupSeeder.frequencyGroupBaseId
    }

    private var isCompanionGroup: Bool {
        isCompanionGroupName(group.groupName)
    }

    // Summerer ord fra alle tre grupper i tripletten (hovedgruppe + Word + Ok), ikke bare
    // hovedgruppens egne ord — slik at antallet som vises stemmer med det faktiske totale
    // innholdet uansett hvilket av de tre kortene man ser på. Frekvensgrupper er aldri del
    // av en triplett, så de teller kun seg selv.
    private var wordCount: Int {
        let g = GlFunctions()
        guard !isFrequencyGroup else {
            return g.getAntGroup(groupId: group.groupId)
        }
        let baseId = Group.resolvedBaseGroupId(for: group.groupId)
        return g.getAntGroup(groupId: baseId)
            + g.getAntGroup(groupId: baseId + 1)
            + g.getAntGroup(groupId: baseId + 2)
    }

    // Flagger kun grupper med EN av de to følgegruppene (Word/Ok) — ikke begge
    // (frisk triplett) og ikke ingen (helt vanlig enkeltstående gruppe, aldri
    // del av noen triplett). Kun den delvise/inkonsistente tilstanden er verdt
    // å varsle om.
    private var hasMissingCompanions: Bool {
        guard !isFrequencyGroup, !isCompanionGroup, group.groupId > 0 else { return false }
        let hasWord = allGroupIds.contains(group.groupId + 1)
        let hasOk = allGroupIds.contains(group.groupId + 2)
        return (hasWord || hasOk) && !(hasWord && hasOk)
    }

    private var borderColor: Color {
        if isCompanionGroup { return .red }
        if hasMissingCompanions { return .orange }
        return .clear
    }

    private var borderWidth: CGFloat {
        hasMissingCompanions ? 3 : 2
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mainContent
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onEdit)
        .accessibilityAddTraits(.isButton)
    }

    private var mainContent: some View {
        VStack(spacing: 6) {
            groupHeader
            // groupInfo
        }
        .padding(.top, 2)
    }

    private var groupHeader: some View {
        HStack(spacing: 8) {
            // Bilde eller type-ikon
            if let img = group.groupUIImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: groupType.iconName)
                    .foregroundStyle(groupType.color)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(groupType.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(visGroupId
                        ? "\(group.groupName ?? "???") (\(group.groupId))"
                        : (group.groupName ?? "???"))
                    .foregroundStyle(erPinned ? Color.red : Color.black)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(headerBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
        )
    }

    // "Word"/"Ok"-følgegrupper ligger tradisjonelt på hovedgruppens ID + 1 / + 2, altså
    // ikke delelig med 3. Ikke 100% garantert (createNewGroupId() tvinger det ikke), men
    // brukes her kun som et visuelt hint slik at de skiller seg fra gruppene man faktisk
    // velger — ingen filtrering, kun bakgrunnsfarge.
    private var isDivisibleByThree: Bool {
        group.groupId % 3 == 0
    }

    private var headerBackground: Color {
        if erValgt {
            return Color.blue.opacity(0.2)
        }
        if !isDivisibleByThree {
            // Undergruppe (Word/Ok-plass): $ foran navnet er definert som riktig/forventet
            // tilstand (grå = normalt). Mangler $, er det et avvik fra konvensjonen (rødt).
            return isCompanionGroup ? Color.gray.opacity(0.35) : Color.red.opacity(0.35)
        }
        // Hovedgruppe der hele tripletten (hovedgruppe + Word + Ok) er tom — trygg
        // sletting-kandidat, ingen videre testing nødvendig.
        if wordCount == 0 {
            return Color.green.opacity(0.35)
        }
        switch groupType {
        case .frequencyCompleted:
            return Color.blue.opacity(0.1)
        case .frequencyPaused:
            return Color.orange.opacity(0.1)
        case .normalInactive, .frequencyInactive:
            return Color.gray.opacity(0.1)
        case .normalActive, .frequencyActive:
            return Color.gray.opacity(0.1)
        case .sentence:
            return Color.green.opacity(0.1)
        case .video:
            return Color.red.opacity(0.1)
        }
    }

    private var groupInfo: some View {
        HStack {
         //   Text("antall: \(GlFunctions().getAntGroup(groupId: group.groupId))")
         //   Spacer()
         //   Text(groupType.displayName)
         //       .foregroundStyle(groupType.color)
         //       .fontWeight(.medium)
        }
        .font(.system(size: 12, weight: .regular, design: .rounded))
        .foregroundStyle(.gray)
    }
}
 
// MARK: Preview



@MainActor
private struct SelectGroupPreviewWrapper: View {
    // Core Data preview-context
    let context = PersistenceController.preview.container.viewContext

    // AppState (@Observable – ikke ObservableObject)
    let appState = AppState()

    init() {
        // Unngå SwiftUI.Group-kollisjon
        typealias CDGroup = Group

        // Seed testdata i init (lov – ikke i body)
        let g1 = CDGroup(context: context)
        g1.groupId = 1
        g1.groupName = "Norsk"

        let g2 = CDGroup(context: context)
        g2.groupId = 2
        g2.groupName = "Thai"

        appState.valgtGruppeId  = 1
        appState.pinnedGruppeId = 2
    }

    var body: some View {
        SelectGroup(appState: appState) { selected in
            print("Valgt gruppexxx:", selected.groupName ?? "ukjent")
        }
        .environment(\.managedObjectContext, context)
    }
}


#Preview("Select Group – Mock Core Data") {
    SelectGroupPreviewWrapper()
}

