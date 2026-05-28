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

# 6. preload JS (rpc.declare → luci.twofa.{status,verify})
echo "Syncing JS..."
$SCP_CMD htdocs/luci-static/resources/preload/twofa.js "$ROUTER_USER@$ROUTER_HOST:/www/luci-static/resources/preload/"

# 6b. 部署中文翻译
# LuCI 的 i18n.lua 会把 lang 做 gsub('_','-'):lower() 归一化，所以无论 UCI 里是
#   zh_Hans / zh_cn / zh-cn，最终都会查 luci-app-twofa.zh-cn.lmo 这个文件。
# 这里也顺手再投一份 .zh-hans.lmo，照顾极少数把 lang 设成 zh_Hans 的固件。
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
	echo "提示: 本机未安装 po2lmo，改用路由器侧的 po2lmo 编译 ..."
	REMOTE_PO="/tmp/luci-app-twofa.zh_Hans.po"
	$SCP_CMD "$PO_SRC" "$ROUTER_USER@$ROUTER_HOST:$REMOTE_PO"
	$SSH_CMD "set -e; \
		if command -v po2lmo >/dev/null 2>&1; then \
			po2lmo $REMOTE_PO /usr/lib/lua/luci/i18n/luci-app-twofa.zh-cn.lmo; \
			cp -f /usr/lib/lua/luci/i18n/luci-app-twofa.zh-cn.lmo \
				/usr/lib/lua/luci/i18n/luci-app-twofa.zh-hans.lmo; \
			rm -f $REMOTE_PO; \
			echo '路由器侧已生成 luci-app-twofa.zh-cn.lmo'; \
		else \
			echo '错误: 路由器上也没有 po2lmo, 请先在路由器安装: opkg update && opkg install po2lmo'; \
			rm -f $REMOTE_PO; \
			exit 1; \
		fi"
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

# 11. 清 LuCI 索引缓存
$SSH_CMD "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache"

cat <<EOF
部署完成。

验收步骤：
  1. ssh 进路由器：ubus list | grep luci.twofa     -> 应能看到 luci.twofa
  2. ssh 进路由器：ubus -v list luci.twofa         -> 应列出 status / verify 两个方法
  3. 浏览器重新登录 LuCI，应弹出 2FA modal
  4. modal 弹出后，打开 DevTools Network 面板：
       - 此时随便点别的菜单, 任意 ubus 调用都应报 ACL denied (说明 rpcd 已强制下钳)
       - 在 modal 里输入正确 TOTP -> 页面 reload, 一切恢复
  5. 若输错 TOTP, 会话依然处于"已下钳"状态, 直到验证通过为止
EOF
