import SwiftUI
import CoreData
import UIKit
import Combine

struct SearchView : View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var sokTekst = ""
    @State private var sokTekst2 = ""
    @State private var navigerTilResultat = false
    @State private var filtrerteOrd: [String] = []
    @State private var filtrerteId: [NSManagedObjectID] = []
    @StateObject private var keyboardObserver = KeyboardObserver()
    @State private var showHistorySheet = false
    @State private var eksaktTreff: Bool = false
    @State private var erSetning: Bool = false

    @FocusState private var isSearchFieldFocused: Bool

    private func recordSearchHistory(_ text: String) {
        SearchHistoryEntry.upsert(searchText: text, in: context)
    }

    private struct SearchLangButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }
    }

    private struct SearchToggleButton: View {
        let title: String
        @Binding var isOn: Bool
        let activeColor: Color

        var body: some View {
            Button { isOn.toggle() } label: {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(isOn ? activeColor : Color.secondary.opacity(0.2))
                    .foregroundColor(isOn ? .white : .primary)
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }
    }

    private struct SearchBarView: View {
        @Binding var sokTekst: String
        @Binding var eksaktTreff: Bool
        @Binding var erSetning: Bool
        @FocusState var isSearchFieldFocused: Bool
        @Binding var showHistorySheet: Bool
        let onThai: () -> Void
        let onEnglish: () -> Void
        let onNorsk: () -> Void
        let onAll: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 0) {
                // Rad 1: tilbake, søkefelt, historikk
                HStack {
                    Button("←") { dismiss() }
                    TextField("Search here ..", text: $sokTekst)
                        .uniformTextField()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .focused($isSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: 300)
                        //.padding()
                    Button { showHistorySheet = true } label: {
                        Image(systemName: "clock")
                            .font(.system(size: 20))
                    }
                    .accessibilityLabel("Previous searches")
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Rad 2: språkknapper + modifikatorer
                ZStack {
                    Spacer()
                    HStack {
                    SearchLangButton(title: "norsk", action: onNorsk)
                    SearchLangButton(title: "thai", action: onThai)
                    SearchLangButton(title: "eng", action: onEnglish)
                    SearchLangButton(title: "all", action: onAll)
                        SearchToggleButton(title: "Exact", isOn: $eksaktTreff, activeColor: .orange)
                        SearchToggleButton(title: erSetning ? "Sentence" : "Word", isOn: $erSetning, activeColor: .purple)
                    }
                        
                    Spacer()
                   
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(.thinMaterial)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Bakgrunnsflate for tap og sveip
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFieldFocused = false
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 30)
                            .onChanged { value in
                                if value.translation.height > 10 {
                                    isSearchFieldFocused = false
                                }
                            }
                            .onEnded { value in
                                let isMostlyVertical = abs(value.translation.width) < 60
                                let isStrongDown = value.translation.height > 120 || value.predictedEndTranslation.height > 180
                                if isMostlyVertical && isStrongDown {
                                    dismiss()
                                }
                            }
                    )
                
                    
                    SearchBarView(
                        sokTekst: $sokTekst,
                        eksaktTreff: $eksaktTreff,
                        erSetning: $erSetning,
                        isSearchFieldFocused: _isSearchFieldFocused,
                        showHistorySheet: $showHistorySheet,
                        onThai: {
                            var trimmed = sokTekst.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let isPrefixSearch = trimmed.hasSuffix("%")
                            if isPrefixSearch { trimmed.removeLast() }
                            recordSearchHistory(trimmed)
                            let result: [NSManagedObjectID]
                            if erSetning {
                                result = g.searchSentence(searchWord: trimmed, exact: eksaktTreff, context: context)
                            } else if isPrefixSearch {
                                result = (try? g.searchThaiTranslationPrefix(searchWord: trimmed, context: context)) ?? []
                            } else {
                                result = (try? g.searchThaiTranslation(searchWord: trimmed, context: context)) ?? []
                            }
                            if !result.isEmpty {
                                isSearchFieldFocused = false
                                filtrerteId = result
                                navigerTilResultat = true
                            } else {
                                print("❌ Ingen treff")
                            }
                        },
                        onEnglish: {
                            let trimmed = sokTekst.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            recordSearchHistory(trimmed)
                            let result = erSetning
                                ? g.searchSentence(searchWord: trimmed, exact: eksaktTreff, context: context)
                                : g.searchEnglish(searchWord: trimmed, exact: eksaktTreff, context: context)
                            if !result.isEmpty {
                                isSearchFieldFocused = false
                                filtrerteId = result
                                navigerTilResultat = true
                            } else {
                                print("❌ Ingen treff")
                            }
                        },
                        onNorsk: {
                            let trimmed = sokTekst.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            recordSearchHistory(trimmed)
                            let result = erSetning
                                ? g.searchSentence(searchWord: trimmed, exact: eksaktTreff, context: context)
                                : g.searchNorsk(searchWord: trimmed, exact: eksaktTreff, context: context)
                            if !result.isEmpty {
                                isSearchFieldFocused = false
                                filtrerteId = result
                                navigerTilResultat = true
                            } else {
                                print("❌ Ingen treff")
                            }
                        },
                        onAll: {
                            var trimmed = sokTekst.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let isPrefixSearch = trimmed.hasSuffix("%")
                            if isPrefixSearch { trimmed.removeLast() }
                            recordSearchHistory(trimmed)
                            let result: [NSManagedObjectID]
                            if erSetning {
                                result = g.searchSentence(searchWord: trimmed, exact: eksaktTreff, context: context)
                            } else if isPrefixSearch {
                                result = (try? g.searchThaiWordPrefix(searchWord: trimmed, context: context)) ?? []
                            } else {
                                result = g.searchThaiWordFree(searchWord: trimmed, context: context)
                            }
                            if !result.isEmpty {
                                isSearchFieldFocused = false
                                filtrerteId = result
                                navigerTilResultat = true
                            } else {
                                print("❌ Ingen treff")
                            }
                        }
                    )
            }
            .navigationDestination(isPresented: $navigerTilResultat) {
                GridView(filtrerteId: filtrerteId, onBack: { navigerTilResultat = false })
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
            }
            .sheet(isPresented: $showHistorySheet) {
                NavigationStack {
                    HistoryListView(
                        onSelect: { text in
                            sokTekst = text
                            isSearchFieldFocused = true
                            showHistorySheet = false
                        }
                    )
                    .navigationTitle("Previous searches")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showHistorySheet = false }
                        }
                    }
                    .padding()
                }
                #if targetEnvironment(macCatalyst)
                .catalystSheetFrame(width: 680, height: 520)
                #endif
            }
            .background(Color.background1.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        } //vstack
        .onAppear {
            // Sjekk om det er et pending søk
            if let pendingText = appState.pendingSearchText {
                sokTekst = pendingText
                appState.pendingSearchText = nil

                DispatchQueue.main.async {
                    isSearchFieldFocused = true
                }

                // Kjør søket automatisk
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    do {
                        let result = try g.searchThaiWord(searchWord: pendingText, context: context)
                        if !result.isEmpty {
                            filtrerteId = result
                            navigerTilResultat = true
                        }
                    } catch {
                        print("🛑 Feil under automatisk søk: \(error.localizedDescription)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    isSearchFieldFocused = true
                }
            }
        }
    }// body
} //struct

