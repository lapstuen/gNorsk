import SwiftUI

struct SelectedMenuView: View {
    @Environment(\.dismiss) private var dismiss
    let selectedValue: String
    let thaiWord: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Selected Value:")
                .font(.headline)
            Text(selectedValue)
                .font(.largeTitle)
                .bold()
            Text("Norwegian Word:")
                .font(.headline)
            Text(thaiWord)
                .font(.title)
                .foregroundColor(.purple)
            Button("Close") {
                dismiss()
            }
            .padding()
            .background(Color.blue.opacity(0.2))
            .cornerRadius(10)
        }
        .padding()
    }
}

struct SelectedMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedMenuView(selectedValue: "Menu 1", thaiWord: "สวัสดี")
    }
}
