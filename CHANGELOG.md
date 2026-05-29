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

## [1.0-r16] - 2026-05-29

### Security

This release closes a full sweep of weaknesses surfaced by an internal
audit. Anyone running r15 or earlier should upgrade as soon as possible.

- **Authentication bypass (critical, CVSS-equivalent ~9.1).** The rpcd
  plugin's ACL downgrade was triggered lazily by the browser preload's
  `status()` poll. Non-browser clients (curl, Python, raw `ubus` over
  unix socket from ssh) never invoked `status()` and kept full ACLs
  indefinitely after authenticating with the password. A new persistent
  daemon (`/usr/sbin/luci-app-twofa-guardd`, procd-managed via
  `/etc/init.d/luci-app-twofa-guard`) now polls `ubus call session list`
  every second and forces a downgrade on every session, closing this gap
  to a worst-case ~1 s window regardless of client type. Note: ssh /
  dropbear login is explicitly out of scope; anyone with the root ssh
  credentials can already do anything.
- **Brute force (critical).** `verify()` accepted unlimited attempts. A
  per-session attempt counter is now enforced: 5 failures triggers a
  60 s lockout, doubling each engagement up to 30 min. Counters survive
  downgrade so an attacker cannot reset by re-calling `status()`.
- **Replay (high).** The previous 90 s acceptance window (slots
  -1/0/+1) was reusable: a captured valid token could be replayed up
  to two extra times. `verify_window()` now returns the matched counter
  and the rpcd plugin persists the last accepted counter per session;
  any new attempt with counter ≤ last is rejected as `totp_replayed`,
  implementing RFC 6238 §5.2.
- **Weak fallback RNG (high).** The CBI's `generate_secret()` had a
  `math.random` fallback seeded by `os.time() + os.clock() * 1e6`,
  giving a brute-forceable secret if `/dev/urandom` was unavailable.
  Removed. Secret generation now lives exclusively in
  `/usr/sbin/twofa-genkey`, which refuses to fall back to anything
  other than `/dev/urandom`.
- **Timing oracle (medium).** Token comparison used Lua string `==`
  (byte-by-byte, short-circuit) plus short-circuit `or` across the
  three windows, leaking through wall-clock timing which slot matched.
  `verify_window()` now computes every candidate in fixed order and
  uses a constant-time byte compare.
- **Secret at rest (medium).** The TOTP secret used to live in
  `/etc/config/twofa` (default mode 0644, included in sysupgrade
  backups). It is now stored in `/etc/twofa.secret` with mode 0600,
  written atomically via `mktemp`+`chmod`+`mv` so there is no
  world-readable window. The uci-defaults script migrates pre-r16
  installs automatically.
- **Session state token leakage (medium).** Session records in
  `/var/run/luci-twofa-sessions.json` used the raw rpc session id as
  the key, meaning a file leak yielded live bearer tokens. Records are
  now keyed by SHA-256 of the SID; the daemon can still find the right
  record but a stolen file is useless.
- **State file write race (medium).** `fs.writefile()` created with
  the default umask (typically 0644) before `chmod 0600` ran. The new
  `write_state()` does `mktemp` + `chmod 0600` + write + atomic
  `os.rename`, eliminating the window.
- **Incomplete ACL downgrade (medium).** The previous `KEEP_SCOPES`
  / `PRESERVE_UBUS_OBJ` model touched only `ubus`/`uci`/`file` and
  preserved every method on the `session` ubus object (including
  `grant`/`destroy`/`create`). Replaced with an explicit
  `(scope, object, method)` allow list that pins `session` to
  `access()` only and revokes everything else regardless of scope.
- **Debug helper leaked secret material (low).** `totp.debug_generate`
  printed the raw key, HMAC, and final code to stdout. Removed from
  the module surface; any caller wiring stdout into an HTTP response
  would have leaked the shared secret.
- **Shell argument injection footguns (low).** The rpcd plugin's
  `ubus_call` / `uci_get` did not shell-quote object/method/key
  arguments. Current callers passed only constants so there was no
  active vulnerability, but the surface is now strict-quote everywhere.
- **SID prefix in logs (low).** syslog entries used to include the
  first 8 chars of the raw SID. They now include the first 8 chars of
  the SID hash instead, so log/scrape correlation can't be used to
  reconstruct live tokens.

### Changed
- CBI no longer auto-generates a secret at render time. A missing
  secret is surfaced as a `(not configured - press Regenerate)`
  notice; the admin must explicitly tick the Regenerate flag to
  create one. This eliminates a race between concurrent renders that
  could silently invalidate the user's existing authenticator binding.
- `Regenerate Secret` now wipes `/var/run/luci-twofa-sessions.json`
  so every active session must re-verify against the new secret.
- New rpcd method `regenerate` exposed for CLI use. NOT in the
  downgrade allow list, so only a 2FA-verified session can call it.

### Added
- `/usr/sbin/twofa-genkey` - shell utility that produces a 16-char
  base32 secret from `/dev/urandom` and writes it atomically to
  `/etc/twofa.secret` (mode 0600). Used by both the uci-defaults
  bootstrapper and the CBI's Regenerate handler so there is one
  canonical generator with one set of mode/race guarantees.
- `/usr/sbin/luci-app-twofa-guardd` + `/etc/init.d/luci-app-twofa-guard`
  - persistent session-guard daemon (procd-managed).
- Internal: `totp.verify_window(secret, token, window)` returns
  `(matched_bool, matched_counter)` so the rpcd plugin can implement
  replay protection without re-deriving counters.
- Internal: `totp._sha1` / `totp._ct_equal` exported for the rpcd
  plugin's SID-hashing fallback (when `nixio.crypto.hash` is missing
  on builds with libnixio compiled without OpenSSL).

### Migration notes
- On upgrade from r15 or earlier, the uci-defaults script moves the
  existing `twofa.global.secret` UCI option into `/etc/twofa.secret`
  (mode 0600) and unsets it from UCI. Your authenticator binding is
  preserved across the upgrade.
- All existing rpcd sessions are forcibly invalidated by the package
  postinst so any pre-r16 ACL snapshots are discarded.

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

### Fixed
- Language pack ipk filename used to be `luci-i18n-twofa-zh-cn_0_<arch>.ipk`
  (version literally `0`) because luci.mk's i18n package template pulls its
  version from `PKG_PO_VERSION`, whose default is a `git log` invocation on
  `po/` - and our CI copies the source into the SDK without a `.git` dir,
  so the lookup returns empty. Explicitly setting `PKG_PO_VERSION` in the
  Makefile so all four ipks of a release share the same `1.0-r15` version
  string.

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
