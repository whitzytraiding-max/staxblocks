# STAX — handover note (for the next AI assistant / dev)

This repo is the **canonical base** for STAX going forward. Michael's side (via Claude) took the
previous code drop and added: AdMob, account sign-in (Apple/Google via Supabase), in-app seamless
sign-in, and all the iOS build fixes. **Build from here.** Below is what's done, what's pending, and
the rules.

## ⚠️ iOS builds need post-export patches — READ `BUILD_PIPELINE_iOS.md` FIRST
The Godot **source** here is configured, but a plain `--export-release "iOS"` does NOT produce a
working App Store build. After exporting you MUST apply the patches in `BUILD_PIPELINE_iOS.md`
(link Google frameworks, fix signing, portrait, icon, dark splash, and add the two native files in
`ios_native/`). Until someone turns these into a proper export setup / plugin, they're manual.
Team ID `MXR22HH76N`, bundle `com.whitzy.stax`, Godot 4.6.3.

## What's in the source (works)
- **AdMob**: `addons/admob/` + `ios/plugins/poing-godot-admob*` (real iOS rewarded unit
  `ca-app-pub-8118111609250042/5979726199`; interstitial code exists but is never called). App ID
  in the `.gdip`. Enabled in `project.godot` `[editor_plugins]`; `etc2_astc` on (required for iOS).
- **Account sign-in** (`scripts/Auth.gd`, `scripts/Net.gd`, MainMenu ACCOUNT overlay): OAuth + PKCE
  via Supabase. `AUTH_REDIRECT = "stax://auth"`.
- **Seamless in-app sign-in**: `Auth.gd` writes the authorize URL to a bridge file; the native
  `ios_native/WebAuth.m` presents **ASWebAuthenticationSession** (in-app sheet, no external browser,
  no code paste) and writes the `stax://auth?code=...` callback back, which `Auth.gd._process` polls
  and feeds to `handle_redirect`. (Apple sign-in confirmed working in-app.)
- **Crash-on-close fix**: `ios_native/CleanExit.m` swizzles `applicationWillTerminate:` to `_Exit(0)`
  (Godot 4.x SIGABRTs tearing down GDScript lambdas on terminate).

## Backend (Supabase — owned by Michael's friend, project `dftjbfjgyzpfznsfezpa`)
- SQL run: `profiles` + `link_or_get_profile`/`push_profile`/`get_profile`, plus leaderboard tables/RPCs.
- **Google provider**: enabled (Google Cloud project "STAX", consent screen published).
- **Apple provider**: enabled — Services ID `com.whitzy.stax.signin`, key `H6QYFHZ5PT`. ⏰ The Apple
  client-secret JWT **expires ~Dec 2026**; regenerate it (ES256, from the .p8) and re-set
  `external_apple_secret` via the Management API or dashboard.
- Redirect allow-list includes `stax://auth` + `https://stax-auth.vercel.app` (old paste page; unused now).

## 🐞 KNOWN ISSUE — Google sign-in fails ("sign-in failed"); Apple works
Same in-app flow; Apple completes, Google errors at the token step. `Auth.gd` now surfaces the real
reason on screen (the ACCOUNT overlay status). Get that exact error on device — likely a Google
OAuth config detail (redirect URI / consent / client secret), not the app. Apple is the proof the
bridge + exchange are correct.

## RULES (from the original dev — do NOT break)
- **Never reorder fields in `GameState._save` / `_read_save_fields` — only append at the end.** The
  crash-safe save + no-wipe-on-partial-read depend on the exact order (fixed a real save-wipe bug).
- Leave the crash-safe save intact (atomic temp+rename, `.bak`, never-wipe-on-short-read).

## Nice-to-have next
- Make the seamless-auth native code a proper Godot iOS plugin (see `SEAMLESS_AUTH_SPEC.md`) so it
  survives clean re-exports instead of being a post-export add.
- Real Android rewarded/interstitial unit IDs before a Play release (currently TEST units).
