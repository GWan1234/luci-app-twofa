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

# 6b. 部署中文翻译（需要 po2lmo，或通过 IPK 安装获得完整 i18n）
if command -v po2lmo >/dev/null 2>&1; then
	echo "Syncing i18n..."
	for lang in zh-cn zh_Hans; do
		po="po/${lang}/luci-app-twofa.po"
		if [ -f "$po" ]; then
			po2lmo "$po" "/tmp/luci-app-twofa.${lang}.lmo"
			$SCP_CMD "/tmp/luci-app-twofa.${lang}.lmo" "$ROUTER_USER@$ROUTER_HOST:/usr/lib/lua/luci/i18n/"
			rm -f "/tmp/luci-app-twofa.${lang}.lmo"
		fi
	done
else
	echo "提示: 未找到 po2lmo，中文界面需通过 IPK 安装或手动编译 .lmo 文件"
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
