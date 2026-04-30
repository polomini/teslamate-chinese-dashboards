#!/usr/bin/env bash
# 从官方源 TeslaMate 迁移到中文 Dashboard 版（teslamate-chinese-dashboards）
# 一键脚本：找 docker-compose.yml → 备份 → 改 grafana image + 加 ENV → 重启 grafana → 装 SQL
#
# 数据零丢失。完全可逆。
# 跑：bash migrate-from-official.sh
set -euo pipefail

REPO_TAG="${REPO_TAG:-v1.6.0}"  # 拉 SQL 用的版本（默认最新稳定）
NEW_IMAGE="bswlhbhmt816/teslamate-chinese-dashboards:latest"
OFFICIAL_IMAGE_PATTERN='teslamate/grafana(:[a-zA-Z0-9._-]*)?'

echo "🇨🇳 TeslaMate 中文 Dashboard 迁移脚本（从官方源 → 我们的源）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ── 1. 找 docker-compose.yml ────────────────────────────────────────
COMPOSE_FILE=""
for candidate in \
    "$PWD/docker-compose.yml" \
    "$PWD/docker-compose.yaml" \
    "$HOME/teslamate/docker-compose.yml" \
    "$HOME/teslamate-chinese/docker-compose.yml" \
    "/opt/teslamate/docker-compose.yml" \
    "/srv/teslamate/docker-compose.yml"; do
    if [[ -f "$candidate" ]]; then
        COMPOSE_FILE="$candidate"
        break
    fi
done

if [[ -z "$COMPOSE_FILE" ]]; then
    echo "❌ 找不到 docker-compose.yml。"
    echo "   把这个脚本放到你 docker-compose.yml 所在目录再跑，或："
    echo "   COMPOSE_FILE=/路径/docker-compose.yml bash migrate-from-official.sh"
    exit 1
fi

echo "✓ 找到 docker-compose.yml：$COMPOSE_FILE"

# ── 2. 检测是不是官方源 ──────────────────────────────────────────────
if grep -qE "image:\s*${OFFICIAL_IMAGE_PATTERN}" "$COMPOSE_FILE"; then
    CURRENT_IMAGE=$(grep -oE "image:\s*${OFFICIAL_IMAGE_PATTERN}" "$COMPOSE_FILE" | head -1 | sed 's/image:\s*//')
    echo "✓ 检测到官方 grafana 镜像：$CURRENT_IMAGE"
elif grep -q "$NEW_IMAGE" "$COMPOSE_FILE"; then
    echo "ℹ️  你已经在我们的镜像上了，不需要迁移。"
    echo "   要升级新版本：bash simple-deploy.sh（脚本会自动进升级模式）"
    exit 0
else
    echo "⚠️  没识别出官方 grafana image。当前文件里 grafana service 是："
    grep -A2 -E "^\s+grafana:" "$COMPOSE_FILE" | head -5 || true
    echo
    echo "   这个脚本只处理「官方源 → 我们」的迁移。如果你是自定义 image，"
    echo "   按 README 方法 C 手动改即可。"
    exit 1
fi

# ── 3. 预览改动 ─────────────────────────────────────────────────────
echo
echo "📋 我会做这 4 件事："
echo "   1) 备份 docker-compose.yml.bak.$(date +%Y%m%d-%H%M%S)"
echo "   2) 改 grafana image：$CURRENT_IMAGE  →  $NEW_IMAGE"
echo "   3) docker compose pull grafana && docker compose up -d grafana"
echo "   4) 装 2 个 SQL（坐标转换 + 分时电价旁路表，幂等可重跑）"
echo
echo "⚠️  TeslaMate / Postgres / MQTT 容器完全不动。ENCRYPTION_KEY、Tesla token、"
echo "    所有数据 0 丢失。万一不满意，把 image 改回去重启 grafana 即可回滚。"
echo
read -rp "继续？ [y/N] " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "已取消，没动任何东西。"; exit 0; }

# ── 4. 备份 ─────────────────────────────────────────────────────────
BACKUP_FILE="${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "✓ 已备份到 $BACKUP_FILE"

# ── 5. 改 image ─────────────────────────────────────────────────────
# 用 sed 行内替换 image 那一行
sed -i.tmp -E "s|image:\s*${OFFICIAL_IMAGE_PATTERN}|image: ${NEW_IMAGE}|" "$COMPOSE_FILE"
rm -f "${COMPOSE_FILE}.tmp"
echo "✓ image 已替换"

# ── 6. 重启 grafana ─────────────────────────────────────────────────
COMPOSE_DIR=$(dirname "$COMPOSE_FILE")
cd "$COMPOSE_DIR"
echo
echo "→ 拉新镜像 + 重启 grafana..."
docker compose pull grafana
docker compose up -d grafana
echo "✓ grafana 已切到中文版镜像"

# ── 7. 装 SQL ───────────────────────────────────────────────────────
echo
echo "→ 装坐标转换函数（地图轨迹纠偏）..."
COORD_URL="https://raw.githubusercontent.com/wjsall/teslamate-chinese-dashboards/${REPO_TAG}/sql/install-coord-functions.sql"
if curl -fsSL "$COORD_URL" | docker exec -i teslamate-database-1 psql -U teslamate -d teslamate >/dev/null 2>&1; then
    echo "✓ 坐标函数装好"
else
    echo "⚠️  坐标函数装失败（可能容器名不是 teslamate-database-1）。手动跑："
    echo "    curl -fsSL $COORD_URL | docker exec -i 你的database容器 psql -U teslamate -d teslamate"
fi

echo
echo "→ 装分时电价旁路表（不动 TeslaMate 任何表）..."
TOU_URL="https://raw.githubusercontent.com/wjsall/teslamate-chinese-dashboards/${REPO_TAG}/sql/install-tou.sql"
if curl -fsSL "$TOU_URL" | docker exec -i teslamate-database-1 psql -U teslamate -d teslamate >/dev/null 2>&1; then
    echo "✓ 分时电价表装好"
else
    echo "⚠️  分时电价表装失败。手动跑："
    echo "    curl -fsSL $TOU_URL | docker exec -i 你的database容器 psql -U teslamate -d teslamate"
fi

# ── 8. 完成 ─────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 迁移完成"
echo
echo "现在打开 http://你的IP:3000 — 43 个中文 dashboard 已就绪。"
echo
echo "📌 下一步（可选）："
echo "   • 配分时电价：仪表盘里点「⚡ 分时电价配置」→「🌆 一键导入城市模板」"
echo "   • 地图改国内瓦片：仪表盘地图右上角下拉框选高德/谷歌"
echo
echo "🔙 想回滚？"
echo "   cp $BACKUP_FILE $COMPOSE_FILE"
echo "   cd $COMPOSE_DIR && docker compose up -d grafana"
echo
echo "💬 出问题：https://t.me/+BeOASgmvE_IyNzNl（Telegram 交流群）"
