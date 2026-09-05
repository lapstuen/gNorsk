import SwiftUI

struct MainMenuButtonExtended: View {
    let title: String
    var color: Color = .blue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(color)
                .cornerRadius(10)
                .font(.headline)
        }
    }
}

#Preview("Select Group") {
    MainMenuButtonExtended(title: "Select Group", color: .red) {
        print("Select Group tapped")
    }
    .padding()
}

#Preview("Edit groups") {
    MainMenuButtonExtended(title: "Edit groups", color: .orange) {
        print("Edit groups tappet")
    }
    .padding()
}

#Preview("Start vocabulary") {
    MainMenuButtonExtended(title: "Start vocabulary", color: .green) {
        print("Start vocabulary tappet")
    }
    .padding()
}

#Preview("GoogleTranslate") {
    MainMenuButtonExtended(title: "GoogleTranslate", color: .blue) {
        print("GoogleTranslate tappet")
    }
    .padding()
}
