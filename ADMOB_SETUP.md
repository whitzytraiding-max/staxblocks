# AdMob Setup — what's done and what's left

## Already wired in code (works today)

- `scripts/Ads.gd` (autoload) — plugin-agnostic ad layer. On desktop with no
  plugin it SIMULATES rewarded ads (always succeeds) so the game stays
  testable. It auto-detects the AdMob addon at `res://addons/admob/` and
  switches to real ads when present.
- `scripts/AdsAdmob.gd` — the real implementation: UMP consent flow at
  startup (GDPR + the ATT message you configure in the AdMob console),
  rewarded ad for the revive, interstitial every 2nd game over, auto-reload
  after shows/failures. Currently uses **Google's official TEST unit IDs**.
- Game flow: one revive per run (button hides after use), watch-ad button
  hides when no ad is available, reward only granted if the ad is watched
  to the end.

## Step 1 — Install the addon (any machine, 2 minutes)

1. Download: https://github.com/poing-studios/godot-admob-plugin/releases/download/v4.3.1/poing-godot-admob-v4.3.1.zip
2. Extract the zip's `addons/` folder into the project root
   (result: `block_blast/addons/admob/plugin.cfg` exists).
3. Godot: Project → Project Settings → Plugins → enable **AdMob**.
4. Run the game on desktop — console should stay clean; ads remain simulated
   on desktop, that's expected.

## Step 2 — iOS native plugin (on the Mac, at export time)

1. Download (version MUST match Godot 4.6.x): https://github.com/poing-studios/godot-admob-plugin/releases/download/v4.3.1/poing-godot-admob-ios-v4.6.3.zip
2. Extract into the project so you get `res://ios/plugins/poing-godot-admob/...`
   (alternatively use the editor tool: Project → Tools → AdMob Manager → iOS → Download & Install).
3. In the iOS export preset, tick the AdMob plugin under **Plugins**.

## Step 3 — AdMob console (https://apps.admob.com)

1. Create the app (iOS) → note the **App ID** (`ca-app-pub-XXXX~YYYY`).
2. Create two ad units:
   - Rewarded → "Continue Run"
   - Interstitial → "Game Over"
3. Paste the two unit IDs into `scripts/AdsAdmob.gd` (the `REWARDED_UNIT` /
   `INTERSTITIAL_UNIT` constants — replace the iOS test values).
4. Privacy & messaging → create the **GDPR message** and the **iOS ATT
   message** (the code already runs the consent flow that displays them).

## Step 4 — Info.plist keys (iOS export preset → "Additional Plist Content")

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXX~YYYY</string>
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

Plus Google's SKAdNetwork list (copy the `SKAdNetworkItems` block from):
https://developers.google.com/admob/ios/quick-start#update_your_infoplist

## Step 5 — App Store privacy

In App Store Connect, declare data collection per Google's guidance
(Identifiers/Usage Data, used for third-party advertising). Apple rejects
mismatched labels.

## Testing rules

- TestFlight builds: keep the TEST unit IDs (they always fill).
- Swap to real IDs only for the App Store release build.
- NEVER tap real ads on your own device repeatedly — AdMob bans for it.
