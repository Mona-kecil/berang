// Shows one web page in a WebKit window, so berang-grab can save the page's accessibility tree.
// usage: page-viewer <url> [script]   Prints "loaded" once the page has finished loading and settled.
// The script, if given, runs in the page after it settles and before "loaded", such as to scroll or select text.
import AppKit
import WebKit

@MainActor final class Viewer: NSObject, WKNavigationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 900),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let web = WKWebView()
    var script: String?

    func show(_ url: URL) {
        web.navigationDelegate = self
        window.contentView = web
        window.title = url.host() ?? "page"
        window.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Late scripts and lazy text settle in the next few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            guard let script else { print("loaded"); fflush(stdout); return }
            web.evaluateJavaScript(script) { _, error in
                print(error.map { "failed: \($0.localizedDescription)" } ?? "loaded"); fflush(stdout)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("failed: \(error.localizedDescription)"); fflush(stdout)
    }
}

guard CommandLine.arguments.count > 1, let url = URL(string: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: page-viewer <url>\n".utf8))
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let viewer = Viewer()
viewer.script = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
viewer.show(url)
app.run()
