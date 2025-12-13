#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq git gnused nix-prefetch-github rustup python3 nix prefetch-yarn-deps coreutils nix-prefetch-git

set -euo pipefail

export RUSTUP_HOME=$(mktemp -d)
export CARGO_HOME=$(mktemp -d)
trap 'rm -rf "$RUSTUP_HOME" "$CARGO_HOME"' EXIT

# Install nightly toolchain
rustup toolchain install nightly
export PATH="$CARGO_HOME/bin:$PATH"

# Paths
nixpkgs="$(git rev-parse --show-toplevel)"
pkgdir="$nixpkgs/pkgs/by-name/sa/sapling"
pkgfile="$pkgdir/package.nix"
latest_json="$(curl -s https://api.github.com/repos/facebook/sapling/releases/latest)"
latest_tag="$(jq -r .tag_name <<<"$latest_json")"
tarball_url="$(jq -r .tarball_url <<<"$latest_json")"

# Prefetch source tarball and get unpacked path
mapfile -t tarball_lines < <(nix-prefetch-url --print-path --unpack "$tarball_url")
source_dir="${tarball_lines[1]}"

# Update Cargo.lock by running cargo fetch in a writable copy of the source
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cp -R "$source_dir" "$tmpdir/src"
chmod -R u+w "$tmpdir/src"
cargo +nightly fetch --manifest-path "$tmpdir/src/eden/scm/Cargo.toml"
cp "$tmpdir/src/eden/scm/Cargo.lock" "$pkgdir/Cargo.lock"

# Parse Cargo.lock and prefetch git sources
cargo_output_hashes="$(python3 -c '
import json
import subprocess
import sys
import tomllib

cargo_lock_path = sys.argv[1]

allowed_packages = {
    "abomonation",
    "cloned",
    "fb303_core",
    "fbthrift",
    "serde_bser",
    "watchman_client"
}

with open(cargo_lock_path, "rb") as f:
    lock = tomllib.load(f)

for pkg in lock.get("package", []):
    source = pkg.get("source", "")
    if source.startswith("git+"):
        name = pkg["name"]
        if name not in allowed_packages:
            continue
        version = pkg["version"]
        # source format: git+https://url?rev#hash
        parts = source.split("#")
        if len(parts) == 2:
            rev = parts[1]
            url_part = parts[0][4:] # remove git+
            if "?" in url_part:
                url = url_part.split("?")[0]
            else:
                url = url_part
            out = subprocess.check_output(
                ["nix-prefetch-git", "--url", url, "--rev", rev, "--quiet"],
                text=True
            )
            data = json.loads(out)
            hash_val = data["hash"]
            print(f"      \"{name}-{version}\" = \"{hash_val}\";")
' "$pkgdir/Cargo.lock")"

# Update the outputHashes
# First clear existing hashes
sed -i '/outputHashes = {/,/};/ {
  /outputHashes = {/n
  /};/!d
}' "$pkgfile"

# Then insert new hashes
echo "$cargo_output_hashes" > "$tmpdir/hashes.txt"
sed -i '/outputHashes = {/r '"$tmpdir/hashes.txt" "$pkgfile"

# Compute versionHash (first 8 bytes of SHA1(version) as big-endian u64)
version_hash="$(python3 -c '
import hashlib
import struct
import sys

s = sys.argv[1].encode("ascii")
print(struct.unpack(">Q", hashlib.sha1(s).digest()[:8])[0])
' "$latest_tag")"
sed -i -e 's|^  version = "[^"]*";|  version = "'"$latest_tag"'";|' "$pkgfile"
sed -i -e 's|^  versionHash = "[^"]*";|  versionHash = "'"$version_hash"'";|' "$pkgfile"

# Prefetch source hash for fetchFromGitHub
src_hash="$(nix-prefetch-github facebook sapling --rev "$latest_tag" | jq -r '.hash')"

# Update the fetchFromGitHub src block's hash
sed -i -e '/src = fetchFromGitHub {/,/}/{s|hash = "[^"]*";|hash = "'"$src_hash"'";|}' "$pkgfile"

# Compute yarn offline cache hash without building
yarn_lock="$source_dir/addons/yarn.lock"
yarn_hash_raw="$(prefetch-yarn-deps "$yarn_lock")"
yarn_hash_sri="$(nix hash convert --hash-algo sha256 --to sri "$yarn_hash_raw")"
sed -i -e '/yarnOfflineCache = fetchYarnDeps {/,/};/{s|sha256 = "[^"]*";|sha256 = "'"$yarn_hash_sri"'";|}' "$pkgfile"
