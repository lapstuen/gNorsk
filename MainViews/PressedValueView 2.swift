import SwiftUI

struct PressedValueView: View {
    let value: String
    let word: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("You selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.largeTitle).bold()
                }

                VStack(spacing: 8) {
                    Text("Word")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(word.isEmpty ? "—" : word)
                        .font(.title2)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
            .navigationTitle("Menu Selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

#Preview {
    PressedValueView(value: "menu one", word: "สวัสดี")
}
