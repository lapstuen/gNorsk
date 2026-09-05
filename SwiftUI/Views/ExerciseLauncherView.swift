import SwiftUI
import CoreData

// Samler alle øvings-/spaced-repetition-varianter på ett sted, slik at man slipper å
// vite at de ligger spredt i MainAppView (rød/liten oransje knapp) og GridView
// (blå/oransje knapp). Startes fra den røde "Øv alt"-knappen på hovedskjermen.
struct ExerciseLauncherView: View {
    // Satt når vi kommer fra en ordliste/søkeresultat-basert GridView i stedet for
    // en ekte gruppe — "Selected group" blir da "Selected list", og selve øvingen
    // kjøres over nøyaktig dette ID-settet i stedet for appState sin globale gruppe.
    var filtrerteId: [NSManagedObjectID] = []
    var listName: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gridView.chunkSize") private var chunkSize: String = "10"

    @State private var launchReviewAll = false
    @State private var launchGroupExerciseGrid = false
    @State private var launchGroupAll = false
    @State private var launchGroupChunked = false
    @State private var showReviewDue = false
    @State private var showActiveLearning = false

    private var isListMode: Bool { !filtrerteId.isEmpty }
    private var harValgtGruppe: Bool { appState.valgtGruppeId > 0 }

    var body: some View {
        NavigationStack {
            List {
                Section("All groups") {
                    Button {
                        launchReviewAll = true
                    } label: {
                        optionRow(
                            color: .red,
                            iconName: "brain.head.profile.fill",
                            title: "Practice due",
                            subtitle: "Only words ready for review now, regardless of group"
                        )
                    }

                    Button {
                        showReviewDue = true
                    } label: {
                        optionRow(
                            color: .purple,
                            iconName: "circle.grid.3x3.circle.fill",
                            title: "Learning List",
                            subtitle: "List of all words due for review, regardless of group"
                        )
                    }

                    Button {
                        showActiveLearning = true
                    } label: {
                        optionRow(
                            color: .green,
                            iconName: "circle.grid.3x3.circle.fill",
                            title: "Learning List",
                            subtitle: "All words in active learning, regardless of group"
                        )
                    }
                }

                Section(isListMode ? "Selected list: \(listName ?? "List")" : (harValgtGruppe ? "Selected group: \(appState.valgtGruppeNavn)" : "Selected group")) {
                    if isListMode || harValgtGruppe {
                        Button {
                            launchGroupExerciseGrid = true
                        } label: {
                            optionRow(
                                color: .red,
                                iconName: "brain.head.profile.fill",
                                title: "Practice due",
                                subtitle: isListMode ? "Exercise view current list" : "Excercise view current group"
                            )
                        }

                        Button {
                            launchGroupAll = true
                        } label: {
                            optionRow(
                                color: .orange,
                                iconName: "brain.head.profile.fill",
                                title: isListMode ? "Practice all words in the list" : "Practice all words in the group",
                                subtitle: "No filtering by date or learning status"
                            )
                        }

                        Button {
                            launchGroupChunked = true
                        } label: {
                            optionRow(
                                color: .blue,
                                iconName: "brain.head.profile.fill",
                                title: "Practice \(chunkSize) oldest words",
                                subtitle: "Limited count — oldest modified first"
                            )
                        }

                        HStack {
                            Text("Word count:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("Count", text: $chunkSize)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .onChange(of: chunkSize) { _, newValue in
                                    // Digits only, clamped to 1...100
                                    let filtered = newValue.filter { $0.isNumber }
                                    if let intVal = Int(filtered) {
                                        let clamped = max(1, min(100, intVal))
                                        if filtered != String(clamped) {
                                            chunkSize = String(clamped)
                                        } else if filtered != newValue {
                                            chunkSize = filtered
                                        }
                                    } else if !newValue.isEmpty {
                                        chunkSize = "10"
                                    }
                                }
                        }
                    } else {
                        Text("Select a group on the main screen to see more options here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Practice Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 620, minHeight: 760)
        #endif
        .fullScreenCover(isPresented: $launchReviewAll) {
            ExerciseView(groupId: nil, exerciseType: .review)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $launchGroupAll) {
            ExerciseView(
                groupId: isListMode ? nil : appState.valgtGruppeId,
                objectIDs: isListMode ? filtrerteId : nil,
                exerciseType: .allInGroup
            )
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $launchGroupChunked) {
            ExerciseView(
                groupId: isListMode ? nil : appState.valgtGruppeId,
                objectIDs: isListMode ? filtrerteId : nil,
                exerciseType: .chunked(limit: Int(chunkSize) ?? 10)
            )
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $launchGroupExerciseGrid) {
            ExerciseView(
                groupId: isListMode ? nil : appState.valgtGruppeId,
                objectIDs: isListMode ? filtrerteId : nil,
                exerciseType: .mixed
            )
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $showReviewDue) {
            ReviewDueView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $showActiveLearning) {
            ActiveLearningView()
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
    }

    @ViewBuilder
    private func optionRow(color: Color, iconName: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
