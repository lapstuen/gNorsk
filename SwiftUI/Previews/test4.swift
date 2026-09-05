import SwiftUI

struct TabbedSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Innhold inkludert X-knappen
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                            .padding()
                    }
                }

                TabView {
                    Text("First tab")
                        .padding()
                        .background(.yellow)
                        .tabItem {
                            Label("Low", systemImage: "character")
                        }

                    Text("Second tab")
                        .padding()
                        .background(.red)
                        .tabItem {
                            Label("High", systemImage: "flag")
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .ignoresSafeArea()
    }
}

struct TabSheetHostView: View {
    @State private var showSheet = false

    var body: some View {
        VStack {
            Text("Test Sheet with TabView and X button")
                .font(.title)

            Button("Open sheet") {
                showSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showSheet) {
            TabbedSheetView()
        }
        .padding()
    }
}

#Preview {
    TabSheetHostView()
}
