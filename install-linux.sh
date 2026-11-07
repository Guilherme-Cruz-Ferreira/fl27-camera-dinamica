#!/bin/bash
# Instala o camera_dinamica no Sider (Linux/Wine).  Uso: ./install-linux.sh "<pasta SiderAddons>"
# Ex.: ./install-linux.sh "$HOME/.wine/drive_c/Program Files (x86)/SP Football Life 2027/SiderAddons"
set -e
AQUI="$(cd "$(dirname "$0")" && pwd)"
SIDER="${1:-$SIDER}"
[ -n "$SIDER" ] || { echo "Uso: $0 \"<pasta SiderAddons>\" (ou defina SIDER)"; exit 1; }
[ -f "$SIDER/sider.ini" ] && [ -f "$SIDER/modules/camera.lua" ] || { echo "Nao achei sider.ini e modules/camera.lua em: $SIDER"; exit 1; }
if ps -eo args | awk '/FL_20[0-9][0-9]\.exe|sider\.exe/ && !/awk/ {f=1} END{exit !f}'; then echo "Feche o jogo antes."; exit 1; fi
[ -f "$SIDER/sider.ini.bak-camera-dinamica" ] || cp "$SIDER/sider.ini" "$SIDER/sider.ini.bak-camera-dinamica"
cp "$AQUI/camera_dinamica.lua" "$SIDER/modules/camera_dinamica.lua"
[ -f "$SIDER/camera_dinamica.ini" ] || cp "$AQUI/camera_dinamica.ini" "$SIDER/camera_dinamica.ini"
if ! grep -q 'lua.module = "camera_dinamica.lua"' "$SIDER/sider.ini"; then
  sed -i 's/^\(\s*\)lua\.module = "camera\.lua"\r\?$/&\n\1lua.module = "camera_dinamica.lua"/' "$SIDER/sider.ini"
fi
grep -n camera "$SIDER/sider.ini"; echo "Pronto. Abra o jogo."
