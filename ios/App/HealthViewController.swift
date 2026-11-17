// The one screen: the health page in a WebView filling the safe area (on an iPhone 17, 402 x 778 pt: the page fits its
// detail to exactly that), or, without a usable token, the sign-in. The page draws itself (pixel font, two columns,
// read only); the app only signs in, holds the token, and keeps the WebView from scrolling or zooming.
//
// Sign-in: the system sign-in sheet (ASWebAuthenticationSession, Safari's cookies) opens BASE/app/health/app-signin;
// Access signs Deyao in there and the page answers dev.de0ch.yycsystems://signed-in?state=…#token=…; the token goes to
// the Keychain and into the WebView as the CF_Authorization cookie. When the WebView is sent anywhere but BASE (Access's
// login: the token is spent) or the page answers 404 (not his identity), the token is dropped and the sheet opens again.
//
// Launch arguments for the CI replica (any build): `-base http://127.0.0.1:PORT` (loopback only: never another host),
// `-reset` (forget the token), `-token T` (keep T as if signed in).
import AuthenticationServices
import UIKit
import WebKit

let ground = UIColor(red: 0x11 / 255.0, green: 0x13 / 255.0, blue: 0x15 / 255.0, alpha: 1)
let panel = UIColor(red: 0x1a / 255.0, green: 0x1d / 255.0, blue: 0x20 / 255.0, alpha: 1)
let ink = UIColor(red: 0xe8 / 255.0, green: 0xea / 255.0, blue: 0xec / 255.0, alpha: 1)
let muted = UIColor(red: 0x9e / 255.0, green: 0xa6 / 255.0, blue: 0xae / 255.0, alpha: 1)
let rule = UIColor(red: 0x33 / 255.0, green: 0x39 / 255.0, blue: 0x3f / 255.0, alpha: 1)
let scheme = "dev.de0ch.yycsystems"

/** the site: newswatch, or the replica's loopback stub */
func siteBase() -> URL {
    let args = ProcessInfo.processInfo.arguments
    if let i = args.firstIndex(of: "-base"), i + 1 < args.count, let u = URL(string: args[i + 1]),
       ["127.0.0.1", "localhost"].contains(u.host ?? "") { return u }
    return URL(string: "https://newswatch.yyc-internal.com")!
}

final class HealthViewController: UIViewController, WKNavigationDelegate, ASWebAuthenticationPresentationContextProviding {
    private let base = siteBase()
    private var web: WKWebView!
    private let signIn = UIView()
    private let note = UILabel()
    private let button = UIButton(type: .system)
    private var session: ASWebAuthenticationSession?
    private var retry: Timer?
    private var contextRetries = 0

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ground
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-reset") { TokenStore.delete() }
        if let i = args.firstIndex(of: "-token"), i + 1 < args.count { TokenStore.set(args[i + 1]) }  // the replica's spent token

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.suppressesIncrementalRendering = true  // the page appears drawn, not piece by piece
        web = WKWebView(frame: .zero, configuration: cfg)
        web.accessibilityIdentifier = "health-web"
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = ground
        web.scrollView.backgroundColor = ground
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.isHidden = true
        layout(web)