private struct HistoryListView: View {
    let onSelect: (String) -> Void
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SearchHistoryEntry.usedAt, ascending: false)],
        animation: .default
    ) private var searchHistory: FetchedResults<SearchHistoryEntry>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Previous searches")
                    .font(.headline)
                Spacer()
                Button("Delete all") {
                    SearchHistoryEntry.deleteAll(in: context)
                }
                    .foregroundColor(.red)
            }

            if searchHistory.isEmpty {
                Text("No history")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(searchHistory) { entry in
                            Button {
                                if let searchText = entry.searchText {
                                    onSelect(searchText)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.secondary)
                                    Text(entry.searchText ?? "")
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(22)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardHeight = Self.height(from: notification)
            }
            .store(in: &cancellables)
    }

    private static func height(from notification: Notification) -> CGFloat {
        guard let info = notification.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        return endFrame.origin.y >= UIScreen.main.bounds.height ? 0 : endFrame.height
    }
}

#if DEBUG
private struct SearchViewPreviewHost: View {
    @State private var appState = AppState()
    private let context = PersistenceController.preview.container.viewContext

    var body: some View {
        SearchView()
            .environment(appState)
            .environment(\.managedObjectContext, context)
            .frame(width: 900, height: 900)
            .background(Color.background1)
    }
}

#Preview("Search (mock)") {
    SearchViewPreviewHost()
}
#endif









