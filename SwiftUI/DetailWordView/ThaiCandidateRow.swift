import SwiftUI

struct ThaiCandidateRow: View {
    let text: String
    let inDB: Bool
    let englishWord: String?
    let externalDef: String?
    let lookedUp: Bool
    let onOpenDetail: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(text)
                if inDB, let englishWord {
                    Text(englishWord)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Ikke bruk Group – la ViewBuilder håndtere én gren som returnerer én view
            if inDB {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let def = externalDef {
                Text(def)
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            } else if lookedUp {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.red)
            } else {
                EmptyView()
            }

            Button {
                onOpenDetail(text)
            } label: {
                Image(systemName: "globe")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}
