# Packaging & distribution

How to turn a build into something you can install and share. For product scope
see [SPEC.md](SPEC.md); for everyday build/run see [README.md](README.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

## TL;DR

```bash
scripts/package.sh              # Release build → dist/DeepFocusTracker-<version>.zip
scripts/package.sh --install    # also copy the app into /Applications
```

The zip is a ready-to-share copy of `DeepFocusTracker.app`. It runs immediately
on **this** Mac; getting it onto **other** Macs needs a one-time approval step
([Option 2](#option-2--share-the-zip-ad-hoc)) or, for a clean download
experience, notarization ([Option 3](#option-3--developer-id--notarization)).

## What a build is today

The project is **ad-hoc signed** ("Sign to Run Locally") — no Apple Developer
account required. A Release build (verified with `codesign` / `lipo` / `spctl`):

| Property | Value |
|---|---|
| Signature | **Ad-hoc** (`Signature=adhoc`, no Team ID) |
| Architecture | **Universal** — `x86_64` + `arm64` (Intel *and* Apple Silicon) |
| Minimum OS | macOS 15.0 |
| Special permissions | **None** (no Accessibility / Screen Recording / network) |
| Gatekeeper verdict | **Rejected** until notarized (`spctl` rejects it) |

An ad-hoc signature is tied to no developer identity, so macOS trusts it only
where it's already "known" — the machine that built it. That single fact drives
every option below.

## Choosing a distribution path

| Option | Cost | Runs on… | Effort |
|---|---|---|---|
| [1. Local install](#option-1--local-install) | Free | This Mac | trivial |
| [2. Share the zip (ad-hoc)](#option-2--share-the-zip-ad-hoc) | Free | Other Macs, after a one-time approval | trivial |
| [3. Developer ID + notarization](#option-3--developer-id--notarization) | $99/yr | Any Mac, double-click | moderate |
| [4. Mac App Store](#option-4--mac-app-store) | $99/yr | Any Mac, auto-update | high |

### Option 1 — local install

For running it yourself, day to day:

```bash
scripts/package.sh --install
```

Builds Release and copies the app to `/Applications/DeepFocusTracker.app`,
replacing any older copy. A locally built app is never quarantined and your Mac
trusts its own ad-hoc signature, so it just launches — look for the 🧠 menu-bar
icon (no Dock icon). Natural pairing: launch-at-login (M4), so it starts with
your session.

### Option 2 — share the zip (ad-hoc)

`dist/DeepFocusTracker-<version>.zip` is a `ditto` archive (bundle-safe — a plain
`zip` can corrupt an `.app`). You can hand it to someone, but their Mac blocks it
on first launch because it isn't notarized. macOS 15 (Sequoia) removed the old
right-click → Open shortcut, so the one-time approval is now:

1. Double-click → "cannot verify it's free of malware" → **Done**.
2. **System Settings → Privacy & Security** → scroll down → **Open Anyway**.
3. Confirm with Touch ID / password. It launches normally from then on.

Or, for a technical recipient, one command clears the quarantine flag:

```bash
xattr -dr com.apple.quarantine /path/to/DeepFocusTracker.app
```

Fine for a handful of trusted people; not something to post for public download.
Recipient requirements: macOS 15+ on any Mac (the binary is universal, so Intel
and Apple Silicon both work).

### Option 3 — Developer ID + notarization

The standard way to distribute a Mac app **outside** the App Store with no
Gatekeeper friction:

1. Join the Apple Developer Program ($99/yr).
2. Sign with a **Developer ID Application** certificate (set `DEVELOPMENT_TEAM`
   and `CODE_SIGN_IDENTITY`, and enable the Hardened Runtime).
3. **Notarize** — upload to Apple with `notarytool`; Apple scans for malware and
   issues a ticket.
4. **Staple** the ticket to the app (`stapler`), then zip or wrap it in a DMG.

The result double-clicks cleanly on any Mac. Xcode's **Product → Archive →
Distribute App → Developer ID** automates most of this. When we go here, the
script gains a companion `scripts/notarize.sh` (see [Future work](#future-work)).

### Option 4 — Mac App Store

Also viable with **no redesign** — the app uses only `NSWorkspace` frontmost-app
APIs, which are sandbox-safe. It would require:

- Enabling **App Sandbox** and re-verifying the SwiftData store under the sandbox
  container (the store moves into the app's container).
- App Store Connect setup and **review**.

Heavy for a personal tool, but the door is open. (The App Store also handles
updates for you.)

## `scripts/package.sh` reference

| Flag | Effect |
|---|---|
| _(none)_ | Release build → `dist/DeepFocusTracker-<version>.zip` |
| `--install` | Also copy the app into `/Applications` (replaces any older copy) |
| `--open` | Reveal the finished zip in Finder |
| `--help` | Usage |

- Builds with `xcodebuild -configuration Release` into `DerivedData/` (gitignored).
- Names the zip from the app's `CFBundleShortVersionString` (currently `1.0`, from
  `MARKETING_VERSION`) so shared files are traceable.
- Output lives in `dist/`, which is gitignored — build artifacts don't belong in
  the repo.

## Future work

- **`scripts/notarize.sh`** — Developer ID sign + `notarytool` submit + staple,
  once there's a paid account and a reason to distribute widely.
- **DMG packaging** — a drag-to-`/Applications` installer window for Options 3/4.
- **Versioning** — bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` per
  release so zip names and the About box stay in step.
