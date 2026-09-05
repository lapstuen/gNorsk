import SwiftUI
import CoreData

// Egen struct (i stedet for inline VStack/Button i EditGroupView) for å unngå at Swift sin
// type-checker gir opp ("unable to type-check this expression in reasonable time") på en stor
// HStack med fire nesten identiske, komplekse knapper.
private struct GroupTypeButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .padding()
            .frame(width: 80)
            .background(isSelected ? tint.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? tint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct EditGroupView: View {

    @ObservedObject var gruppe: Group

    @Environment(AppState.self) private var appState
    @Binding var visRedigeringsSkjema: Bool
    @Binding var redigeringsmodus: Bool
    var buttonColor: Color

    @State private var fraRankText: String = ""
    @State private var tilRankText: String = ""

    @State private var visBekreft = false
    @State private var isFetchingFromPublic = false
    @State private var feilmelding: String?
    @State private var moveStats: (total: Int, willMove: Int, byGroup: [Int16: Int]) = (0, 0, [:])
    @State private var showPhotoPicker = false
    @State private var gruppeImage: UIImage?
    @State private var showSlettGruppeAlert = false

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nyttNavn: String
    @State private var youtubeUrlText: String

    init(gruppe: Group,
         visRedigeringsSkjema: Binding<Bool>,
         redigeringsmodus: Binding<Bool>,
         buttonColor: Color) {
        self._gruppe = ObservedObject(wrappedValue: gruppe)
        self._visRedigeringsSkjema = visRedigeringsSkjema
        self._redigeringsmodus = redigeringsmodus
        self.buttonColor = buttonColor
        self._nyttNavn = State(initialValue: gruppe.groupName ?? "")
        self._youtubeUrlText = State(initialValue: gruppe.youtubeUrl ?? "")
        self._gruppeImage = State(initialValue: gruppe.groupUIImage)
        self._fraRankText = State(initialValue: gruppe.frequencyFrom > 0 ? "\(gruppe.frequencyFrom)" : "")
        self._tilRankText = State(initialValue: gruppe.frequencyTo > 0 ? "\(gruppe.frequencyTo)" : "")
    }

    // Hver MARK-seksjon er brutt ut i en egen @ViewBuilder-variabel (i stedet for alt inline i én
    // stor VStack i body) — uten dette ga Swift sin type-checker opp ("unable to type-check this
    // expression in reasonable time") på selve body-uttrykket, som ble for stort/sammensatt etter
    // at Sentences/Video-knappene ble lagt til gruppetype-seksjonen.
    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            Text("Edit group")
                .font(.title2)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("ID: \(gruppe.groupId)")
                    .foregroundColor(.gray)
                    .font(.caption)
                Button {
                    appState.pinnedGruppeId = gruppe.groupId
                    appState.oppdateringFerdig = true
                    appState.refreshToken = UUID()
                } label: {
                    Image(systemName: appState.pinnedGruppeId == gruppe.groupId ? "pin.fill" : "pin")
                        .font(.system(size: 13))
                        .foregroundColor(appState.pinnedGruppeId == gruppe.groupId ? .white : .blue)
                        .frame(width: 30, height: 30)
                        .background(appState.pinnedGruppeId == gruppe.groupId ? Color.blue : Color(.systemGray5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        Button {
            showPhotoPicker = true
        } label: {
            if let img = gruppeImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 120)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title)
                            Text("Add photo")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showPhotoPicker) {
            PhotoViewControllerWrapper { image in
                gruppeImage = image
                showPhotoPicker = false
                gruppe.groupImage = image.jpegData(compressionQuality: 0.8)
                try? context.save()
            }
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        HStack {
            Image(systemName: "pencil")
                .foregroundColor(.secondary)
            TextField("Group name", text: $nyttNavn)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
        }
    }

    @ViewBuilder
    private var youtubeSection: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
            TextField("YouTube URL (optional)", text: $youtubeUrlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                #endif
            if !youtubeUrlText.isEmpty {
                Button {
                    youtubeUrlText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 4) {
            Image(systemName: gruppe.type.iconName)
                .foregroundColor(gruppe.type.color)
            Text(gruppe.type.displayName)
                .foregroundColor(gruppe.type.color)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var groupTypeSection: some View {
        VStack(spacing: 8) {
            Text("Group type")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                GroupTypeButton(icon: "folder.fill", label: "Regular", isSelected: gruppe.isNormalGroup, tint: .blue) {
                    gruppe.makeNormalGroup()
                    try? context.save()
                    appState.oppdateringFerdig = true
                }

                GroupTypeButton(icon: "chart.bar.fill", label: "Frequency", isSelected: gruppe.isFrequencyGroup, tint: .orange) {
                    gruppe.makeFrequencyGroup()
                    try? context.save()
                    appState.oppdateringFerdig = true
                }

                GroupTypeButton(icon: "text.quote", label: "Sentences", isSelected: gruppe.isSentenceGroup, tint: .green) {
                    gruppe.makeSentenceGroup()
                    try? context.save()
                    appState.oppdateringFerdig = true
                }

                GroupTypeButton(icon: "play.rectangle.fill", label: "Video", isSelected: gruppe.isVideoGroup, tint: .red) {
                    gruppe.makeVideoGroup()
                    try? context.save()
                    appState.oppdateringFerdig = true
                }
            }

            // SwiftUI.Group (presisert eksplisitt) — bare "Group" er tvetydig i denne filen siden
            // Core Data-typen for gruppe-entiteten også heter Group.
            SwiftUI.Group {
                if gruppe.isSentenceGroup {
                    Text("Sentence group – words in this group are sentences")
                } else if gruppe.isVideoGroup {
                    Text("Video group – linked to a YouTube lesson")
                } else if gruppe.isNormalGroup {
                    Text("Regular group – add words manually")
                } else {
                    Text("Frequency group – fetch words by rank")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var frequencySection: some View {
        if gruppe.isFrequencyGroup {
            Divider()

            VStack(spacing: 6) {
                Text("Frequency range")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if gruppe.hasFrequencyRange {
                    Text("Saved: \(gruppe.frequencyFrom) – \(gruppe.frequencyTo)")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                HStack {
                    Text("From rank").frame(width: 80, alignment: .leading)
                    TextField("e.g. 1", text: $fraRankText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                HStack {
                    Text("To rank").frame(width: 80, alignment: .leading)
                    TextField("e.g. 50", text: $tilRankText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Button("Fetch words") {
                    guard let f = Int(fraRankText), let t = Int(tilRankText), f > 0, t > 0, f <= t else {
                        feilmelding = "Invalid range. Both fields must be numbers and from ≤ to."
                        return
                    }
                    let groupId = gruppe.groupId
                    Task {
                        isFetchingFromPublic = true
                        do {
                            let result = try await PublicImportService.importRange(
                                minRank: f, maxRank: t, targetGroupId: groupId, context: context
                            )
                            Notifier.shared.show(
                                .success,
                                "\(result.importedWords) words fetched from Public (\(result.skippedWords) already existed)"
                            )
                        } catch {
                            Notifier.shared.show(.error, "Could not fetch from Public: \(error.localizedDescription)")
                        }
                        isFetchingFromPublic = false

                        // Etter Public-henting: sjekk om det i tillegg finnes lokale ord i
                        // dette intervallet som ligger i FEIL gruppe, og tilby å flytte dem hit.
                        moveStats = GlFunctions.shared.countWordsForRankMove(
                            fromRank: f,
                            toRank: t,
                            targetGroupId: groupId,
                            context: context
                        )
                        visBekreft = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFetchingFromPublic)
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if kanSlettes {
            Divider()
            Button(role: .destructive) {
                showSlettGruppeAlert = true
            } label: {
                Label("Delete group", systemImage: "trash")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerSection
                imageSection
                nameSection
                youtubeSection
                statusSection
                Divider()
                groupTypeSection
                frequencySection
                deleteSection
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 300, minHeight: 200)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .onDisappear {
            saveGroup()
        }
        .alert("Confirm move", isPresented: $visBekreft) {
            Button("Cancel", role: .cancel) {}
            if moveStats.willMove > 0 {
                Button("Move \(moveStats.willMove) words", role: .destructive) {
                    guard let f = Int(fraRankText), let t = Int(tilRankText) else { return }
                    let flyttet = GlFunctions.shared.moveWordsByRank(
                        fromRank: f,
                        toRank: t,
                        targetGroupId: gruppe.groupId,
                        context: context
                    )
                    print("Flyttet \(flyttet) ord")
                }
            }
        } message: {
            let f = Int(fraRankText) ?? 0
            let t = Int(tilRankText) ?? 0

            if moveStats.total == 0 {
                Text("No words found with frequency #\(f)–#\(t).")
            } else if moveStats.willMove == 0 {
                Text("All \(moveStats.total) words with frequency #\(f)–#\(t) are already in this group.")
            } else {
                let gruppeInfo = moveStats.byGroup
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { "Group \($0.key): \($0.value) words" }
                    .joined(separator: "\n")

                Text("""
                    Found \(moveStats.total) words with frequency #\(f)–#\(t).

                    \(moveStats.willMove) words will be MOVED from other groups:
                    \(gruppeInfo)

                    ⚠️ This cannot be undone!
                    """)
            }
        }
        .alert("Notice", isPresented: Binding(get: { feilmelding != nil }, set: { _ in feilmelding = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feilmelding ?? "")
        }
        .alert("Delete group?", isPresented: $showSlettGruppeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { slettGruppe() }
        } message: {
            let base = gruppe.groupId
            let count = [base, base + 1, base + 2].filter { groupExists($0) }.count
            Text("Deletes \(count) group(s). This cannot be undone.")
        }
    }

    // MARK: - Auto-lagring
    private func saveGroup() {
        gruppe.groupName = nyttNavn
        let trimmedUrl = youtubeUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        gruppe.youtubeUrl = trimmedUrl.isEmpty ? nil : trimmedUrl
        if let f = Int(fraRankText), let t = Int(tilRankText), f >= 0, t >= 0, f <= t {
            gruppe.setFrequencyRange(from: f, to: t)
        }
        do {
            try context.save()
        } catch {
            print("❌ EditGroupView auto-lagring feilet: \(error)")
        }
        appState.oppdateringFerdig = true
    }

    // MARK: - Helpers

    private func antallOrd(for groupId: Int16) -> Int {
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "groupId == %d", groupId)
        return (try? context.count(for: req)) ?? 0
    }

    private func groupExists(_ id: Int16) -> Bool {
        let req = NSFetchRequest<Group>(entityName: "Group")
        req.predicate = NSPredicate(format: "groupId == %d", id)
        req.fetchLimit = 1
        return ((try? context.count(for: req)) ?? 0) > 0
    }

    private var kanSlettes: Bool {
        let base = gruppe.groupId
        guard antallOrd(for: base) == 0 else { return false }
        if groupExists(base + 1), antallOrd(for: base + 1) > 0 { return false }
        if groupExists(base + 2), antallOrd(for: base + 2) > 0 { return false }
        return true
    }

    private func slettGruppe() {
        let base = gruppe.groupId
        for id in [base, base + 1, base + 2].filter({ groupExists($0) }) {
            let req = NSFetchRequest<Group>(entityName: "Group")
            req.predicate = NSPredicate(format: "groupId == %d", id)
            if let g = try? context.fetch(req).first { context.delete(g) }
        }
        try? context.save()
        appState.refreshToken = UUID()
        visRedigeringsSkjema = false
    }
}

#Preview {
    @Previewable @State var visRedigeringsSkjema = true
    @Previewable @State var redigeringsmodus = true

    let context = PersistenceController.preview.container.viewContext
    let testGroup = Group(context: context)
    testGroup.groupId = 99
    testGroup.groupName = "Test group"
    testGroup.groupType = 9
    let appState = AppState()

    return EditGroupView(
        gruppe: testGroup,
        visRedigeringsSkjema: $visRedigeringsSkjema,
        redigeringsmodus: $redigeringsmodus,
        buttonColor: .blue
    )
    .environment(appState)
    .environment(\.managedObjectContext, context)
}
