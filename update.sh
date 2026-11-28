#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
src=$(cd "$(dirname -- "$0")" && pwd)
if [[ ! -r /etc/garageyard/package ]]; then
    echo "Сначала установите сервер командой bash install.sh." >&2
    exit 1
fi
read -r game < /etc/garageyard/package
version=1.0.6
hash=52e5126d33fdf9ed0a3fb8f09701f39da4c6eaa47f977c584ecb741f60fbbc97
if [[ -f "$game/.release-sha256" && $(cat "$game/.release-sha256") == "$hash" ]]; then
    echo "Версия $version уже установлена."
    exit 0
fi

name="GarageYard-LinuxServer-$version.tar.gz"
cache="$(dirname -- "$game")/.downloads-0/$hash"
install -d -m700 "$cache"
exec 8<"$cache"
flock -n 8 || { echo 'Скачивание обновления уже выполняется.' >&2; exit 1; }
source "$src/download.sh"
release="https://github.com/blogerandrey-ux/garageyard-server/releases/download/server-v$version"
download_asset "$release/GarageYard-LinuxServer.tar.gz" "$cache/$name" "$hash"
printf '%s  %s\n' "$hash" "$name" > "$cache/SHA256SUMS.txt"
bash "$src/update-from-archive.sh" "$cache/$name"
rm -- "$cache/$name" "$cache/SHA256SUMS.txt"
rmdir -- "$cache"
