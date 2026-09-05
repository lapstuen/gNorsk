//
//  QuickThaiSyllableTestsView.swift
//

import Foundation
import CoreData
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let goldenJSONFileName = "thai_syllable_golden.json"

private func copyThaiWordToClipboard(_ word: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = word
#elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(word, forType: .string)
#endif
}

// MARK: - Modell for gulltest
struct TestCase: Identifiable, Decodable {
    let id: UUID
    let text: String
    let expected: [String]?
    let ipa: String?

    init(text: String, expected: [String]?, ipa: String? = nil) {
        self.id = UUID()
        self.text = text
        self.expected = expected
        self.ipa = ipa
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case expected
        case syllables
        case ipa
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        let syls = try c.decodeIfPresent([String].self, forKey: .syllables)
        let old = try c.decodeIfPresent([String].self, forKey: .expected)
        self.expected = syls ?? old
        self.ipa = try c.decodeIfPresent(String.self, forKey: .ipa)
        self.id = UUID()
    }
}

private func bundledGoldenTestsURL() -> URL? {
    Bundle.main.url(forResource: "thai_syllable_golden", withExtension: "json")
}

private func editableGoldenTestsURL() -> URL? {
    bundledGoldenTestsURL()
}

private func loadGoldenTests() -> [TestCase] {
    guard let url = editableGoldenTestsURL() ?? bundledGoldenTestsURL() else {
        print("❌ Fant ikke thai_syllable_golden.json i bundle eller Documents")
        return []
    }

    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TestCase].self, from: data)
    } catch {
        print("❌ Kunne ikke lese gullfilen: \(error)")
        return []
    }
}

struct QuickThaiSyllableTestsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppState.self) private var appState

    @State private var tests: [TestCase] = loadGoldenTests()
    @State private var evaluated: [Evaluated] = []
    @State private var ran = false
    @State private var filterText: String = ""
    @State private var statusFilter: ResultStatusFilter = .all
    @State private var showGoldenEditor = false
    @State private var goldenEditorText = ""
    @State private var goldenEditorError: String?
    @State private var showingValidationError = false
    @State private var selectedDetailWord: WordInput?

    private struct Evaluated: Identifiable {
        let id = UUID()
        let test: TestCase
        let syls: [ThaiSyllable]
        let got: [String]
        let ipaOK: Bool?
        let lookupState: SyllableLookupState
    }

    private enum ResultStatusFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case ok = "OK"
        case error = "Feil"
        case unknown = "Ukjent"

        var id: String { rawValue }
    }

    private var visibleEvaluated: [Evaluated] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return evaluated.filter { item in
            let matchesText = needle.isEmpty || item.test.text == needle
            let matchesStatus: Bool
            switch statusFilter {
            case .all:
                matchesStatus = true
            case .ok:
                matchesStatus = item.ipaOK == true
            case .error:
                matchesStatus = item.ipaOK == false
            case .unknown:
                matchesStatus = item.ipaOK == nil
            }
            return matchesText && matchesStatus
        }
    }

    private var visibleOks: [Evaluated] {
        visibleEvaluated.filter { $0.ipaOK == true }
    }

    private var visibleIPAErrors: [Evaluated] {
        visibleEvaluated.filter { $0.ipaOK == false }
    }

    private var visibleUnknownCount: Int {
        visibleEvaluated.count - visibleOks.count - visibleIPAErrors.count
    }

    private enum SyllableLookupState: Equatable {
        case found([String])
        case noRow
        case duplicateRows(Int)
        case noStoredSyllables(rawSentence: String?)
        case malformedStoredSyllables(rawSentence: String?, rawSyllables: [String])
        case fetchFailed(String)

        var syllables: [String]? {
            if case .found(let syllables) = self {
                return syllables
            }
            return nil
        }

        private var sentenceDescription: String {
            switch self {
            case .noStoredSyllables(let rawSentence):
                return rawSentence.map { "\"\($0)\"" } ?? "nil"
            case .malformedStoredSyllables(let rawSentence, _):
                return rawSentence.map { "\"\($0)\"" } ?? "nil"
            default:
                return "n/a"
            }
        }

        var rawSentenceValue: String? {
            switch self {
            case .noStoredSyllables(let rawSentence):
                return rawSentence
            case .malformedStoredSyllables(let rawSentence, _):
                return rawSentence
            default:
                return nil
            }
        }

        var rawSentenceDebugText: String? {
            guard let rawSentenceValue else { return nil }
            return "DB sentence field: \"\(rawSentenceValue)\" (\(rawSentenceValue.count) chars)"
        }

        var statusText: String {
            switch self {
            case .found(let syllables):
                return "DB syllables found: \(syllables)"
            case .noRow:
                return "No DB row found"
            case .duplicateRows(let count):
                return "Duplicate DB rows found (\(count))"
            case .noStoredSyllables(let rawSentence):
                return "DB row found, but sentence field is: \(rawSentence.map { "\"\($0)\"" } ?? "nil")"
            case .malformedStoredSyllables(let rawSentence, let rawSyllables):
                return "Stored sentence could not be parsed: \(rawSentence.map { "\"\($0)\"" } ?? "nil") | raw syllables: \(rawSyllables)"
            case .fetchFailed(let message):
                return "DB fetch failed: \(message)"
            }
        }
    }

    private func lookupStateColor(_ state: SyllableLookupState) -> Color {
        switch state {
        case .found:
            return .green
        case .noStoredSyllables:
            return .orange
        case .noRow, .duplicateRows, .malformedStoredSyllables, .fetchFailed:
            return .red
        }
    }

    private var editableGoldenURL: URL? {
        editableGoldenTestsURL()
    }

    private func dbFirstSyllable(for thai: String) -> String? {
        lookupSyllables(for: thai).syllables?.first
    }

    private func lookupSyllables(for thai: String) -> SyllableLookupState {
        let countReq = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        countReq.predicate = NSPredicate(format: "thaiWord == %@", thai)

        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.predicate = NSPredicate(format: "thaiWord == %@", thai)

        do {
            let matchCount = try context.count(for: countReq)
            guard matchCount == 1 else {
                if matchCount == 0 {
                    fatalError("❌ No DB row found for '\(thai)'")
                } else {
                    fatalError("⚠️ Duplicate DB rows found for '\(thai)': \(matchCount)")
                }
            }

            let matches = try context.fetch(req)
            guard let word = matches.first else {
                fatalError("❌ DB count said 1 row for '\(thai)', but fetch returned nothing")
            }

            print(
                "✅ DB row hit for '\(thai)': " +
                "thaiWord=\(word.thaiWord ?? "nil"), " +
                "sentence=\"\(word.sentence ?? "nil")\", " +
                "sentenceCount=\(word.sentence?.count ?? 0), " +
                "notes=\"\(word.notes ?? "nil")\", " +
                "wordType=\(word.wordType), " +
                "objectID=\(word.objectID.uriRepresentation().absoluteString)"
            )

            switch word.syllableStorageDiagnostic() {
            case .empty(let rawSentence):
                let rawText = rawSentence ?? "nil"
                fatalError("❌ DB row found for '\(thai)', but sentence field is empty: \"\(rawText)\" (\(rawSentence?.count ?? 0) chars)")
            case .malformed(let rawSentence):
                let rawText = rawSentence ?? "nil"
                fatalError("❌ DB row found for '\(thai)', but sentence field could not be parsed: \"\(rawText)\" (\(rawSentence?.count ?? 0) chars)")
            case .found(let syllables):
                let normalized = syllables.flatMap { normalizeSyllableText($0) }
                guard !normalized.isEmpty else {
                    let rawText = word.sentence ?? "nil"
                    fatalError("❌ DB row found for '\(thai)', but sentence field normalized to nothing: \"\(rawText)\" (\(word.sentence?.count ?? 0) chars)")
                }
                return .found(normalized)
            }
        } catch {
            print("❌ Could not fetch DB syllables for \(thai): \(error)")
            return .fetchFailed(error.localizedDescription)
        }
    }

    private func dbWord(for thai: String) -> ThaiWords? {
        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.predicate = NSPredicate(format: "thaiWord == %@", thai)
        req.fetchLimit = 1

        do {
            return try context.fetch(req).first
        } catch {
            print("❌ Could not fetch DB word for \(thai): \(error)")
            return nil
        }
    }

    private func normalizeSyllableText(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[") && trimmed.contains("]") else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        let parts = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2 else { return nil }
            let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return parts.isEmpty ? (trimmed.isEmpty ? [] : [trimmed]) : parts
    }

    private func openDetailView(for thai: String) {
        if let word = dbWord(for: thai) {
            selectedDetailWord = WordInput(from: word)
            return
        }

        selectedDetailWord = WordInput(
            objectID: nil,
            thaiWord: thai,
            englishWord: "",
            ipa: "",
            sentence: "",
            tags: "",
            image: nil,
            uuid: nil,
            translation1: "",
            translation2: ""
        )
    }

    private func firstIPAComponent(_ ipa: String?) -> String {
        guard let ipa, !ipa.isEmpty else { return "" }
        return ipa.split(separator: ".").first.map(String.init) ?? ipa
    }

    private func runTests() {
        evaluated = tests.map { tc in
            let lookupState = lookupSyllables(for: tc.text)
            let sourceSyllables = lookupState.syllables
            // NB: analyser alle stavelsene i ÉN omgang (ikke én og én med
            // treatTextAsSingleSyllable) — ellers mister vi kryss-stavelse-
            // mønstre som อักษรนำ (f.eks. "ต" + "ลาด" i "ตลาด").
            let parsedSyllables = (sourceSyllables ?? []).compactMap { analyzeThaiSyllableText($0, source: "DB") }
            let analysis: [SyllableToneInfo] = buildToneInfos(from: parsedSyllables, source: "DB", word: dbWord(for: tc.text))
            let got = sourceSyllables ?? []
            let expectedIPAComponents = tc.ipa?.split(separator: ".").map(String.init) ?? []
            let gotIPAComponents = analysis.map { toneIPA(for: $0) }.filter { !$0.isEmpty }
            let ipaOK: Bool?
            if sourceSyllables == nil || expectedIPAComponents.isEmpty {
                ipaOK = nil
            } else {
                ipaOK = gotIPAComponents.count == expectedIPAComponents.count
                    && zip(gotIPAComponents, expectedIPAComponents).allSatisfy { $0 == $1 }
            }
            return Evaluated(test: tc, syls: analysis.map { $0.syllable }, got: got, ipaOK: ipaOK, lookupState: lookupState)
        }
        ran = true
    }

    private func openGoldenEditor() {
        guard let url = editableGoldenURL ?? editableGoldenTestsURL() else {
            goldenEditorError = "Kunne ikke finne bundle-resursen \(goldenJSONFileName)."
            showingValidationError = true
            return
        }

        do {
            goldenEditorText = try String(contentsOf: url, encoding: .utf8)
            goldenEditorError = nil
            showGoldenEditor = true
        } catch {
            goldenEditorError = "Kunne ikke lese \(url.lastPathComponent): \(error.localizedDescription)"
            showingValidationError = true
        }
    }

    private func saveGoldenEditorText() {
        guard let url = editableGoldenURL ?? editableGoldenTestsURL() else {
            goldenEditorError = "Kunne ikke finne bundle-resursen \(goldenJSONFileName)."
            showingValidationError = true
            return
        }

        guard let data = goldenEditorText.data(using: .utf8) else {
            goldenEditorError = "Teksten kunne ikke kodes som UTF-8."
            showingValidationError = true
            return
        }

        do {
            _ = try JSONDecoder().decode([TestCase].self, from: data)
        } catch {
            goldenEditorError = "JSON-validering feilet: \(error.localizedDescription)"
            showingValidationError = true
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            tests = try JSONDecoder().decode([TestCase].self, from: data)
            showGoldenEditor = false
            ran = false
            evaluated = []
            print("✅ Saved editable golden JSON to: \(url.path)")
        } catch {
            goldenEditorError = "Kunne ikke lagre \(url.lastPathComponent): \(error.localizedDescription)"
            showingValidationError = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Word", text: $filterText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Status", selection: $statusFilter) {
                    ForEach(ResultStatusFilter.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Button("Run tests") {
                        runTests()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Edit JSON") {
                        openGoldenEditor()
                    }
                    .buttonStyle(.bordered)

                    if ran {
                        let totalCount = visibleEvaluated.count
                        let okCount = visibleOks.count
                        let errorCount = visibleIPAErrors.count
                        let unknownCount = visibleUnknownCount
                        VStack(alignment: .leading, spacing: 2) {
                            Text("total number \(totalCount).")
                            Text("ok \(okCount).")
                            Text("error \(errorCount).")
                            Text("unknown \(unknownCount).")
                        }
                    }
                }

                guardSection(title: "Word analysis", show: ran && !visibleEvaluated.isEmpty) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(visibleEvaluated) { current in
                            wordAnalysisBlock(for: current)
                            if current.id != visibleEvaluated.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if !ran {
                    Text("Tap «Run tests» to see a quick syllable test.")
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .sheet(isPresented: $showGoldenEditor) {
            NavigationView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Edit \(goldenJSONFileName)")
                        .font(.headline)
                    TextEditor(text: $goldenEditorText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    Text("This edits the bundle resource used by the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("Golden JSON")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showGoldenEditor = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveGoldenEditorText()
                        }
                    }
                }
            }
        }
        .alert("Golden JSON", isPresented: $showingValidationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(goldenEditorError ?? "Unknown error")
        }
        .fullScreenCover(item: $selectedDetailWord) { input in
            DetailWordView(initialWord: input, isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
    }

    @ViewBuilder
    private func wordAnalysisBlock(for current: Evaluated) -> some View {
        let lookupState = current.lookupState

        if let syllables = lookupState.syllables, !syllables.isEmpty {
            let expectedIPAComponents = current.test.ipa?.split(separator: ".").map(String.init) ?? []
            // NB: analyser alle stavelsene i ÉN omgang (ikke isolert per stavelse)
            // slik at kryss-stavelse-mønstre som อักษรนำ ("ต" + "ลาด") fanges opp.
            let parsedSyllables = syllables.compactMap { analyzeThaiSyllableText($0, source: "DB") }
            let contextAnalysis = buildToneInfos(from: parsedSyllables, source: "DB", word: dbWord(for: current.test.text))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(current.test.text)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(current.ipaOK == true ? .green : (current.ipaOK == false ? .red : .primary))
                    Button {
                        openDetailView(for: current.test.text)
                    } label: {
                        Label("Detail", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }

                Text(lookupState.statusText)
                    .font(.caption)
                    .foregroundColor(lookupStateColor(lookupState))

                if let rawSentenceDebugText = lookupState.rawSentenceDebugText {
                    Text(rawSentenceDebugText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ForEach(Array(syllables.enumerated()), id: \.offset) { index, syllable in
                    let analyzed = contextAnalysis[safe: index]
                    let gotIPA = analyzed.map { toneIPA(for: $0) } ?? ""
                    let expectedIPA = index < expectedIPAComponents.count ? expectedIPAComponents[index] : ""

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Syllable \(index + 1) of \(syllables.count): \(syllable)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ToneAnnotatedSentenceView(
                            text: syllable,
                            fontSize: 44,
                            showInfoButtons: true,
                            word: nil,
                            treatTextAsSingleSyllable: true
                        )
                        HStack(spacing: 12) {
                            Text("Got: \(gotIPA)")
                                .foregroundColor(expectedIPA.isEmpty ? .secondary : (gotIPA == expectedIPA ? .green : .red))
                            if !expectedIPA.isEmpty {
                                Text("Exp: \(expectedIPA)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.title)
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(current.test.text)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(current.ipaOK == true ? .green : (current.ipaOK == false ? .red : .primary))
                    Button {
                        openDetailView(for: current.test.text)
                    } label: {
                        Label("Detail", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
                Text(lookupState.statusText)
                    .font(.subheadline)
                    .foregroundColor(lookupStateColor(lookupState))

                if let rawSentenceDebugText = lookupState.rawSentenceDebugText {
                    Text(rawSentenceDebugText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if case .noStoredSyllables(let rawSentence) = lookupState {
                    Text("Raw sentence field: \(rawSentence ?? "nil")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if case .malformedStoredSyllables(let rawSentence, let rawSyllables) = lookupState {
                    Text("Raw sentence field: \(rawSentence ?? "nil")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Raw syllables: \(rawSyllables.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if case .fetchFailed(let message) = lookupState {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

@ViewBuilder
private func guardSection<Content: View>(title: String, show: Bool, @ViewBuilder content: () -> Content) -> some View {
    if show {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct IPACompareView: View {
    let syls: [ThaiSyllable]
    let expectedIPA: String?

    var body: some View {
        let gotIPA = syls.map { syllable in
            let info = analyzeToneSentence(syllable.original, treatTextAsSingleSyllable: true).first
            return info.map { toneIPA(for: $0) } ?? ""
        }.filter { !$0.isEmpty }.joined(separator: ".")
        let expected = expectedIPA ?? ""
        let mismatch = !expected.isEmpty && gotIPA != expected
        let color: Color = expected.isEmpty ? .secondary : (mismatch ? .red : .green)

        HStack(spacing: 6) {
            Text(gotIPA).foregroundColor(color)
            if !expected.isEmpty {
                Text(expected).foregroundColor(color)
            } else {
                Text("–").foregroundColor(.secondary)
            }
        }
        .font(.callout)
    }
}

#Preview {
    QuickThaiSyllableTestsView()
}
