import SwiftUI

struct MainAppViewPreviewWrapper: View {
    let appState = AppState()  // 🔑 Ikke @State

    var body: some View {
        MainAppView()
            .environment(appState)  // 🔑 Ny stil (SwiftUI 5)
    }
}

#Preview {
    MainAppViewPreviewWrapper()
}
