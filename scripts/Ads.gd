extends Node

# Plugin-agnostic ad layer. If the Poing Studios AdMob addon is installed
# (res://addons/admob/), the real implementation (AdsAdmob.gd) is loaded at
# runtime — that script references the plugin's classes and must never be
# parsed when the addon is missing, which is why it's load()ed here instead
# of preloaded. Without the addon (desktop dev), rewarded ads simulate
# success so the whole flow stays testable.

const INTERSTITIAL_EVERY := 2   # show an interstitial every Nth game over

var _impl : Node = null         # AdsAdmob instance when plugin present
var _game_overs := 0

func _ready() -> void:
	if FileAccess.file_exists("res://addons/admob/plugin.cfg"):
		var impl_script := load("res://scripts/AdsAdmob.gd")
		if impl_script != null:
			_impl = impl_script.new()
			add_child(_impl)

func _is_mobile() -> bool:
	return OS.get_name() == "iOS" or OS.get_name() == "Android"

# A rewarded ad can be offered: real ad loaded, or dev simulation off-device
func can_offer_rewarded() -> bool:
	if _impl != null and _impl.is_rewarded_ready():
		return true
	return not _is_mobile()   # desktop dev: always offer (simulated)

# Shows the rewarded ad; calls back exactly once with true if the reward
# was earned (player may close the ad early → false)
func show_rewarded(on_finished: Callable) -> void:
	if _impl != null and _impl.is_rewarded_ready():
		_impl.show_rewarded(on_finished)
	elif not _is_mobile():
		on_finished.call(true)    # dev simulation
	else:
		on_finished.call(false)   # mobile with no fill — don't grant

# Call once per game over; shows an interstitial every INTERSTITIAL_EVERY-th
func notify_game_over() -> void:
	_game_overs += 1
	if _game_overs % INTERSTITIAL_EVERY != 0:
		return
	if _impl != null:
		_impl.show_interstitial()
