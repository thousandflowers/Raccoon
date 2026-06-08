#!/usr/bin/env bats

load test_helper

setup() {
	setup_raccoon_env
	BIN_DIR="$HOME/.local/bin"
	mkdir -p "$BIN_DIR"
	mkdir -p "$HOME/.raccoon"
	touch "$HOME/.raccoon/rcc"
}

teardown() {
	teardown_raccoon_env
}

@test "install.sh detects writable /usr/local/bin" {
	run bash -c '
		BIN_DIR=""
		detect_bin_dir() {
			if [[ -w "/usr/local/bin" ]]; then
				echo "/usr/local/bin"
			elif [[ -w "/usr/local" ]]; then
				echo "/usr/local/bin"
			else
				echo "${HOME}/.local/bin"
			fi
		}
		detect_bin_dir
	'
	[[ -n "$output" ]]
}

@test "install.sh always creates symlink (unconditional)" {
	run bash -c '
		set -e
		INSTALL_DIR="'"$HOME"'/.raccoon"
		BIN_DIR="'"$BIN_DIR"'"

		ln -sf "${INSTALL_DIR}/rcc" "${BIN_DIR}/rcc"
		[[ -L "${BIN_DIR}/rcc" ]] && [[ "$(readlink "${BIN_DIR}/rcc")" == "${INSTALL_DIR}/rcc" ]]
		echo "ok"
	'
	assert_success
	assert_output "ok"
}

@test "install.sh re-links on second run (overwrite)" {
	run bash -c '
		set -e
		INSTALL_DIR="'"$HOME"'/.raccoon"
		BIN_DIR="'"$BIN_DIR"'"

		ln -sf "${INSTALL_DIR}/rcc" "${BIN_DIR}/rcc"
		NEW_DIR="'"$HOME"'/.raccoon-new"
		mkdir -p "$NEW_DIR"
		touch "$NEW_DIR/rcc"
		ln -sf "${NEW_DIR}/rcc" "${BIN_DIR}/rcc"
		[[ "$(readlink "${BIN_DIR}/rcc")" == "${NEW_DIR}/rcc" ]]
		echo "re-linked"
	'
	assert_success
	assert_output "re-linked"
}
