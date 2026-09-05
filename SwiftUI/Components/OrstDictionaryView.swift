import SwiftUI
import WebKit

// MARK: - Shared holder (reference type — safe across SwiftUI value-type boundary)

private class WebViewHolder: ObservableObject {
    var webView: WKWebView?

    func extractText(js: String, then: @escaping (String) -> Void) {
        guard let wv = webView else { print("⚠️ WebViewHolder: webView is nil"); return }
        wv.evaluateJavaScript(js) { result, error in
            if let error { print("⚠️ JS error: \(error)") }
            let text = (result as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            print("📝 Extracted text length: \(text.count)")
            DispatchQueue.main.async { then(text) }
        }
    }
}

// MARK: - Generic injecting web view

struct InjectedSearchWebView: View {
    let baseURL: String
    let word: String
    let jsTemplate: String
    var extractTextJS: String? = nil

    private static let placeholder = "WORD_PLACEHOLDER"

    @Environment(\.dismiss) private var dismiss
    @StateObject private var holder = WebViewHolder()
    @State private var translateURL: URL? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let extractJS = extractTextJS {
                    HStack {
                        Spacer()
                        Button {
                            holder.extractText(js: extractJS) { text in
                                guard !text.isEmpty,
                                      let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                      let url = URL(string: "https://translate.google.com/?sl=no&tl=th&text=\(encoded)")
                                else { print("⚠️ Ingen tekst å oversette"); return }
                                translateURL = url
                            }
                        } label: {
                            Label("Oversett", systemImage: "globe")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(8)
                    }
                    .background(.ultraThinMaterial)
                }

                _InjectedWebView(
                    baseURL: baseURL,
                    js: jsTemplate.replacingOccurrences(of: Self.placeholder, with: escaped(word)),
                    holder: holder
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Lukk") { dismiss() }
                }
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 1000, minHeight: 800)
            #endif
        }
        .sheet(item: $translateURL) { url in
            SafariView(url: url)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 1200, minHeight: 900)
                #endif
        }
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - UIViewRepresentable

private struct _InjectedWebView: UIViewRepresentable {
    let baseURL: String
    let js: String
    let holder: WebViewHolder

    func makeCoordinator() -> Coordinator { Coordinator(js: js) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        holder.webView = webView
        if let url = URL(string: baseURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        holder.webView = webView
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let js: String
        var hasInjected = false
        init(js: String) { self.js = js }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasInjected else { return }
            hasInjected = true
            webView.evaluateJavaScript(js)
        }
    }
}

// MARK: - Royal Society Dictionary (ORST)

struct OrstDictionaryView: View {
    let word: String
    var body: some View {
        InjectedSearchWebView(
            baseURL: "https://dictionary.orst.go.th/index.php",
            word: word,
            jsTemplate: """
                setTimeout(function() {
                    var input = document.getElementById('txt_input');
                    if (input) {
                        input.value = 'WORD_PLACEHOLDER';
                        document.getElementById('btnSubmit').click();
                    }
                }, 600);
                """,
            extractTextJS: """
                (function() {
                    var el = document.getElementById('r_lookup')
                          || document.getElementById('r_lookup_con')
                          || document.getElementById('wordlist');
                    return el ? el.innerText : '';
                })()
                """
        )
    }
}

// MARK: - thai-language.com

struct ThaiLanguageDictionaryView: View {
    let word: String
    var body: some View {
        InjectedSearchWebView(
            baseURL: "http://www.thai-language.com/",
            word: word,
            jsTemplate: """
                setTimeout(function() {
                    var input = document.getElementById('search');
                    if (input) {
                        input.value = 'WORD_PLACEHOLDER';
                        input.form.submit();
                    }
                }, 400);
                """
        )
    }
}
