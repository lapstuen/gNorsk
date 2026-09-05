import SwiftUI
import CoreData

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(AppState.self) private var appState
    @State private var visSystemFunctions = false
    @State private var admin = AdminManager.shared
    @State private var showPinPrompt = false
    @State private var pinInput = ""
    @State private var pinError = false
    @AppStorage("imageTapLanguage") private var imageTapLanguage: ImageTapLanguage = .thai
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @AppStorage("speechRateThai") private var speechRateThai: Double = 0.5
    @AppStorage("speechRateEnglish") private var speechRateEnglish: Double = 0.5
    @AppStorage("speechRateMorsmaal") private var speechRateMorsmaal: Double = 0.5
    @State private var syncMonitor = CloudKitSyncMonitor.shared
    @State private var showSyncDetails = false
    @State private var wordCount = 0
    @State private var gThaiMirrorMonitor = CloudKitSyncMonitor.gThaiMirror
    @State private var showGThaiMirrorDetails = false
    @State private var gThaiMirrorWordCount = 0
    @State private var mirrorTestWord = "danse"
    @State private var mirrorTestResult: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    private var platform: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #elseif os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.model
        #elseif os(macOS)
        return "Mac"
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Native language x1")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Native language", systemImage: "house")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Native language", selection: $morsmaalLanguage) {
                            ForEach(MorsmaalLanguage.allCases, id: \.self) { lang in
                                Text(lang.label).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Grid view")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Language when tapping image", systemImage: "photo.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Image tap language", selection: $imageTapLanguage) {
                            ForEach(ImageTapLanguage.allCases, id: \.self) { lang in
                                Label(lang.label, systemImage: lang.systemImage).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Speech rate")) {
                    RateSliderRow(label: "Norwegian", icon: "globe.asia.australia", rate: $speechRateThai)
                    RateSliderRow(label: "English", icon: "globe.americas", rate: $speechRateEnglish)
                    RateSliderRow(label: "Native language", icon: "house", rate: $speechRateMorsmaal)
                }

                Section {
                    CloudKitSyncStatusView(
                        monitor: syncMonitor,
                        wordCount: wordCount,
                        showDetails: $showSyncDetails
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: Text("gThai mirror (fallback lookup)")) {
                    CloudKitSyncStatusView(
                        monitor: gThaiMirrorMonitor,
                        wordCount: gThaiMirrorWordCount,
                        showDetails: $showGThaiMirrorDetails
                    )
                    .listRowInsets(EdgeInsets())

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test lookup (translation1)")
                            .font(.subheadline)
                        HStack {
                            TextField("Word", text: $mirrorTestWord)
                                #if os(iOS)
                                .autocapitalization(.none)
                                #endif
                                .textFieldStyle(.roundedBorder)
                            Button("Check") { runMirrorTestLookup() }
                                .buttonStyle(.bordered)
                        }
                        if let result = mirrorTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.hasPrefix("✅") ? .green : .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if admin.isAdmin {
                    Section(header: Text("Maintenance")) {
                        NormalizeThaiSection(context: context)
                    }
                }

                Section(header: Text("About")) {
                    HStack { Text("Version").foregroundStyle(.secondary); Spacer(); Text(appVersion).fontWeight(.medium) }
                    HStack { Text("Build").foregroundStyle(.secondary); Spacer(); Text(buildNumber).fontWeight(.medium) }
                    HStack { Text("Platform").foregroundStyle(.secondary); Spacer(); Text(platform).fontWeight(.medium) }
                    HStack { Text("Device").foregroundStyle(.secondary); Spacer(); Text(deviceName).fontWeight(.medium) }
                }

                Section(header: Text("Administrator")) {
                    if admin.isAdmin {
                        HStack {
                            Label("Admin mode: ON", systemImage: "lock.open.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Turn off") { admin.disable() }
                        }
                    } else {
                        Button {
                            pinInput = ""
                            pinError = false
                            showPinPrompt = true
                        } label: {
                            Label("Enable admin mode", systemImage: "lock.fill")
                        }
                        if pinError {
                            Text("Wrong PIN code").font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                if admin.isAdmin {
                    Section {
                        Button {
                            visSystemFunctions = true
                        } label: {
                            Label("System functions", systemImage: "ellipsis.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("About gNorsk")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $visSystemFunctions) {
                Backup()
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 500, idealWidth: 600, maxWidth: 1000,
                           minHeight: 600, idealHeight: 800, maxHeight: 1200)
                #elseif os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .alert("Enter admin PIN", isPresented: $showPinPrompt) {
                SecureField("PIN", text: $pinInput)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    pinError = !admin.enable(pin: pinInput)
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onAppear { updateWordCount() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            updateWordCount()
        }
    }

    private func updateWordCount() {
        wordCount = syncMonitor.getWordCount()
        gThaiMirrorWordCount = GThaiReferenceStore.shared.recordCount()
    }

    private func runMirrorTestLookup() {
        let word = mirrorTestWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let (found, englishWord) = GThaiReferenceStore.shared.debugLookup(word)
        if found {
            mirrorTestResult = "✅ Found — englishWord: \(englishWord ?? "(empty)")"
        } else {
            mirrorTestResult = "⚠️ Not found in translation1 (\(gThaiMirrorWordCount) records in mirror)"
        }
    }
}

private struct CloudKitSyncStatusView: View {
    let monitor: CloudKitSyncMonitor
    let wordCount: Int
    @Binding var showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                Text("CloudKit Sync")
                    .font(.headline)

                Spacer()

                if monitor.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monitor.statusText)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Word count:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(wordCount)")
                        .fontWeight(.medium)
                }

                if let lastImport = monitor.lastImportDate {
                    HStack {
                        Text("Last import:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDate(lastImport))
                            .fontWeight(.medium)
                    }
                }

                if let error = monitor.lastError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics (since launch):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Total imports:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monitor.totalImportCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Total exports:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monitor.totalExportCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Total failures:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monitor.totalFailureCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(monitor.totalFailureCount > 0 ? .red : .primary)
                }
            }

            if !monitor.syncEvents.isEmpty {
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        Text(showDetails ? "Hide details" : "Show details")
                            .font(.caption)
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if showDetails {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Latest sync events:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(monitor.syncEvents.prefix(10)) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: event.type.icon)
                                        .font(.caption)
                                        .foregroundStyle(event.succeeded ? .green : .red)

                                    Text(event.type.label)
                                        .font(.caption)

                                    Spacer()

                                    Text(formatTime(event.date))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if event.succeeded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }

                                if !event.succeeded {
                                    if let errorDetails = event.errorDetails {
                                        Text("⚠️ \(errorDetails)")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .padding(.leading, 24)
                                    }
                                    if let errorCode = event.errorCode {
                                        Text("Error code: \(errorCode)")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .padding(.leading, 24)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch monitor.statusColor {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct RateSliderRow: View {
    let label: String
    let icon: String
    @Binding var rate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", rate))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .font(.subheadline)
            }
            HStack(spacing: 8) {
                Text("Slow").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $rate, in: 0.3...0.8, step: 0.05)
                Text("Fast").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NormalizeThaiSection: View {
    let context: NSManagedObjectContext
    @State private var status: String? = nil
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Normalize Thai Text")
                .font(.subheadline)
            Text("Fixes hidden duplicates where a Thai word is stored with a different byte order on vowel/tone marks.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let s = status {
                Text(s)
                    .font(.caption.bold())
                    .foregroundStyle(s.hasPrefix("✅") ? .green : .orange)
            }
            Button {
                runNormalization()
            } label: {
                if running {
                    HStack(spacing: 6) { ProgressView().scaleEffect(0.8); Text("Normalizing...") }
                } else {
                    Text("Run normalization")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)
        }
        .padding(.vertical, 4)
    }

    private func runNormalization() {
        running = true
        status = nil
        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        guard let words = try? context.fetch(fetch) else {
            status = "⚠️ Could not fetch words"
            running = false
            return
        }
        var count = 0
        var dupeGroups: [String: [String]] = [:]  // canonical → [original hex dumps]
        for word in words {
            var changed = false
            if let t = word.thaiWord {
                let n = canonicalThaiString(t)
                if n != t {
                    print("🔧 Endret: \(thaiHexDump(t)) → \(thaiHexDump(n))")
                    word.thaiWord = n
                    changed = true
                }
                // Collect for duplicate detection
                dupeGroups[n, default: []].append(thaiHexDump(t))
            }
            if let s = word.sentence {
                let n = canonicalThaiString(s)
                if n != s { word.sentence = n; changed = true }
            }
            if changed { count += 1 }
        }
        // Print duplicates found after normalization
        for (canonical, dumps) in dupeGroups where dumps.count > 1 {
            print("⚠️ Duplikat etter normalisering: '\(canonical)' → \(dumps)")
        }
        do {
            if count > 0 { try context.save() }
            let dupeCount = dupeGroups.values.filter { $0.count > 1 }.count
            var msg = count > 0 ? "✅ \(count) words normalized" : "✅ No byte changes"
            if dupeCount > 0 { msg += " — \(dupeCount) duplicate group(s) in Xcode console" }
            status = msg
        } catch {
            status = "⚠️ \(error.localizedDescription)"
        }
        running = false
    }
}

#Preview {
    AboutView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
