# HM Tech Bootstrap

`hm-tech-bootstrap` builds a signed macOS installer package for provisioning a
standard developer workstation through an MDM solution.

The package installs a LaunchDaemon that waits for both a logged-in console
user and Homebrew, then applies an idempotent Brewfile. It is designed to be
deployed independently from the official Homebrew installer package, in any
order.

## Managed software

- [rig](https://github.com/r-lib/rig) (`r-rig`), with R 4.6.1 pinned as the
  default CRAN installation
- RStudio
- Visual Studio Code
- Docker Desktop
- Cyberduck

Project-specific R dependencies are intentionally not installed globally. R
projects should use [`renv`](https://rstudio.github.io/renv/) to make their
package environment reproducible.

## How it works

The package installs:

- `/Library/Hypermynds/HMTech/Brewfile`
- `/Library/Hypermynds/HMTech/bootstrap.sh`
- `/Library/LaunchDaemons/com.hypermynds.hmtech.bootstrap.plist`

The LaunchDaemon runs every five minutes until:

1. a console user is logged in;
2. Homebrew is available;
3. `brew bundle` and the R setup complete successfully.

Homebrew commands run as the console user through `brew as-console-user`, while
system-level R operations run through `rig`. Successful completion creates
`/Library/Hypermynds/HMTech/.completed`; later runs exit without changing the
machine.

Logs are written to:

```text
/var/log/hypermynds-hmtech-bootstrap.log
```

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac supported by Homebrew
- the official Homebrew installer package deployed separately
- a local administrator logged in during the initial bootstrap
- a macOS Installer signing identity available on the build Mac
- the corresponding public certificate trusted by the target devices

## Build

The signing identity expected by `build.sh` is:

```text
Installer Certificate (Hypermynds)
```

Build version `1.0.0` with:

```bash
./build.sh 1.0.0
```

The signed package is written to:

```text
dist/hm-tech-bootstrap-1.0.0.pkg
```

`build.sh` verifies the package signature and prints its SHA-256 checksum.

## Release

Releases are created locally so that the private Installer signing key never
needs to leave the build Mac.

Install and authenticate the GitHub CLI once:

```bash
brew install gh
gh auth login
```

Commit and push all source changes, then create a draft release:

```bash
./release.sh 1.0.0
```

The script verifies the repository state, builds and signs the package, creates
a SHA-256 checksum file, and uploads both assets to a GitHub draft release.
After reviewing the assets and generated notes, publish it with:

```bash
gh release edit v1.0.0 --draft=false --latest
```

To publish immediately instead of creating a draft:

```bash
./release.sh 1.0.0 --publish
```

Published packages have stable, versioned URLs such as:

```text
https://github.com/Hypermynds/hm-tech-bootstrap/releases/download/v1.0.0/hm-tech-bootstrap-1.0.0.pkg
```

Use the package version, identifier `com.hypermynds.hmtech.bootstrap`, direct
asset URL, and SHA-256 checksum when registering the package with an MDM.

## Verification

Follow the bootstrap log:

```bash
sudo tail -f /var/log/hypermynds-hmtech-bootstrap.log
```

Verify the installed software:

```bash
rig list
R --version | head -1
test -d "/Applications/RStudio.app" && echo "RStudio OK"
test -d "/Applications/Visual Studio Code.app" && echo "VS Code OK"
test -d "/Applications/Docker.app" && echo "Docker OK"
test -d "/Applications/Cyberduck.app" && echo "Cyberduck OK"
```

Verify the installer receipt:

```bash
pkgutil --pkg-info com.hypermynds.hmtech.bootstrap
```

## Updating the baseline

1. Update `payload/Library/Hypermynds/HMTech/Brewfile` or `R_VERSION` in
   `bootstrap.sh`.
2. Test the change on a pilot Mac.
3. Commit and push the source changes.
4. Create a new semantic version with `release.sh`.
5. Register and deploy the new package version through the MDM.

`brew bundle --no-upgrade` installs missing software without upgrading existing
applications. New R versions are intentional, reviewed changes rather than a
moving `release` target.

## Security

Never commit private keys, PKCS#12 files, signing passwords, or unencrypted
certificate exports. Release assets are public when the repository is public.
Only source code and signed installer packages intended for distribution should
be published here.
