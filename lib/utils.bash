#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/tinygo-org/tinygo"
TOOL_NAME="tinygo"
TOOL_TEST="tinygo version"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(--proto '=https' --tlsv1.2 -fsSL)

# NOTE: You might want to remove this if <YOUR TOOL> is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	git ls-remote --tags --refs "$GH_REPO" |
		grep -o 'refs/tags/.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	list_github_tags
}

download_release() {
	local version kernel arch filename url
	version="$1"
	kernel="$2"
	arch="$3"
	filename="$4"

	if [ "$kernel" = "Linux" ]; then
		kernel="linux"
	fi
	if [ "$arch" = "x86_64" ]; then
		arch="arm64"
	fi

	# Supported targets:
	# darwin-amd64
	# darwin-arm64
	# linux-amd64
	# linux-arm
	# linux-arm64
	#
	# TinyGo builds for Windows, but I don't have a Windows system for testing.
	url="$GH_REPO/releases/download/v${version}/${TOOL_NAME}${version}.${kernel}-${arch}.tar.gz"

	echo "* Downloading $TOOL_NAME release $version..."
	curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_root_path="${3%/bin}"
	local install_bin_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_bin_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_root_path"

		local tool_cmd
		tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
		test -x "$install_bin_path/$tool_cmd" || fail "Expected $install_bin_path/$tool_cmd to be executable."

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_root_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}
