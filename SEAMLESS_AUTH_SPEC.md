# Spec: seamless in-app sign-in (no external browser, no code paste)

**Goal:** Tapping Google/Apple opens an **in-app** auth sheet, the user signs in, and the app is
linked automatically — no Safari hand-off, no copy/paste of a code.

**Current state:** `Auth.gd` works via `OS.shell_open()` (external Safari) + a paste-code web page
(`AUTH_REDIRECT = https://stax-auth.vercel.app`). The token exchange + profile sync are already
built (`Auth.complete_with_code` / `handle_redirect`). We only need to replace the *transport*.

**Backend is fully configured** (don't change): Supabase project `dftjbfjgyzpfznsfezpa`, Google +
Apple providers enabled, redirect allow-list includes `stax://auth`. So switching the app to the
`stax://` redirect "just works" server-side.

## Approach: ASWebAuthenticationSession (the iOS-standard for OAuth in apps)
It shows an in-app Safari sheet AND auto-captures the `stax://auth?code=...` redirect, returning it
straight to the app. Works for both Google and Apple (same web flow). (Optionally use the fully
native `ASAuthorizationController` for Apple later; not required.)

### 1. Register the URL scheme (iOS export → Info.plist)
Add to the app's `Info.plist` a `CFBundleURLTypes` entry with URL scheme **`stax`**. Easiest in
the Godot iOS export preset's "Additional Plist Content", so it's reproducible:
```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLSchemes</key><array><string>stax</string></array>
</dict></array>
```

### 2. Auth.gd — switch redirect + add a native call hook
- `const AUTH_REDIRECT := "stax://auth"`
- In `begin_sign_in()`, instead of `OS.shell_open(url)`, call the native plugin:
  `WebAuth.start(url, "stax")` (see plugin below).
- Add: `func _on_web_auth_result(callback_url: String) -> void: handle_redirect(callback_url)`
  connected to the plugin's `completed` signal. (`handle_redirect` already parses `?code=` and runs
  the PKCE exchange — no other changes needed.)

### 3. The native plugin (Godot iOS plugin: `WebAuth`)
A small Godot iOS plugin exposing one Object singleton:
- Method `start(authorize_url: String, callback_scheme: String)`:
  - Presents `ASWebAuthenticationSession(url:, callbackURLScheme: callback_scheme, completionHandler:)`
    from the Godot root view controller; set `presentationContextProvider`; keep a strong ref to the
    session; set `prefersEphemeralWebBrowserSession = false` (so existing Google/Apple logins are reused).
  - On completion: emit signal `completed(callback_url: String)` (deferred onto the main/Godot thread)
    with the returned URL (contains `?code=...`). On error/cancel, emit `failed(reason)`.
- Link `AuthenticationServices.framework`.
- Package as a `.gdip` + xcframework under `ios/plugins/` (same mechanism as the Poing AdMob plugin),
  so it's in-source and survives re-exports.

(If you prefer not to write a plugin from scratch, there are community Godot 4 iOS plugins for
ASWebAuthenticationSession / deep links — the contract above is all `Auth.gd` needs.)

### Result
Tap Google/Apple → in-app sheet → sign in → sheet dismisses → signed in. The Vercel paste page is
no longer used (can stay as a harmless fallback).
