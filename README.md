# HM Tech Bootstrap

`hm-tech-bootstrap` builds a signed macOS installer package for provisioning a
standard developer workstation through an MDM solution.

The package installs a LaunchDaemon that waits for both a logged-in console
user and Homebrew, then ensures the software declared in the Brewfile is
present. The official Homebrew installer package can be deployed independently,
in either order.

## Managed software

- RStudio
- Visual Studio Code
- Docker Desktop
- Cyberduck

The R runtime is intentionally outside this bootstrap. It should be deployed as
a separate, versioned package through the MDM using the official signed CRAN
installer. Project-specific R dependencies are not installed globally; R
projects should use [`renv`](https://rstudio.github.io/renv/) to make their
package environment reproducible.

## Existing installations

The bootstrap is conservative and does not upgrade, uninstall or forcibly
replace existing software:

- formulae and casks already managed by Homebrew are left unchanged;
- missing software is installed;
- an existing application is adopted only when Homebrew verifies that its
  artifacts are identical to the current cask;
- an existing application that cannot be safely adopted is left untouched.

This allows the same package to provision new Macs and to onboard existing
developer workstations without overwriting their applications.

## How it works

The package installs:

- `/Library/Hypermynds/HMTech/Brewfile`
- `/Library/Hypermynds/HMTech/VERSION`
- `/Library/Hypermynds/HMTech/bootstrap.sh`
- `/Library/LaunchDaemons/com.hypermynds.hmtech.bootstrap.plist`

The LaunchDaemon runs every five minutes until a console user is logged in,
Homebrew is available and all required installations complete. Homebrew
commands run as the console user through `brew as-console-user`.

Successful completion creates a version-specific marker:

```text
/Library/Hypermynds/HMTech/.completed-X.Y.Z
```

Reinstalling the same package version is a no-op. Deploying a newer package
version runs the updated baseline once.

Logs are written to:

```text
/var/log/hypermynds-hmtech-bootstrap.log
```

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac supported by Homebrew
- the official Homebrew installer package deployed separately
- network access to the Homebrew cask sources
- a local administrator logged in during the initial bootstrap
- a macOS Installer signing identity available on the build Mac
- the corresponding public certificate trusted by the target devices

## Build

The signing identity expected by `build.sh` is:

```text
Installer Certificate (Hypermynds)
```

Build a package with a semantic version:

```bash
./build.sh 1.0.1
```

The script temporarily embeds the requested version in the package payload,
then restores the source `VERSION` file. The signed package is written to:

```text
dist/hm-tech-bootstrap-1.0.1.pkg
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
./release.sh 1.0.1
```

The script checks the repository state, builds and signs the package, creates a
SHA-256 checksum file, and uploads both assets. Publish the reviewed draft with:

```bash
gh release edit v1.0.1 --draft=false --latest
```

To publish immediately:

```bash
./release.sh 1.0.1 --publish
```

Published packages have stable, versioned URLs such as:

```text
https://github.com/Hypermynds/hm-tech-bootstrap/releases/download/v1.0.1/hm-tech-bootstrap-1.0.1.pkg
```

Use the package version, identifier `com.hypermynds.hmtech.bootstrap`, direct
asset URL, and SHA-256 checksum when registering the package with an MDM.

## Verification

Follow the bootstrap log:

```bash
sudo tail -f /var/log/hypermynds-hmtech-bootstrap.log
```

Verify the completion marker and installed software:

```bash
cat /Library/Hypermynds/HMTech/.completed-1.0.1
brew list --cask rstudio visual-studio-code docker-desktop cyberduck
```

The independently managed R runtime can be verified with:

```bash
R --version | head -1
```

Verify the installer receipt:

```bash
pkgutil --pkg-info com.hypermynds.hmtech.bootstrap
```

## Updating the baseline

1. Update `payload/Library/Hypermynds/HMTech/Brewfile` and, for any new cask,
   add its conservative artifact-detection rule to `bootstrap.sh`.
2. Test the change on a pilot Mac.
3. Commit and push the source changes.
4. Create a new semantic version with `release.sh`.
5. Register and deploy the new package version through the MDM.

## Security

Never commit private keys, PKCS#12 files, signing passwords, or unencrypted
certificate exports. Release assets are public when the repository is public.
Only source code and signed installer packages intended for distribution should
be published here.
