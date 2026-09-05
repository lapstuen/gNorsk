import SwiftUI
import CoreData

struct EditGroupUrlView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    let groupId: Int16?
    @State private var urlText: String
    let onSave: (String?) -> Void

    init(groupId: Int16?, currentUrl: String?, onSave: @escaping (String?) -> Void) {
        self.groupId = groupId
        self.onSave = onSave
        _urlText = State(initialValue: currentUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("YouTube URL")) {
                    TextField("https://www.youtube.com/watch?v=...", text: $urlText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                }

                Section {
                    Button("Paste from clipboard") {
                        #if canImport(UIKit)
                        if let str = UIPasteboard.general.string {
                            urlText = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        #endif
                    }
                }

                if !urlText.isEmpty {
                    Section {
                        Button("Delete URL", role: .destructive) {
                            urlText = ""
                        }
                    }
                }
            }
            .navigationTitle("Group YouTube URL")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveUrl()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveUrl() {
        guard let gid = groupId else { dismiss(); return }
        let request: NSFetchRequest<Group> = Group.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %d", gid)
        request.fetchLimit = 1
        if let group = try? context.fetch(request).first {
            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            group.youtubeUrl = trimmed.isEmpty ? nil : trimmed
            try? context.save()
            onSave(trimmed.isEmpty ? nil : trimmed)
        }
        dismiss()
    }
}
