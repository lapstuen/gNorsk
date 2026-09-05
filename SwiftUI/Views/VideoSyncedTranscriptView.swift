//
//  VideoSyncedTranscriptView.swift
//  gThai
//
import SwiftUI
import CoreData

struct VideoSyncedTranscriptView: View {
    let groupId: Int16

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var bridge = YouTubePlayerBridge()
    @State private var sortedWords: [ThaiWords] = []
    @State private var currentSentenceIndex: Int? = nil
    @State private var videoId: String? = nil
    @State private var youtubeUrl: String = ""
    @State private var groupName: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if bridge.notEmbeddable {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("This video can't be played inside gNorsk")
                            .font(.subheadline)
                        Button {
                            Group.openYouTube(baseUrl: youtubeUrl)
                        } label: {
                            Label("Watch on YouTube", systemImage: "play.rectangle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black.opacity(0.06))
                } else if let vid = videoId {
                    YouTubePlayerWebView(videoId: vid, bridge: bridge)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                       // .frame(width: 1320,height: 1080) // height will be 180
                } else {
                    ContentUnavailableView("No video", systemImage: "video.slash")
                        .frame(height: 200)
                }
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(sortedWords.enumerated()), id: \.element.objectID) { index, word in
                            TranscriptSentenceRow(
                                word: word,
                                onSeekToTimestamp: {
                                    guard let secs = Group.timestampToSeconds((word.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                                    if bridge.notEmbeddable {
                                        Group.openYouTube(baseUrl: youtubeUrl, seconds: secs)
                                    } else {
                                        bridge.seekAndPlay(to: secs)
                                    }
                                }
                            )
                                .id(word.objectID)
                                .listRowBackground(index == currentSentenceIndex ? Color.blue.opacity(0.15) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: currentSentenceIndex) { _, newIndex in
                        guard let idx = newIndex, idx < sortedWords.count else { return }
                        withAnimation {
                            proxy.scrollTo(sortedWords[idx].objectID, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(groupName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close17") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadData)
        .onChange(of: bridge.currentTime) { _, t in
            let newIndex = indexForTime(t)
            if newIndex != currentSentenceIndex {
                currentSentenceIndex = newIndex
            }
        }
    }

    private func loadData() {
        let groupReq: NSFetchRequest<Group> = Group.fetchRequest()
        groupReq.predicate = NSPredicate(format: "groupId == %d", groupId)
        groupReq.fetchLimit = 1
        guard let group = try? context.fetch(groupReq).first else { return }
        groupName = group.groupName ?? ""
        youtubeUrl = group.youtubeUrl ?? ""
        videoId = Group.youtubeVideoID(from: youtubeUrl)

        let wordsReq: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        wordsReq.predicate = NSPredicate(format: "groupId == %d", groupId)
        let all = (try? context.fetch(wordsReq)) ?? []
        sortedWords = Group.sortedChronologically(all)
            .filter { Group.timestampToSeconds(($0.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) != nil }
    }

    private func indexForTime(_ t: Double) -> Int? {
        var result: Int? = nil
        for (i, w) in sortedWords.enumerated() {
            guard let secs = Group.timestampToSeconds((w.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            if secs <= Int(t) { result = i } else { break }
        }
        return result
    }

}

private struct TranscriptSentenceRow: View {
    let word: ThaiWords
    let onSeekToTimestamp: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var tokens: [String] = []
    @State private var tokenEnglishMap: [String: String] = [:]
    @State private var tokenExistsSet: Set<String> = []
    @State private var popoverIndex: Int? = nil
    @State private var translationIndex: Int? = nil
    @State private var selectedCandidateWord: String? = nil
    @State private var externalLookupToken: String = ""
    @State private var showThaiLangDict = false
    @State private var showOrstDict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ts = word.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !ts.isEmpty {
                Button(action: onSeekToTimestamp) {
                    Text("⏱ \(ts)")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            ScrollView(.vertical, showsIndicators: false) {
                TokenFlowLayout(spacing: 2) {
                    ForEach(tokens.indices, id: \.self) { i in
                        tokenButton(for: tokens[i], index: i)
                    }
                }
            }
            .frame(maxHeight: 260)  // ~5 lines of token boxes, scrolls internally past that
            Text(word.englishWord ?? "")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .task(id: word.objectID) {
            loadTokens()
        }
        .sheet(item: Binding(
            get: {
                guard let w = selectedCandidateWord, let existing = fetchExistingWord(thai: w) else { return nil }
                return WordInput(from: existing)
            },
            set: { newValue, _ in if newValue == nil { selectedCandidateWord = nil } }
        )) { (wordInput: WordInput) in
            DetailWordView(initialWord: wordInput, isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .fullScreenCover(isPresented: $showOrstDict) {
            OrstDictionaryView(word: externalLookupToken)
        }
        .sheet(isPresented: $showThaiLangDict) {
            ThaiLanguageDictionaryView(word: externalLookupToken)
        }
    }

    @ViewBuilder
    private func tokenButton(for token: String, index: Int) -> some View {
        Button {
            translationIndex = index
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard translationIndex == index else { return }
                CloudTTSTest.speakNorsk(token)
            }
        } label: {
            Text(token)
                .font(.system(size: 24))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(tokenExistsSet.contains(token) ? Color(.systemGray5) : Color.orange.opacity(0.15))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: tokenExistsSet.contains(token) ? 0 : 2)
                )
        }
        .buttonStyle(.plain)
        .textSelection(.disabled)
        // .contextMenu lost to iOS's own dictionary-lookup long-press gesture on Thai text
        // ("Ask Siri"/"Look up", and it grabbed the wrong adjacent word besides). Using an
        // explicit high-priority long-press gesture instead reliably wins over the system
        // one and goes straight to our own popover — no intermediate menu needed now that
        // "Look up" was its only real item; "Create word" moved into the popover itself.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                popoverIndex = index
            }
        )
        .popover(isPresented: Binding(
            get: { translationIndex == index },
            set: { if !$0 { translationIndex = nil } }
        )) {
            Text(tokenEnglishMap[token] ?? (tokenExistsSet.contains(token) ? token : "Not in database"))
                .font(.title3)
                .padding()
        }
        .popover(isPresented: Binding(
            get: { popoverIndex == index },
            set: { if !$0 { popoverIndex = nil } }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tokenEnglishMap[token] ?? (tokenExistsSet.contains(token) ? token : "Not in database"))
                    .font(.title3)
                    .padding()
                if tokenExistsSet.contains(token) {
                    Button {
                        popoverIndex = nil
                        selectedCandidateWord = token
                    } label: {
                        Label("Open17", systemImage: "arrow.up.right.circle")
                    }
                    .padding([.horizontal, .bottom])
                } else {
                    Button {
                        createWord(thai: token)
                        popoverIndex = nil
                    } label: {
                        Label("Create word", systemImage: "plus.circle.fill")
                    }
                    .padding([.horizontal, .bottom])
                    Divider()
                    externalLookupLinks(for: token)
                        .padding([.horizontal, .bottom])
                }
            }
        }
    }

    @ViewBuilder
    private func externalLookupLinks(for token: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                externalLookupToken = token
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.thai2english.com/?q=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Thai2English", systemImage: "globe.asia.australia")
            }
            Button {
                externalLookupToken = token
                showThaiLangDict = true
            } label: {
                Label("thai-language.com", systemImage: "character.book.closed")
            }
            Button {
                externalLookupToken = token
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://dict.longdo.com/?search=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Longdo Dict", systemImage: "book.pages")
            }
            Button {
                externalLookupToken = token
                showOrstDict = true
            } label: {
                Label("Royal Society Dictionary", systemImage: "text.book.closed")
            }
            Button {
                externalLookupToken = token
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://forvo.com/search/\(encoded)/no/") {
                    openURL(url)
                }
            } label: {
                Label("Forvo", systemImage: "person.wave.2")
            }
            Button {
                externalLookupToken = token
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://papago.naver.com/?sk=no&tk=th&st=\(encoded)") {
                    openURL(url)
                }
            } label: {
                Label("Papago", systemImage: "p.circle.fill")
            }
            Button {
                openGoogleTranslate(token, targetLang: "th", using: openURL)
            } label: {
                Label("Google Translate", systemImage: "g.circle.fill")
            }
        }
        .buttonStyle(.plain)
    }

    private func loadTokens() {
        let debugTokens = HybridSegmentationPipeline.run(
            text: word.thaiWord ?? "", context: context,
            ignorePrecomputedSyllables: false, useAppleNLWordPreprocess: false
        ).debugTokens
        tokens = debugTokens

        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "thaiWord IN %@", debugTokens)
        guard let results = try? context.fetch(req) else { return }
        var map: [String: String] = [:]
        var exists: Set<String> = []
        for w in results {
            if let thai = w.thaiWord {
                exists.insert(thai)
                if let eng = w.englishWord, !eng.isEmpty { map[thai] = eng }
            }
        }
        tokenEnglishMap = map
        tokenExistsSet = exists
    }

    private func fetchExistingWord(thai: String) -> ThaiWords? {
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "thaiWord == %@", thai)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    // Creates a standalone vocabulary entry for a token that isn't in the database yet,
    // saved into the sentence's own "Word" companion group (base+1) — same convention as
    // DetailWordView's createWordInCompanionGroup, but resolved from the true base group
    // (Group.resolvedBaseGroupId) rather than the raw sentence groupId, so it still lands in
    // the right place even if the sentence itself happens to sit in a non-base slot.
    private func createWord(thai: String) {
        guard fetchExistingWord(thai: thai) == nil else { return }
        let baseGroupId = Group.resolvedBaseGroupId(for: word.groupId)
        let companionGroupId = baseGroupId + 1

        let compReq = NSFetchRequest<Group>(entityName: "Group")
        compReq.predicate = NSPredicate(format: "groupId == %d", companionGroupId)
        compReq.fetchLimit = 1
        guard (try? context.fetch(compReq).first) != nil else { return }

        let newWord = ThaiWords(context: context)
        newWord.id = UUID()
        newWord.thaiWord = thai
        newWord.englishWord = ""
        newWord.groupId = companionGroupId
        newWord.modifiedDate = Date()
        try? context.save()
        loadTokens()
    }
}

// Simple left-to-right wrap layout for the token boxes. Uses the Layout protocol (not the
// older GeometryReader-based FlowLayout component) specifically because it correctly
// reports its own intrinsic size, so it works inside a ScrollView — GeometryReader-based
// layouts collapse to zero height there since ScrollView asks for a natural size upfront.
private struct TokenFlowLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
