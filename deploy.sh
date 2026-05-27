#!/bin/bash

# 使用方法: ./deploy.sh [路由器地址] [端口]
# 示例:
#   ./deploy.sh 192.168.52.11
#   ./deploy.sh homeproxy.404area.vip 36666

ROUTER_HOST=${1:-192.168.52.11}
ROUTER_PORT=${2:-22}
ROUTER_USER="root"

echo "正在部署到 $ROUTER_USER@$ROUTER_HOST:$ROUTER_PORT ..."

# 定义 SSH 和 SCP 命令，包含端口参数
SSH_CMD="ssh -p $ROUTER_PORT $ROUTER_USER@$ROUTER_HOST"
SCP_CMD="scp -P $ROUTER_PORT"

# 1. 确保目标目录存在
$SSH_CMD "mkdir -p /usr/lib/lua/luci/controller/admin/system/ \
/usr/lib/lua/luci/model/cbi/admin_system/ \
/usr/lib/lua/luci/twofa/ \
/usr/lib/lua/luci/i18n/ \
/www/luci-static/resources/preload/ \
/usr/share/luci/menu.d/ \
/usr/share/rpcd/acl.d/ \
/etc/config/ \
/etc/uci-defaults/"

# 2. 复制 Lua 控制器
echo "Syncing Controller..."
$SCP_CMD luasrc/controller/admin/system/twofa.lua $ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/controller/admin/system/

# 3. 复制 Lua 模型 (CBI)
echo "Syncing Model..."
$SCP_CMD luasrc/model/cbi/admin_system/twofa.lua $ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/model/cbi/admin_system/

# 4. 复制核心库 (Auth & TOTP)
echo "Syncing Libraries..."
$SCP_CMD luasrc/twofa/*.lua $ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/twofa/

# 5. 复制视图 (Hook)

# 6. 复制静态资源 (JS)
echo "Syncing JS..."
$SCP_CMD htdocs/luci-static/resources/preload/twofa.js $ROUTER_USER@$ROUTER_HOST:/www/luci-static/resources/preload/

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

# 7. 复制菜单与 ACL
echo "Syncing menu and ACL..."
$SCP_CMD root/usr/share/luci/menu.d/luci-app-twofa.json $ROUTER_USER@$ROUTER_HOST:/usr/share/luci/menu.d/
$SCP_CMD root/usr/share/rpcd/acl.d/luci-app-twofa.json $ROUTER_USER@$ROUTER_HOST:/usr/share/rpcd/acl.d/

# 8. 复制配置文件 (关键修复：之前漏了这一步，导致 ubus code 4 错误)
echo "Syncing Config..."
$SCP_CMD root/etc/config/twofa $ROUTER_USER@$ROUTER_HOST:/etc/config/

# 9. 应用 UCI 默认值（为 root 授予 ACL，并修复损坏的 twofa 配置）
echo "Applying uci-defaults..."
$SCP_CMD root/etc/uci-defaults/10-luci-app-twofa $ROUTER_USER@$ROUTER_HOST:/etc/uci-defaults/
$SCP_CMD root/etc/uci-defaults/98-luci-app-twofa $ROUTER_USER@$ROUTER_HOST:/etc/uci-defaults/
$SCP_CMD root/etc/uci-defaults/99-luci-app-twofa $ROUTER_USER@$ROUTER_HOST:/etc/uci-defaults/
$SSH_CMD "chmod +x /etc/uci-defaults/10-luci-app-twofa /etc/uci-defaults/98-luci-app-twofa /etc/uci-defaults/99-luci-app-twofa; \
/etc/uci-defaults/10-luci-app-twofa; \
/etc/uci-defaults/98-luci-app-twofa 2>/dev/null || true; \
/etc/uci-defaults/99-luci-app-twofa 2>/dev/null || true"

# 10. 重启服务
echo "Restarting RPCD..."
$SSH_CMD "/etc/init.d/rpcd restart"

# 11. 清除 LuCI 缓存
$SSH_CMD "rm -rf /tmp/luci-indexcache /tmp/luci-modulecache"

echo "部署完成！请刷新浏览器测试。"
