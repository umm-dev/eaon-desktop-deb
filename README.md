# Eaon

Eaon is a desktop chat client for macOS and Debian-based Linux. Talk to
[Eaon](https://eaon.dev)'s hosted models, bring your own API key for any
OpenAI-compatible/Anthropic/Gemini provider, or run models entirely on-device
with Ollama, llama.cpp, or MLX — all from the same app, with no account
required for the local-only path.

The original SwiftUI app is retained for macOS. The `eaon-tauri` app provides
the matching cross-platform interface and feature set for Debian and other
Linux distributions supported by Tauri.

## Highlights

- **Multi-provider chat** — Eaon's hosted catalog, BYOK cloud providers, and
  local models, with automatic routing based on which model you pick.
- **Local models** — discover and run GGUF/MLX models via Ollama, llama.cpp,
  or Apple's MLX framework, with live hardware-fit checks before you download
  anything.
- **Plugins** — connect real accounts (GitHub, Slack, Notion, Linear, and
  more) and let a model call their tools directly, with native tool-calling
  and a confirmation step before anything runs.
- **Image generation** — over an API or a local server (Automatic1111-style,
  or an Ollama-served diffusion model).
- **Computer Control** — optional, off by default — let a model organize
  files or run shell commands on this Mac, with safety rules and
  confirmation built in.
- **Local API Server** — run Eaon itself as a local, OpenAI-compatible
  server other tools can point at.
- **Memory** — Eaon can learn durable facts about you across conversations,
  entirely on-device.

## Quick start

Clone this Debian/Linux fork:

```sh
git clone https://github.com/umm-dev/eaon-desktop-deb.git
cd eaon-desktop-deb
```

### Debian and Ubuntu

Build and install the Linux desktop app from `eaon-tauri`:

```sh
cd eaon-tauri
npm ci
npm run package:deb
sudo apt install ./src-tauri/target/release/bundle/deb/Eaon_*.deb
eaon
```

See [the Debian build guide](eaon-tauri/DEBIAN.md) for the required system
dependencies, validation commands, removal, and release-artifact details.

### macOS

Run the native development launcher:

```sh
./run.sh
```

The launcher builds Eaon and starts it as a detached macOS app process.

## Building

### macOS

Requires Xcode 15+ / Swift 5.9+ and macOS 14+.

```sh
swift build
./run.sh            # builds and launches for local development
```

To produce a distributable universal build (arm64 + x86_64), see
`build-installer.sh` and `RELEASING-UPDATES.md`.

### Debian and Ubuntu

The packaged Linux app is built from `eaon-tauri`. Follow
[the Debian build guide](eaon-tauri/DEBIAN.md), which covers the required
WebKitGTK/Tauri dependencies and creates an installable `.deb` package.

## Contributors

Sanscreates,
Mincoffical, and
Tanzim

## Contributing

**Contributions are genuinely welcome and made as easy as possible.** No
account, no CLA to sign, no external dependencies to wrangle:

```sh
git clone https://github.com/umm-dev/eaon-desktop-deb.git
cd eaon-desktop-deb
```

For macOS development, run `swift build && ./run.sh`. For Debian and Ubuntu,
follow [the Linux build guide](eaon-tauri/DEBIAN.md).

Repository integration policy:

- Merge changes that are ready and validated into `main`.
- Merge work that needs further integration or testing into `beta` first.

Open an issue, pick up a
[`good first issue`](https://github.com/umm-dev/eaon-desktop-deb/labels/good%20first%20issue),
or just send a PR — see [CONTRIBUTING.md](CONTRIBUTING.md) for the (short)
details and the one-line sign-off we use instead of a contributor agreement.

## License

Eaon is [GNU GPL v3.0](LICENSE.md). You're free to use, study, modify, and
redistribute it. Any modified version you distribute must also be GPLv3,
with source available, keeping the existing copyright notices. Fork away.