        signIn.backgroundColor = ground
        layout(signIn)
        let title = UILabel()
        title.text = "YYC Systems"
        title.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        title.textColor = ink
        note.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        note.textColor = muted
        note.numberOfLines = 0
        note.accessibilityIdentifier = "signin-note"
        var bc = UIButton.Configuration.plain()
        bc.title = "Sign in"
        bc.baseForegroundColor = ink
        bc.background.backgroundColor = panel
        bc.background.strokeColor = ink
        bc.background.strokeWidth = 1
        bc.background.cornerRadius = 0
        bc.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        button.configuration = bc
        button.accessibilityIdentifier = "signin"
        button.addAction(UIAction { [weak self] _ in self?.startSignIn() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, note, button])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        signIn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: signIn.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: signIn.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: signIn.topAnchor, constant: 32),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private var started = false
    /** the first start waits for the scene to be active: the sign-in sheet presents only from a window of a
     * foreground-active scene (from viewDidLoad there was no window and the app ended; from viewDidAppear on a first
     * launch the scene was not active yet: ASWebAuthenticationSession error 3, presentationContextInvalid) */
    func becameActive() {
        if !started { started = true; start() }
    }

    /** a view filling the safe area: the page's window is exactly the space between the status bar and the home bar */
    private func layout(_ v: UIView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: g.leadingAnchor), v.trailingAnchor.constraint(equalTo: g.trailingAnchor),
                                     v.topAnchor.constraint(equalTo: g.topAnchor), v.bottomAnchor.constraint(equalTo: g.bottomAnchor)])
    }

    private func start() {
        if let t = TokenStore.get(), TokenStore.usable(t) { show(t) } else { needSignIn("Not signed in.") }
    }

    func cameToForeground() {
        guard !web.isHidden else { return }
        if !TokenStore.usable(TokenStore.get()) { dropToken("The sign-in has expired.") }
    }

    // ---- the page ----
    private func show(_ token: String) {
        let exp = TokenStore.expiry(token) ?? Date().addingTimeInterval(3600)
        var props: [HTTPCookiePropertyKey: Any] = [.domain: base.host!, .path: "/", .name: "CF_Authorization", .value: token, .expires: exp]
        if base.scheme == "https" { props[.secure] = "TRUE" }
        guard let cookie = HTTPCookie(properties: props) else { return dropToken("The token could not be used.") }
        web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak self] in
            guard let self else { return }
            self.signIn.isHidden = true
            self.web.isHidden = false
            self.web.load(URLRequest(url: self.base.appendingPathComponent("app/health")))
        }
    }

    private func dropToken(_ why: String) {
        TokenStore.delete()
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cs in
            for c in cs where c.name == "CF_Authorization" { self?.web.configuration.websiteDataStore.httpCookieStore.delete(c) }
        }
        web.stopLoading()
        needSignIn(why)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let u = action.request.url
        if u?.scheme == "about" || u?.host == base.host { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        // anywhere else is Access's login (the token is spent) or a link: the page has none
        if action.targetFrame?.isMainFrame ?? true { dropToken("The sign-in has expired.") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let h = response.response as? HTTPURLResponse, h.statusCode == 404 || h.statusCode == 403 {
            decisionHandler(.cancel)
            return dropToken("This account can't see the page (HTTP \(h.statusCode)).")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { offline(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { offline(error) }

    /** no connection: say so and try again every 10 s (the page itself greys out when its reads fail once it is up) */
    private func offline(_ error: Error) {
        let e = error as NSError  // a navigation this app cancelled ends in WebKit's own domain: not a lost connection
        guard e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled else { return }
        web.isHidden = true
        signIn.isHidden = false
        note.text = "Can't reach the page: \(error.localizedDescription) Trying again every 10 s."
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in self?.start() }
    }

    // ---- sign-in ----
    private func needSignIn(_ why: String) {
        web.isHidden = true
        signIn.isHidden = false
        note.text = why + " Sign in with Cloudflare Access (Google)."
        startSignIn()
    }

    private func startSignIn() {
        guard session == nil else { return }
        let state = TokenStore.newState()
        var c = URLComponents(url: base.appendingPathComponent("app/health/app-signin"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "state", value: state)]
        let s = ASWebAuthenticationSession(url: c.url!, callback: .customScheme(scheme)) { [weak self] url, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.session = nil
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    if code == .presentationContextInvalid, self.contextRetries < 5 {  // the scene not active yet: shortly again
                        self.contextRetries += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.startSignIn() }
                        return
                    }
                    let cancelled = code == .canceledLogin
                    self.note.text = cancelled ? "Sign-in cancelled." : "Sign-in failed: \(error.localizedDescription)"
                    return
                }
                guard let url, let token = Self.token(from: url, state: state) else {
                    self.note.text = "Sign-in failed: the answer was not for this request."
                    return
                }
                TokenStore.set(token)
                self.show(token)
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false  // Safari's Access session: signed in already means no prompt
        session = s
        if !s.start() { session = nil; note.text = "Sign-in could not start." }
    }

    /** dev.de0ch.yycsystems://signed-in?state=S#token=T → T, when S is ours */
    static func token(from url: URL, state: String) -> String? {
        guard url.scheme == scheme, url.host == "signed-in",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let frag = url.fragment, frag.hasPrefix("token=") else { return nil }
        let t = String(frag.dropFirst(6)).removingPercentEncoding ?? ""
        return t.isEmpty ? nil : t
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}
