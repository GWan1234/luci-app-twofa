#!/bin/bash

# 使用方法: ./deploy.sh [路由器地址] [端口]
# 示例:
#   ./deploy.sh 192.168.52.11
#   ./deploy.sh homeproxy.404area.vip 36666

set -e

ROUTER_HOST=${1:-192.168.52.11}
ROUTER_PORT=${2:-22}
ROUTER_USER="root"

echo "正在部署到 $ROUTER_USER@$ROUTER_HOST:$ROUTER_PORT ..."

SSH_CMD="ssh -p $ROUTER_PORT $ROUTER_USER@$ROUTER_HOST"
SCP_CMD="scp -P $ROUTER_PORT"

# 1. 确保目标目录存在 & 清理上一版本残留 (auth.lua / guard.lua 已废弃)
$SSH_CMD "set -e; \
mkdir -p /usr/lib/lua/luci/controller/admin/system/ \
         /usr/lib/lua/luci/model/cbi/admin_system/ \
         /usr/lib/lua/luci/twofa/ \
         /usr/lib/lua/luci/i18n/ \
         /www/luci-static/resources/preload/ \
         /usr/share/luci/menu.d/ \
         /usr/share/rpcd/acl.d/ \
         /usr/libexec/rpcd/ \
         /usr/sbin/ \
         /etc/init.d/ \
         /etc/config/ \
         /etc/uci-defaults/; \
rm -f /usr/lib/lua/luci/twofa/auth.lua /usr/lib/lua/luci/twofa/guard.lua; \
rm -f /var/run/luci-twofa-sessions.json"

# 2. Lua 控制器（已精简为只挂载 CBI 菜单）
echo "Syncing Controller..."
$SCP_CMD luasrc/controller/admin/system/twofa.lua "$ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/controller/admin/system/"

# 3. CBI 模型
echo "Syncing Model..."
$SCP_CMD luasrc/model/cbi/admin_system/twofa.lua "$ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/model/cbi/admin_system/"

# 4. 公共库 (TOTP, 给 rpcd 插件复用)
echo "Syncing Libraries..."
$SCP_CMD luasrc/twofa/totp.lua "$ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/twofa/"

# 5. rpcd ubus 对象插件 —— 真正负责会话级 ACL 升降
echo "Syncing rpcd plugin..."
$SCP_CMD root/usr/libexec/rpcd/luci-app-twofa "$ROUTER_USER@$ROUTER_HOST:/usr/libexec/rpcd/luci-app-twofa"
$SSH_CMD "chmod +x /usr/libexec/rpcd/luci-app-twofa"

# 5b. twofa-genkey: secret 生成器，CBI 的 Regenerate / uci-defaults 都靠它写 /etc/twofa.secret (0600)
echo "Syncing twofa-genkey..."
$SCP_CMD root/usr/sbin/twofa-genkey "$ROUTER_USER@$ROUTER_HOST:/usr/sbin/twofa-genkey"
$SSH_CMD "chmod +x /usr/sbin/twofa-genkey"

# 5c. session-guard 守护进程：闭合 rpcd 插件懒触发降权的非浏览器绕过窗口
echo "Syncing session-guard daemon..."
$SCP_CMD root/usr/sbin/luci-app-twofa-guardd "$ROUTER_USER@$ROUTER_HOST:/usr/sbin/luci-app-twofa-guardd"
$SCP_CMD root/etc/init.d/luci-app-twofa-guard "$ROUTER_USER@$ROUTER_HOST:/etc/init.d/luci-app-twofa-guard"
$SSH_CMD "chmod +x /usr/sbin/luci-app-twofa-guardd /etc/init.d/luci-app-twofa-guard"

# 6. preload JS (rpc.declare → luci-app-twofa.{status,verify})
echo "Syncing JS..."
$SCP_CMD htdocs/luci-static/resources/preload/twofa.js "$ROUTER_USER@$ROUTER_HOST:/www/luci-static/resources/preload/"

