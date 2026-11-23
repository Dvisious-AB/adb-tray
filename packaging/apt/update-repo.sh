#!/usr/bin/env bash
# Add .deb files to an apt repository in a directory (the gh-pages branch) and sign it.
#
#   packaging/apt/update-repo.sh REPO_DIR PACKAGE.deb...
#
# Every package ever added stays in pool/, so older versions can still be installed. The signing key is
# the GnuPG secret key with the fingerprint in APT_GPG_FINGERPRINT (or the only secret key there is);
# APT_GPG_PASSPHRASE is used when it is set. Needs apt-ftparchive (apt-utils) and gpg.
set -euo pipefail

REPO="${1:?usage: update-repo.sh REPO_DIR PACKAGE.deb...}"
shift
SUITE=stable
COMPONENT=main
ARCHITECTURES=(amd64 arm64 armhf i386)

KEY="${APT_GPG_FINGERPRINT:-$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')}"
[[ -n "$KEY" ]] || { echo "No GnuPG secret key to sign with" >&2; exit 1; }
SIGN=(gpg --batch --yes --local-user "$KEY" --digest-algo SHA512)
[[ -n "${APT_GPG_PASSPHRASE:-}" ]] && SIGN+=(--pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE")

POOL="pool/$COMPONENT/a/adb-tray"
mkdir -p "$REPO/$POOL"
for deb in "$@"; do
    install -m 644 "$deb" "$REPO/$POOL/"
done

cd "$REPO"
for arch in "${ARCHITECTURES[@]}"; do
    dir="dists/$SUITE/$COMPONENT/binary-$arch"
    mkdir -p "$dir"
    # --arch keeps Architecture: all packages in every list.
    apt-ftparchive --arch "$arch" packages pool > "$dir/Packages"
    gzip -9nkf "$dir/Packages"
done

apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="Appninjas" \
    -o APT::FTPArchive::Release::Label="Appninjas" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Components="$COMPONENT" \
    -o APT::FTPArchive::Release::Architectures="${ARCHITECTURES[*]}" \
    -o APT::FTPArchive::Release::Description="Appninjas packages" \
    release "dists/$SUITE" > "dists/$SUITE/Release.tmp"
mv "dists/$SUITE/Release.tmp" "dists/$SUITE/Release"

"${SIGN[@]}" --clearsign --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"
"${SIGN[@]}" --armor --detach-sign --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"

# The public key, binary for /etc/apt/keyrings and armored for reading.
gpg --batch --yes --export "$KEY" > appninjas-archive-keyring.gpg
gpg --batch --yes --armor --export "$KEY" > appninjas-archive-keyring.asc
# GitHub Pages must serve the files as they are, without Jekyll.
touch .nojekyll
echo "Repository updated: $(find pool -name '*.deb' | wc -l | tr -d ' ') package(s) in $REPO/pool"
