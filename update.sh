#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
exec 9>/run/lock/garageyard-update.lock
flock -n 9 || { echo 'Обновление уже выполняется.' >&2; exit 1; }
read -r game </etc/garageyard/package
binary="$game/GarageYard/Binaries/Linux/GarageYardServer"
release=https://github.com/blogerandrey-ux/garageyard-server/releases/download/server-v1.0.2
patch=GarageYardServer-1.0.1-to-1.0.2.vcdiff
old_hash=39f81e78f9b19cdcd2d41fb2c52e4a5fd9916bc00180469305e7b6d4ccfe3fc0
new_hash=faae1b0cfe0f9c38ae2cc780bef060f4fc3b6bc80b108e6b0e13d9ca463005f4
patch_hash=d2a67b756e424f572defd684e3989ba1229a2f0c534c8b020d90d942900b08a0
digest() { sha256sum <"$1" | cut -d' ' -f1; }
current=$(digest "$binary")
if [[ $current == "$new_hash" ]]; then echo 'Версия 1.0.2 уже установлена.'; exit 0; fi
if [[ $current != "$old_hash" ]]; then echo 'Для этого обновления требуется исходная версия сервера 1.0.1.' >&2; exit 1; fi
if ! command -v xdelta3 >/dev/null; then apt-get install -y xdelta3; fi
stage=$(mktemp -d "$(dirname "$binary")/.update-XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
curl --fail --location --retry 3 --output "$stage/$patch" "$release/$patch"
[[ $(digest "$stage/$patch") == "$patch_hash" ]] || { echo 'Ошибка SHA-256 обновления.' >&2; exit 1; }
xdelta3 -d -s "$binary" "$stage/$patch" "$stage/new"
[[ $(digest "$stage/new") == "$new_hash" ]] || { echo 'Ошибка SHA-256 готового сервера.' >&2; exit 1; }
chmod 755 "$stage/new"
ln "$binary" "$stage/previous"
running=false
if systemctl is-active --quiet garageyard; then running=true; fi
mv -Tf "$stage/new" "$binary"
if "$running" && ! systemctl restart garageyard; then
    mv -Tf "$stage/previous" "$binary"
    systemctl restart garageyard
    exit 1
fi
echo 'GarageYard 1.0.2 установлен.'
