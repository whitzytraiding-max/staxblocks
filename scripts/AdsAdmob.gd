extends Node

# Real AdMob implementation — references classes provided by the Poing
# Studios addon (res://addons/admob/). NEVER preload/reference this script
# statically: Ads.gd load()s it at runtime only when the addon is installed.
#
# iOS rewarded unit ID is LIVE (production). iOS interstitial + both Android
# unit IDs are still Google test IDs — replace before Android release.

const REWARDED_UNIT := {
	"iOS":     "ca-app-pub-8118111609250042/5979726199",
	"Android": "ca-app-pub-3940256099942544/5224354917",   # TEST — replace with Android unit ID
}
const INTERSTITIAL_UNIT := {
	"iOS":     "ca-app-pub-3940256099942544/4411468910",   # TEST — replace
	"Android": "ca-app-pub-3940256099942544/1033173712",   # TEST — replace
}

var _rewarded_ad     : RewardedAd
var _interstitial_ad : InterstitialAd
var _reward_earned   := false
var _on_finished     : Callable

func _ready() -> void:
	_request_consent_then_init()

# ── UMP consent (GDPR + the AdMob-console-configured ATT message on iOS) ─────
func _request_consent_then_init() -> void:
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(params,
		func():
			var status = UserMessagingPlatform.consent_information.get_consent_status()
			if status == ConsentInformation.ConsentStatus.REQUIRED:
				UserMessagingPlatform.load_consent_form(
					func(form: ConsentForm):
						form.show(func(_err): _init_ads()),
					func(_err): _init_ads())
			else:
				_init_ads(),
		func(_err):
			# Consent update failed (offline etc) — still init; AdMob will
			# serve non-personalized/test ads as appropriate
			_init_ads())

func _init_ads() -> void:
	MobileAds.initialize()
	_load_rewarded()
	_load_interstitial()

func _unit(table: Dictionary) -> String:
	return table.get(OS.get_name(), table["Android"])

# ── Rewarded ──────────────────────────────────────────────────────────────────
func _load_rewarded() -> void:
	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd):
		_rewarded_ad = ad
	callback.on_ad_failed_to_load = func(error: LoadAdError):
		print("[Ads] rewarded failed to load: ", error.message)
		get_tree().create_timer(30.0).timeout.connect(_load_rewarded)
	RewardedAdLoader.new().load(_unit(REWARDED_UNIT), AdRequest.new(), callback)

func is_rewarded_ready() -> bool:
	return _rewarded_ad != null

func show_rewarded(on_finished: Callable) -> void:
	if _rewarded_ad == null:
		on_finished.call(false)
		return
	_reward_earned = false
	_on_finished   = on_finished

	var fsc := FullScreenContentCallback.new()
	fsc.on_ad_dismissed_full_screen_content = func():
		var earned := _reward_earned
		var cb := _on_finished
		_load_rewarded()   # preload the next one
		cb.call(earned)
	fsc.on_ad_failed_to_show_full_screen_content = func(_err):
		var cb := _on_finished
		_load_rewarded()
		cb.call(false)
	_rewarded_ad.full_screen_content_callback = fsc

	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item):
		_reward_earned = true
	_rewarded_ad.show(listener)

# ── Interstitial ──────────────────────────────────────────────────────────────
func _load_interstitial() -> void:
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd):
		_interstitial_ad = ad
	callback.on_ad_failed_to_load = func(error: LoadAdError):
		print("[Ads] interstitial failed to load: ", error.message)
		get_tree().create_timer(30.0).timeout.connect(_load_interstitial)
	InterstitialAdLoader.new().load(_unit(INTERSTITIAL_UNIT), AdRequest.new(), callback)

func show_interstitial() -> void:
	if _interstitial_ad == null:
		return
	var fsc := FullScreenContentCallback.new()
	fsc.on_ad_dismissed_full_screen_content = func():
		_load_interstitial()
	_interstitial_ad.full_screen_content_callback = fsc
	_interstitial_ad.show()
