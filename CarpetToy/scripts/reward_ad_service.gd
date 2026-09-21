extends RefCounted
## Provider adapter only. No provider means no ad availability or rewards.
signal verified_reward(job_id: String, receipt_id: String)
var _provider: Object
var _pending: Dictionary = {}
var _nonce_serial := 0

func configure(provider: Object) -> bool:
	if provider == null or not provider.has_method("is_rewarded_ad_available") or not provider.has_method("request_verified_reward") or not provider.has_method("verify_reward_receipt"):
		return false
	_provider = provider
	return true

func is_rewarded_ad_available() -> bool:
	return is_instance_valid(_provider) and bool(_provider.call("is_rewarded_ad_available"))

func cancel_pending() -> void:
	_pending.clear()

func request_reward(job_id: String) -> bool:
	if job_id.is_empty() or _pending.has(job_id) or not is_rewarded_ad_available():
		return false
	_nonce_serial += 1
	var nonce := "%d-%d-%d" % [Time.get_ticks_usec(), _nonce_serial, randi()]
	_pending[job_id] = nonce
	var started := bool(_provider.call("request_verified_reward", job_id, nonce, _on_provider_result))
	if not started: _pending.erase(job_id)
	return started

func _on_provider_result(job_id: String, nonce: String, receipt: Dictionary) -> void:
	if not _pending.has(job_id) or str(_pending[job_id]) != nonce:
		return
	_pending.erase(job_id)
	if not is_instance_valid(_provider) or not bool(_provider.call("verify_reward_receipt", job_id, nonce, receipt)):
		return
	var receipt_id: String = str(receipt.get("receipt_id", ""))
	if receipt_id.is_empty(): return
	verified_reward.emit(job_id, receipt_id)