# 6b. 部署中文翻译
#
# 注意:
#   - po2lmo 是 luci-base 编译期的 host 工具, opkg 源里不存在,
#     在路由器上跑 `opkg install po2lmo` 一定失败, 别再走那个套路.
#   - 在 Mac/Linux 本机装 po2lmo 的方法:
#       git clone --depth 1 https://github.com/openwrt/luci.git /tmp/luci
#       cd /tmp/luci/build && cc -O2 -o po2lmo po2lmo.c contrib/lmo.c contrib/template_lmo.c
#       sudo install -m 0755 po2lmo /usr/local/bin/
#   - 用 GitHub Actions 出来的 ipk 已经把 .lmo 打进包里, 走 ipk 路径不用管这一段.
#
# LuCI 的 i18n.load() 会把 lang 做 gsub('_','-'):lower() 归一化, 所以:
#   uci.luci.main.lang = zh_Hans  ->  zh-hans  -> 命中 luci-app-twofa.zh-hans.lmo
#   uci.luci.main.lang = zh_cn    ->  zh-cn    -> 命中 luci-app-twofa.zh-cn.lmo
# 两份 .lmo 内容相同, 我们直接 cp 一份.

PO_SRC="po/zh_Hans/luci-app-twofa.po"

if [ ! -f "$PO_SRC" ]; then
	echo "跳过 i18n: 未找到 $PO_SRC"
elif command -v po2lmo >/dev/null 2>&1; then
	echo "Syncing i18n..."
	TMP_LMO="$(mktemp -t luci-app-twofa.XXXXXX.lmo)"
	po2lmo "$PO_SRC" "$TMP_LMO"
	for suffix in zh-cn zh-hans; do
		$SCP_CMD "$TMP_LMO" "$ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/i18n/luci-app-twofa.${suffix}.lmo"
	done
	rm -f "$TMP_LMO"
else
	echo "跳过 i18n: 本机未安装 po2lmo, 中文文案可能不显示."
	echo "        如需在 deploy.sh 路径下也启用中文, 请按脚本注释装一份 po2lmo."
fi

# 7. 菜单 + ACL (ACL 已重写, 见 root/usr/share/rpcd/acl.d/luci-app-twofa.json)
echo "Syncing menu and ACL..."
$SCP_CMD root/usr/share/luci/menu.d/luci-app-twofa.json "$ROUTER_USER@$ROUTER_HOST:/usr/share/luci/menu.d/"
$SCP_CMD root/usr/share/rpcd/acl.d/luci-app-twofa.json "$ROUTER_USER@$ROUTER_HOST:/usr/share/rpcd/acl.d/"

# 8. 默认 UCI 配置 (没有 /etc/config/twofa 就会让 rpc uci.get 报 code 4)
echo "Syncing Config..."
$SCP_CMD root/etc/config/twofa "$ROUTER_USER@$ROUTER_HOST:/etc/config/twofa.dist"
$SSH_CMD "[ -s /etc/config/twofa ] || cp /etc/config/twofa.dist /etc/config/twofa; rm -f /etc/config/twofa.dist"

# 9. uci-defaults (生成 secret, 把 luci-app-twofa 加进 root 的 rpcd acl 列表)
echo "Applying uci-defaults..."
$SCP_CMD root/etc/uci-defaults/10-luci-app-twofa "$ROUTER_USER@$ROUTER_HOST:/etc/uci-defaults/"
$SSH_CMD "chmod +x /etc/uci-defaults/10-luci-app-twofa && /etc/uci-defaults/10-luci-app-twofa"

# 10. 重启 rpcd，让新的 acl.d / libexec/rpcd 生效；销毁所有旧会话避免脏 ACL
echo "Restarting RPCD..."
$SSH_CMD "/etc/init.d/rpcd restart; sleep 1; ubus call session destroy '{\"timeout\":0}' >/dev/null 2>&1 || true"

# 10b. 启动 / 重启 session-guard 守护进程
echo "Starting session-guard..."
$SSH_CMD "/etc/init.d/luci-app-twofa-guard enable >/dev/null 2>&1 || true; /etc/init.d/luci-app-twofa-guard restart >/dev/null 2>&1 || true"

# 11. 清 LuCI 索引缓存
$SSH_CMD "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache"

cat <<EOF
部署完成。

验收步骤：
  1. ssh 进路由器：ubus list | grep luci-app-twofa  -> 应能看到 luci-app-twofa
  2. ssh 进路由器：ubus -v list luci-app-twofa      -> 应列出 status / verify 两个方法
  3. 浏览器重新登录 LuCI，应弹出 2FA modal
  4. modal 弹出后，打开 DevTools Network 面板：
       - 此时随便点别的菜单, 任意 ubus 调用都应报 ACL denied (说明 rpcd 已强制下钳)
       - 在 modal 里输入正确 TOTP -> 页面 reload, 一切恢复
  5. 若输错 TOTP, 会话依然处于"已下钳"状态, 直到验证通过为止
EOF
