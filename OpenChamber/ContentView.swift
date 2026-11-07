import SwiftUI
import WebKit
import UIKit

// 改成你的服务器地址即可（必须是 https）
let kStartURL = URL(string: "https://www.zhuzhiwei888888.cn:28443/")!

struct ContentView: View {
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            WebView(
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                reloadToken: reloadToken
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在连接…").font(.footnote).foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            if let message = errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("无法连接服务器").font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        errorMessage = nil
                        isLoading = true
                        reloadToken += 1
                    } label: {
                        Text("重试").fontWeight(.semibold)
                            .padding(.horizontal, 26).padding(.vertical, 10)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundColor(.white)
                    }
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(30)
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.load(kStartURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.load(kStartURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private var parent: WebView
        weak var webView: WKWebView?
        var lastReloadToken = 0
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(_ parent: WebView) { self.parent = parent }

        func load(_ url: URL) {
            var request = URLRequest(url: url)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 30
            webView?.load(request)
        }

        @objc func handleRefresh() {
            webView?.reload()
        }

        // MARK: - Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.errorMessage = nil
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
            parent.errorMessage = friendly(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
            parent.errorMessage = friendly(error)
        }

        private func friendly(_ error: Error) -> String {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorNotConnectedToInternet: return "手机没有连接网络。"
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "服务器地址无法访问，请确认电脑和网络正常。"
                case NSURLErrorTimedOut: return "连接超时，请稍后重试。"
                case NSURLErrorSecureConnectionFailed: return "证书校验失败，请检查服务器 HTTPS 证书。"
                default: break
                }
            }
            return ns.localizedDescription
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            if navigationAction.targetFrame == nil {
                // target=_blank：留在应用内打开
                if let url = navigationAction.request.url {
                    webView.load(URLRequest(url: url))
                }
                decisionHandler(.cancel)
                return
            }

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (url.scheme ?? "").lowercased()
            if scheme == "http" || scheme == "https" {
                if url.host == kStartURL.host {
                    decisionHandler(.allow)
                } else {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                }
                return
            }
            if scheme == "mailto" || scheme == "tel" || scheme == "sms" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        // MARK: - Downloads

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let dir = FileManager.default.temporaryDirectory
            var url = dir.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
            var index = 1
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            while FileManager.default.fileExists(atPath: url.path) {
                let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
                url = dir.appendingPathComponent(name)
                index += 1
            }
            downloadDestinations[ObjectIdentifier(download)] = url
            completionHandler(url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            presentShareSheet(for: url)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }

        private func presentShareSheet(for url: URL) {
            guard let controller = topViewController() else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = controller.view
            activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
                                                                        y: controller.view.bounds.midY,
                                                                        width: 0, height: 0)
            controller.present(activity, animated: true)
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes
            guard let windowScene = scenes.first as? UIWindowScene,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return nil }
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController { controller = presented }
            return controller
        }

        // MARK: - Capture permissions (mic / camera)

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // MARK: - JS dialogs

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            topViewController()?.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            topViewController()?.present(alert, animated: true)
        }
    }
}
