import SafariServices
import SwiftUI
import WebKit

struct SafariView: View {
    let url: URL

    var body: some View {
        #if targetEnvironment(macCatalyst)
        _CatalystExternalBrowserView(url: url)
            .frame(minWidth: 1200, minHeight: 800)
        #else
        _SafariVC(url: url)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

// iPad/iPhone: native SFSafariViewController
private struct _SafariVC: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// Mac Catalyst: åpne URL eksternt for å unngå NSRemoteView/WKWebView-sheet assertions.
private struct _CatalystExternalBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Opening in browser...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            UIApplication.shared.open(url, options: [:]) { _ in
                dismiss()
            }
        }
    }
}
