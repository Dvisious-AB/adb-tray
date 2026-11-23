# The apt repository

Linux users install Appninjas ADB from a signed apt repository on the `gh-pages` branch, served by
GitHub Pages at <https://dvisious-ab.github.io/adb-tray/>. `.github/workflows/release.yml` updates
it whenever a `v*` tag is pushed: it builds the package (`packaging/debian/build-deb.sh`), adds it to
`pool/` next to every earlier version, regenerates `dists/stable` for amd64, arm64, armhf and i386
(the package is `Architecture: all`) and signs `InRelease` and `Release.gpg`
(`packaging/apt/update-repo.sh`).

## One-time setup

Done once by a maintainer with admin rights on the repository. The workflow never creates keys.

1. Create the signing key. RSA 4096 is read by every apt version in use. Choose a passphrase when
   asked, or press Enter for none:

   ```bash
   gpg --quick-gen-key "Appninjas apt repository" rsa4096 sign 5y
   ```

2. Store it as repository secrets:

   ```bash
   FPR="$(gpg --list-secret-keys --with-colons "Appninjas apt repository" | awk -F: '/^fpr:/ { print $10; exit }')"
   gpg --armor --export-secret-keys "$FPR" | gh secret set APT_GPG_PRIVATE_KEY -R Dvisious-AB/adb-tray
   gh secret set APT_GPG_PASSPHRASE -R Dvisious-AB/adb-tray   # only if the key has a passphrase
   ```

3. Keep a copy of the secret key somewhere safe and offline. If it is lost, every user has to fetch a
   new public key:

   ```bash
   gpg --armor --export-secret-keys "$FPR" > appninjas-apt-signing-key.asc
   ```

4. After the first release has created the `gh-pages` branch, turn on GitHub Pages for it:

   ```bash
   gh api -X POST repos/Dvisious-AB/adb-tray/pages -f "source[branch]=gh-pages" -f "source[path]=/"
   ```

## A release

1. Set the new version in `VERSION` and merge that to `main`.
2. Tag the merge commit and push the tag: `git tag v1.0.0 && git push origin v1.0.0`.
   The workflow fails if the tag and `VERSION` differ.
3. The job summary shows the `url` and `sha256` for the Homebrew formula in `Dvisious-AB/homebrew-tap`.

## Testing locally

`update-repo.sh` signs with whichever secret key GnuPG has, so a test can use a throwaway keyring:

```bash
export GNUPGHOME="$(mktemp -d)"
gpg --batch --passphrase '' --quick-gen-key "test" ed25519 sign never
packaging/apt/update-repo.sh /tmp/repo "$(packaging/debian/build-deb.sh --output /tmp/dist)"
```
