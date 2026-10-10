extends RefCounted
## Shared bounded currency and compact labels. Currency never passes through int64.
const MAX_VALUE := 1e60
const SUFFIXES := ["", "K", "M", "B", "T", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AH", "AI", "AJ", "AK", "AL", "AM", "AN", "AO", "AP"]


static func is_valid(value: Variant, minimum: float = 0.0) -> bool:
	if not (value is int or value is float) or not is_finite(minimum):
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= MAX_VALUE


static func rounded(value: float) -> float:
	# Negative progression sentinels remain negative. Invalid arithmetic must
	# remain invalid so the ledger can reject it instead of manufacturing money.
	if not is_finite(value) or absf(value) > MAX_VALUE:
		return NAN
	return roundf(value)


static func format(value: float, decimals: int = 1) -> String:
	if not is_finite(value):
		return "0"
	var negative := value < 0.0
	var number := absf(value)
	var group := 0
	while number >= 1000.0 and group < SUFFIXES.size() - 1:
		number /= 1000.0
		group += 1
	# Select the group iteratively, then scale once to avoid accumulating
	# division error around half-way decimal values such as 1.25AF.
	number = absf(value) / pow(1000.0, float(group))
	var places := clampi(decimals, 0, 3) if group > 0 else 0
	var precision := pow(10.0, places)
	number = roundf(number * precision) / precision
	# Rounding 999.95K should show 1M, never 1000K. This also handles the
	# slight representation differences around exact powers of one thousand.
	if number >= 1000.0 and group < SUFFIXES.size() - 1:
		number /= 1000.0
		group += 1
		places = clampi(decimals, 0, 3)
	var pattern := "%." + str(places) + "f"
	var label := pattern % number
	if places > 0:
		while label.ends_with("0"):
			label = label.left(label.length() - 1)
		label = label.trim_suffix(".")
	return ("-" if negative and number > 0.0 else "") + label + str(SUFFIXES[group])
