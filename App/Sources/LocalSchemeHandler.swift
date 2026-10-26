import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves the bundled `www/` folder over a private `app://local/...` origin.
/// A real origin (instead of file://) keeps localStorage stable, so stats and streaks persist.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "app"
    static let host = "local"
    static var startURL: URL { URL(string: "\(scheme)://\(host)/index.html")! }

    private let root: URL? = Bundle.main.resourceURL?.appendingPathComponent("www", isDirectory: true)

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path

        guard let root = root else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let fileURL = root.appendingPathComponent(relative).standardizedFileURL
        // Never serve anything outside the www folder.
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        var mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        if ext == "html" { mime = "text/html" }
        if mime.hasPrefix("text/") || mime == "application/javascript" || mime == "application/json" {
            mime += "; charset=utf-8"
        }
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            urlSchemeTask.didFailWithError(URLError(.cannotCreateFile))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel: responses are delivered synchronously.
    }
}
