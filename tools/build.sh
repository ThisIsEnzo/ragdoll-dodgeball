#!/usr/bin/env bash
# Сборка place без живого синка Rojo. Запуск: bash tools/build.sh
set -euo pipefail

PROJECT="${1:-default.project.json}"
OUT="${2:-build/ragdoll-dodgeball.rbxlx}"

if ! command -v rojo >/dev/null 2>&1; then
  echo "rojo не найден в PATH. Установи: aftman add rojo-rbx/rojo && aftman install" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
echo "Rojo: $(rojo --version)"
echo "Сборка $PROJECT -> $OUT"
rojo build "$PROJECT" -o "$OUT"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1))"
