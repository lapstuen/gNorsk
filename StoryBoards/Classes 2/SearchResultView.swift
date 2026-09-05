import SwiftUI
import CoreData

struct SearchResultView: View {
   // var filtrerteId: [String]
    var filtrerteId: [NSManagedObjectID] = []
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                
                Spacer()
                Text("🔍 Søkeresultat (\(filtrerteId.count))")
                    .font(.headline)
                Spacer()
            }
            .padding()

            GridView(filtrerteId: filtrerteId)
                .environment(appState)
                .environment(\.managedObjectContext, context)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

