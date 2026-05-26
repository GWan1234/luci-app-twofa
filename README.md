# luci-app-twofa

Two-Factor Authentication (TOTP) for OpenWrt LuCI web interface.

- Supports Google Authenticator and Microsoft Authenticator.
- Configurable via LuCI **Services → Two-Factor Auth** menu.
- Compatible with OpenWrt 22.03+.
- Automatically built for multiple architectures via GitHub Actions.

## Features
- Enable/disable 2FA from LuCI.
- Auto-generate TOTP secret and QR code.
- Secure HMAC-SHA1 based TOTP verification.
- Only affects root login (LuCI default user).

## Installation
GitHub Actions produces two `all` packages (install on any CPU architecture):
- `luci-app-twofa_x86_64_all.ipk`
- `luci-app-twofa_aarch64_all.ipk`

```sh
opkg install luci-app-twofa_*.ipk
```
