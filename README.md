# luci-app-twofa

Two-Factor Authentication (TOTP, RFC 6238) for the OpenWrt / ImmortalWrt LuCI web interface.

- Works with Google Authenticator, Microsoft Authenticator, Authy, etc.
- Configurable from LuCI **Services → 2FA Settings**.
- Enforced at the **rpcd ACL layer**, not the page layer — the modal cannot be bypassed by knowing a direct URL or by calling ubus directly.
- English by default; Simplified Chinese available as a separate language pack.

## Compatibility

**Verified on:**

| Item | Version | Notes |
|---|---|---|
| Firmware | **ImmortalWrt 24.10** | Primary target |
| Lua | **Lua 5.1.5 (double int32)** | The patched Lua that ImmortalWrt ships with |
| LuCI | `git-24.265.*` (OpenWrt 24.10 LuCI branch) | Modern client-side LuCI |
| `rpcd`, `nixio`, `qrencode` | Default ImmortalWrt versions | All declared in `LUCI_DEPENDS` |

**Probably works on:** any OpenWrt 22.03+ derivative shipping rpcd, nixio (with or without `nixio.crypto`), qrencode, and any Lua version from 5.1 through 5.4. The TOTP implementation deliberately avoids `\xNN` hex escapes (Lua 5.2+ only), assumes signed-or-unsigned bit modules, and falls back to a pure-Lua HMAC-SHA1 when `nixio.crypto` is missing — but only ImmortalWrt 24.10 is in CI.

**Not supported:** any router where you cannot set the system clock within ±2 minutes of the TOTP token source (the authenticator app). TOTP is by definition time-sensitive.

## Packages

GitHub Actions produces **four ipks per release**, one (package × architecture) pair:

| File | Required? | Purpose |
|---|---|---|
| `luci-app-twofa_<ver>_x86_64.ipk` | Yes | Main package, English UI, x86_64 routers |
| `luci-app-twofa_<ver>_aarch64.ipk` | Yes | Main package, English UI, aarch64 routers |
| `luci-i18n-twofa-zh-cn_<ver>_x86_64.ipk` | Optional | 中文界面，依赖主包 |
| `luci-i18n-twofa-zh-cn_<ver>_aarch64.ipk` | Optional | 中文界面，依赖主包 |

> The main package is `PKGARCH:=all` (pure Lua, no compiled binaries) so the x86_64 and aarch64 ipks are byte-identical content-wise — the per-arch filename is just a packaging convenience so you can pick "the one for my router" without thinking.

## Installation

Download the ipks for your architecture from the [latest rolling release](../../releases/tag/latest) (auto-built from `main`) or any tagged release.

```sh
# 1. Main package (English UI)
opkg install ./luci-app-twofa_*.ipk

# 2. Optional: Simplified Chinese language pack
opkg install ./luci-i18n-twofa-zh-cn_*.ipk
```

After install, refresh the LuCI tab once (Ctrl+Shift+R if the old strings linger from cache).

## First-time setup

1. **Services → 2FA Settings**
2. Scan the QR code with your authenticator app (or type the 16-char base32 secret manually)
3. Tick **Enable 2FA**, save
4. Log out, log back in. You should see the 2FA challenge modal before LuCI loads.

If the modal accepts the code from your phone, you're done. If it rejects every code:

- `logread -e luci-app-twofa` will tell you whether the failure is `totp_mismatch` (wrong code / clock skew) or something deeper.
- Make sure router time is synced: `date` should agree with your phone within 30s.

## Build from source

```sh
# In an OpenWrt 24.10 SDK tree:
cp -r path/to/luci-app-twofa package/luci-app-twofa
./scripts/feeds install luci-base luci-compat luci-lib-nixio qrencode
echo "CONFIG_PACKAGE_luci-app-twofa=m"          >> .config
echo "CONFIG_PACKAGE_luci-i18n-twofa-zh-cn=m"   >> .config
make defconfig
make package/luci-app-twofa/compile V=s
```

The CI workflow in `.github/workflows/build.yml` does exactly this for both x86_64 and aarch64, and uploads the resulting 4 ipks to a rolling `latest` release on every push to `main`.

## Releases

This project follows the standard open-source release model:

| Channel | Tag | Description | When to use |
|---|---|---|---|
| **Stable** | `v1.0-rN` (`v1.0-r15`, etc.) | Permanent, versioned releases. Each one carries a curated changelog drawn from [`CHANGELOG.md`](CHANGELOG.md) plus GitHub's auto-generated commit list. | Production / normal use. |
| **Rolling** | `latest` | A single pre-release that is recreated on every push to `main`. Always carries the freshest 4 ipks but **history is not preserved**. | Testing the newest fixes before they are tagged. |
| **CI artifacts** | — | The Actions tab holds per-run ipks for 90 days; requires a logged-in GitHub session. | Reviewing a PR's build output. |

Stable releases live forever in the [Releases page](../../releases) and the most recent one wears the "Latest release" badge. The rolling `latest` is marked as a pre-release so it does NOT compete for that badge.

### How to cut a new stable release (maintainers)

1. Bump `PKG_RELEASE` in `Makefile`.
2. Add a `## [1.0-rNEW] - YYYY-MM-DD` section at the top of `CHANGELOG.md` describing the user-visible changes (Added / Changed / Fixed / Removed).
3. Commit and push to `main`. The rolling pre-release picks it up automatically.
4. Once you're happy, tag and push:
   ```sh
   git tag v1.0-rNEW -m "v1.0-rNEW"
   git push origin v1.0-rNEW
   ```
5. The `release_tag` workflow extracts your CHANGELOG section verbatim, attaches the four ipks, and publishes a permanent release.

## License

MIT
