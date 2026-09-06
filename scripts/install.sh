#!/bin/bash
# Собирает панель и ставит её в /Applications.
#
# Автозапуск и хук статусов сессий больше не ставит этот скрипт — их
# включает само приложение (Settings -> Sources/Aikon/HookInstaller.swift,
# Sources/Aikon/LoginItem.swift). Так это работает и для человека, который
# скачал готовый .app без репозитория и скриптов.
set -euo pipefail

cd "$(dirname "$0")/.."
bash scripts/bundle.sh

DEST="/Applications/Aikon.app"

pkill -f "Aikon.app/Contents/MacOS/Aikon" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R build/Aikon.app "$DEST"

echo "установлено: $DEST"
echo "автозапуск и хук статусов сессий включаются в настройках самого приложения"
