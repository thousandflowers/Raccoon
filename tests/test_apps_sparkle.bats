#!/usr/bin/env bats
# Unit tests for the Sparkle appcast decision logic (_sparkle_decide). Sourcing
# apps.sh exposes the function without running main (guarded at the bottom).
# Fixtures are synthetic appcast XML, so nothing touches the network.

load test_helper

setup() {
	setup_raccoon_env
	# shellcheck disable=SC1090
	source "$SCRIPT_DIR/bin/apps.sh"
}
teardown() { teardown_raccoon_env; }

# Newest item first, versions carried on the enclosure attributes (IINA-style).
iina_feed() {
	cat <<'XML'
<rss><channel>
<item><title>1.4.4</title>
<enclosure url="https://dl.example/IINA.v1.4.4.dmg" sparkle:version="1.4.4" sparkle:shortVersionString="1.4.4"/>
</item>
<item><title>1.4.3</title>
<enclosure url="https://dl.example/IINA.v1.4.3.dmg" sparkle:shortVersionString="1.4.3"/>
</item>
</channel></rss>
XML
}

# shortVersionString as a child element, alongside a build number that must NOT
# be compared against the marketing version (AppCleaner-style).
build_feed() {
	cat <<'XML'
<rss><channel>
<item>
<sparkle:shortVersionString>3.6.9</sparkle:shortVersionString>
<sparkle:version>3805</sparkle:version>
<enclosure url="https://dl.example/AppCleaner_3.6.9.zip"/>
</item>
</channel></rss>
XML
}

@test "sparkle: picks the newest short version and its download URL" {
	out="$(iina_feed | _sparkle_decide '1.4.3' '1.4.3')"
	[[ "$out" == *"1.4.4"* ]]
	[[ "$out" == *"https://dl.example/IINA.v1.4.4.dmg"* ]]
}

@test "sparkle: compares short-vs-short, ignoring the build number" {
	out="$(build_feed | _sparkle_decide '3.6.8' '3804')"
	[[ "$out" == *"3.6.9"* ]]
	[[ "$out" == *"AppCleaner_3.6.9.zip"* ]]
}

@test "sparkle: no output when already up to date" {
	out="$(iina_feed | _sparkle_decide '1.4.4' '1.4.4')"
	[[ -z "$out" ]]
}

@test "sparkle: falls back to build-vs-build when no short version present" {
	out="$(printf '%s' '<rss><channel><item><sparkle:version>200</sparkle:version><enclosure url="https://dl.example/a.zip"/></item></channel></rss>' | _sparkle_decide '' '100')"
	[[ "$out" == *"200"* ]]
	[[ "$out" == *"a.zip"* ]]
}
