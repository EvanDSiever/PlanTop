import AppKit
import WebKit

extension Notification.Name {
    public static let songTopYouTubeAuthChanged = Notification.Name("com.songtop.youtubeAuthChanged")
}

public final class YouTubeLoginWindowController: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let indicator = NSProgressIndicator()
    public var onLoginCompleted: (() -> Void)?
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign In to YouTube / Google Account"
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        
        // Header Bar
        let headerView = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 44, width: contentView.bounds.width, height: 44))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1.0).cgColor
        contentView.addSubview(headerView)
        
        let titleLabel = NSTextField(labelWithString: "Sign In to YouTube (Premium / Personal Account)")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 16, y: 14, width: 380, height: 16)
        headerView.addSubview(titleLabel)
        
        let doneButton = NSButton(title: "Done", target: self, action: #selector(handleDone))
        doneButton.bezelStyle = .rounded
        doneButton.frame = NSRect(x: contentView.bounds.width - 80, y: 8, width: 68, height: 28)
        doneButton.autoresizingMask = [.minXMargin]
        headerView.addSubview(doneButton)
        
        // WebKit Configuration with Persistent Data Store
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let webViewFrame = NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 44)
        webView = WKWebView(frame: webViewFrame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        contentView.addSubview(webView)
        
        // Progress Spinner
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.frame = NSRect(x: (contentView.bounds.width - 24) / 2, y: (contentView.bounds.height - 24) / 2, width: 24, height: 24)
        indicator.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        indicator.isDisplayedWhenStopped = false
        contentView.addSubview(indicator)
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue") {
            indicator.startAnimation(nil)
            webView.load(URLRequest(url: url))
        }
    }
    
    @objc private func handleDone() {
        window?.close()
        NotificationCenter.default.post(name: .songTopYouTubeAuthChanged, object: nil)
        onLoginCompleted?()
    }
    
    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        indicator.startAnimation(nil)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        indicator.stopAnimation(nil)
        if let currentURL = webView.url?.absoluteString, currentURL.contains("youtube.com") && !currentURL.contains("accounts.google.com") {
            NotificationCenter.default.post(name: .songTopYouTubeAuthChanged, object: nil)
        }
    }
}
