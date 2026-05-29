# Changelog

All notable changes to `luci-app-twofa` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project loosely follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the OpenWrt convention of `<MAJOR.MINOR>-r<PKG_RELEASE>` (so `1.0-r15`
means upstream version 1.0, package iteration 15).

When adding a new release, create a `## [1.0-rN] - YYYY-MM-DD` section at the
top (above the previous one). The GitHub Actions workflow extracts that exact
section verbatim and pastes it as the release body.

---

## [Unreleased]

## [1.0-r15] - 2026-05-29

### Changed
- **Packaging split**. The main `luci-app-twofa` package now ships English
  UI only; install `luci-i18n-twofa-zh-cn` separately for 简体中文. This
  matches the convention of every other LuCI app and lets users opt out of
  the translation overhead.
- Github Actions now produces **four ipks per release** (main + i18n, each
  for `x86_64` and `aarch64`) with the architecture embedded in the
  filename, so users can pick the right asset without guessing.
- Tagged `v*` releases are now the canonical channel; a `latest`
  pre-release is kept as a rolling channel for the freshest `main` build.

### Added
- `CHANGELOG.md` (this file). Tagged releases pull their notes from here.

## [1.0-r14] - 2026-05-29

### Fixed
- **Critical, TOTP correctness**: every verification was permanently
  rejected on ImmortalWrt's patched Lua 5.1 (`(double int32)`) runtime.
  Root cause: the SHA-1 padding byte was written as `"\x80"`, but the `\x`
  hex escape is a Lua 5.2+ feature. The patched 5.1 silently drops the
  backslash, so the SHA-1 input was fed the 3-character literal `"x80"`
  instead of one byte `0x80`. Every hash, every HMAC and every TOTP code
  was therefore wrong-but-consistent. Replaced with `string.char(0x80)`
  and added a top-of-file rule banning `\xNN` escapes anywhere in the
  codebase.

## [1.0-r13] - 2026-05-28

### Added
- Defensive `uint32()` wrapper around every `band/bor/bxor` call. LuaBitOp
  (Mike Pall) returns signed int32 for high-bit-set inputs; nixio.bit on
  Lua 5.3+ returns unsigned. The wrapper costs one comparison and makes
  the SHA-1 implementation portable across both conventions.

## [1.0-r12] - 2026-05-28

### Fixed
- `uci-defaults/10-luci-app-twofa` previously called
  `openssl rand -base32 20`. **There is no `-base32` flag** in openssl
  (`-hex` and `-base64` only); on routers with `openssl-util` installed
  this silently produced an empty secret, which was then committed as
  `secret=""` into UCI and triggered hours of "code always wrong" reports.
  Switched to `tr -dc 'A-Z2-7' </dev/urandom | head -c 16` which works
  on every busybox-based OpenWrt build.
- The `awk` fallback for the same path was missing `srand()`, so absent
  openssl-util it would emit the **same** 16-character secret on every
  boot. Catastrophic if it had ever shipped that way.

## [1.0-r11] - 2026-05-28

### Added
- Pure-Lua HMAC-SHA1 fallback. The default `libnixio` variant on
  ImmortalWrt is compiled without OpenSSL, so `nixio.crypto.hmac` is
  `nil` and any call to it crashed verification with
  `attempt to index field 'crypto' (a nil value)`. The fallback runs in
  ~1 ms per HMAC and ships with this package, so `libnixio-openssl` is
  no longer required.

### Changed
- rpcd plugin now logs the active HMAC backend (`nixio.crypto` vs
  `pure-lua`) on every verify call, so future regressions can be
  diagnosed from `logread -e luci-app-twofa` alone.

## [1.0-r10] - 2026-05-28

### Fixed
- `base32_decode()` raised `arithmetic overflow` on Lua 5.3+ (which
  ImmortalWrt 24.x ships) once the accumulator buffer exceeded 2^31 -
  roughly the 13th base32 character. Rewrote the decoder to mask the
  accumulator after every emitted byte, keeping it inside 12 bits so no
  bit operation ever sees a value > 2^32.

## [1.0-r9] - 2026-05-28

### Fixed
- Session downgrade was too aggressive: it revoked **every** non-twofa
  ACL on the session, including `ubus.session.access`. LuCI polls
  `session.access` as a heartbeat; when that fails, the frontend pops
  its own "session expired" modal *in front of* the 2FA dialog, so the
  user could never get past it. The downgrade now preserves `ubus.session.*`
  explicitly.

## [1.0-r6 - r8] - 2026-05-28

### Fixed
- rpcd plugin file name vs ubus object name mismatch. rpcd registers
  each `/usr/libexec/rpcd/<basename>` script as an ubus object using the
  **basename verbatim**, so a file named `luci-app-twofa` becomes
  `luci-app-twofa` (not `luci.twofa`). Renamed every reference (ACL JSON,
  preload JS, plugin's own self-guard).
- Main package's `postinst` now restarts `rpcd` and clears
  `/tmp/luci-{index,module}cache` so newly installed ACLs and plugins
  take effect without a manual `/etc/init.d/rpcd restart`.

## [1.0-r5] - 2026-05-27

### Added
- Initial public release. Implements TOTP-based 2FA for LuCI:
  - rpcd plugin (`/usr/libexec/rpcd/luci-app-twofa`) enforcing 2FA at
    the ACL layer by revoking non-twofa ACLs on un-validated sessions.
  - Client-side preload (`htdocs/luci-static/resources/preload/twofa.js`)
    that blocks the UI behind a modal until verification.
  - CBI settings page at **Services → 2FA Settings** with QR code,
    secret display and regeneration toggle.
  - GitHub Actions matrix build for `x86_64` and `aarch64`.

[Unreleased]: https://github.com/OWNER/luci-app-twofa/compare/v1.0-r15...HEAD
[1.0-r15]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r15
[1.0-r14]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r14
[1.0-r13]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r13
[1.0-r12]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r12
[1.0-r11]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r11
[1.0-r10]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r10
[1.0-r9]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r9
[1.0-r6 - r8]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r8
[1.0-r5]: https://github.com/OWNER/luci-app-twofa/releases/tag/v1.0-r5
