# Eaon for Debian

The Linux app is the Tauri rebuild in this directory. It uses the same Eaon
interface and feature set as the macOS client while replacing macOS-only
system integrations with their Linux-safe equivalents.

## Build a Debian package

On Debian 13 / Ubuntu 24.04 or a newer compatible release, install the build
dependencies once:

```sh
sudo apt-get update
sudo apt-get install -y \
  build-essential file libayatana-appindicator3-dev libdbus-1-dev \
  librsvg2-dev libwebkit2gtk-4.1-dev libxdo-dev patchelf pkg-config
```

Then build the package from this directory:

```sh
npm ci
npm run check
cargo test --manifest-path src-tauri/Cargo.toml
npm run package:deb
```

The finished package is written to
`src-tauri/target/release/bundle/deb/`. Tauri derives its runtime library
dependencies from the linked binary, so the package installs the matching
WebKitGTK/GTK libraries for the distribution it was built on.

## Install and remove

```sh
sudo apt install ./src-tauri/target/release/bundle/deb/Eaon_*.deb
eaon
sudo apt remove eaon
```

The package creates the normal desktop-menu entry and installs the application
under `/usr/bin/eaon`. User data remains in Eaon's per-user application-data
directory and is not removed by `apt remove`.

## Release artifact

The repository's release workflow builds a `.deb` on Ubuntu as well as the
other supported platform installers. For Debian-oriented releases, attach the
`.deb` from `src-tauri/target/release/bundle/deb/`.
