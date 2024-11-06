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
	local version="$1"
	local kernel="$2"
	local arch="$3"
	local filename="$4"

	# Supported targets:
	# darwin-amd64
	# darwin-arm64
	# linux-amd64
	# linux-arm
	# linux-arm64
	#
	# TinyGo builds for Windows, but I don't have a Windows system for testing.
	kernel=$(echo "${kernel}" | tr '[:upper:]' '[:lower:]')
	if [ "$arch" = "x86_64" ]; then
		arch="amd64"
	fi
	local download_filename="${TOOL_NAME}${version}.${kernel}-${arch}.tar.gz"
	local url="$GH_REPO/releases/download/v${version}/${download_filename}"
	echo "* Downloading $TOOL_NAME release $version..."
	curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

# As of 2024-10-16, TinyGo does not publish hashes for their releases, nor do
# they sign them.  The check_sha256 method checks downloaded files against a
# file (SHA256SUMS) of known hashes.  Consider it the trust-on-first-use of
# downloading.
check_sha256() {
	local plugin_dir="$1"
	local file_path="$2"
	local file_dir
	local file_name
	local sha256sum_path
	local line_count
	local pwd

	# Build an SHA256SUMS file for the one file we have downloaded.
	file_dir=$(dirname "${file_path}")
	file_name=$(basename "${file_path}")
	sha256sum_path=$(mktemp)
	grep "${file_name}" "${plugin_dir}/SHA256SUMS" >"${sha256sum_path}"
	line_count=$(wc -l "${sha256sum_path}" | awk '{print $1}')
	if [ "$line_count" -ne 1 ]; then
		rm "${sha256sum_path}"
		fail "Unable to find exactly one SHA-256 value for file ${file_name}"
	fi

	# Check the SHA-256 value.
	local sha256_rc

	pwd=$(pwd)
	cd "${file_dir}"
	if command -v sha256sum >/dev/null 2>/dev/null; then
		sha256sum --check "${sha256sum_path}"
		sha256_rc=$?
	elif command -v shasum >/dev/null 2>/dev/null; then
		shasum --algorithm 256 --check "${sha256sum_path}"
		sha256_rc=$?
	fi
	cd "${pwd}"

	if [ $sha256_rc -ne 0 ]; then
		rm "${sha256sum_path}"
		fail "Failed to verify the SHA-256 value for the file ${file_name}"
	fi
	rm "${sha256sum_path}"
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
