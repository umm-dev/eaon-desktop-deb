import SwiftUI
import WebKit

/// The content of the "model page" pop-up window (see the `WindowGroup(for:
/// URL.self)` scene in `App.swift`) — a real, separate, resizable app window
/// with its own titlebar and traffic lights, embedding the model's actual
/// page (Ollama's library page, or a Hugging Face repo page) rather than
/// switching out to the system browser.
struct ModelBrowserWindow: View {
    @Environment(\.themeColors) private var colors
    let url: URL

    var body: some View {
        ModelBrowserWebView(url: url)
            .frame(minWidth: 480, minHeight: 360)
            .background(colors.backgroundPrimary)
            .navigationTitle(url.host ?? "Model")
    }
}

private struct ModelBrowserWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    // `url` is fixed for the lifetime of this window (each pop-up is opened
    // fresh per model via `openWindow(value:)`), so there's nothing to diff.
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
