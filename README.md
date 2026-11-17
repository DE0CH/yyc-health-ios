# YYC Systems (iPhone)

Deyao's system health page, `https://newswatch.yyc-internal.com/app/health` (DE0CH/yyc-code news-stream, README "The
system health page"), full screen on his iPhone: a UIKit app with one WKWebView filling the safe area (on an iPhone 17,
402 x 778 pt, the size the page fits its detail to). The page draws everything; the app signs in and holds the token.

- **Sign-in:** the system sign-in sheet (ASWebAuthenticationSession, Safari's cookies) opens `/app/health/app-signin`;
  Cloudflare Access signs Deyao in with Google and the page answers `dev.de0ch.yycsystems://signed-in?state=…#token=…`.
  The token is kept in the Keychain (this device only) and given to the WebView as the `CF_Authorization` cookie. When
  the WebView is sent to Access's login (the token is spent) or the page answers 404, the app drops it and opens the
  sheet again.
- **No scroll, no zoom, portrait, dark.** No connection: it says so and tries again every 10 s.
- Bundle `dev.de0ch.yycsystems`, home-screen name "YYC Systems", App Store Connect record "YYC Systems DE0CH",
  TestFlight group Owner. Team S64YL394S3.
- **CI** (`.github/workflows/ios.yml`, every push to `main`): xcodegen, the phone replica on an iPhone 17 simulator
  against `ios/stub/stub.py` (sign-in sheet and the page with its cookie in a 402 x 778 window, the token kept over a
  relaunch, a spent token back to sign-in; screenshots and a video in the `replica-screens` artifact), an unsigned
  archive, cloud-signed export and TestFlight upload. Secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`.
