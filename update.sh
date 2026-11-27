#!/usr/bin/env bash
set -euo pipefail
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
exec 9>/run/lock/garageyard-update.lock
flock -n 9 || { echo 'Обновление уже выполняется.' >&2; exit 1; }
package=/etc/garageyard/package
read -r game <"$package"
parent=$(dirname -- "$game")
binary=GarageYard/Binaries/Linux/GarageYardServer
old1=39f81e78f9b19cdcd2d41fb2c52e4a5fd9916bc00180469305e7b6d4ccfe3fc0
old2=faae1b0cfe0f9c38ae2cc780bef060f4fc3b6bc80b108e6b0e13d9ca463005f4
expected=df2c68ad2cf7a13146df8705aa834c8d5dbe1ca3e83d7d66070a02280e053b24
digest() { sha256sum <"$1" | cut -d' ' -f1; }
current=$(digest "$game/$binary")
if [[ $current == "$expected" ]]; then echo 'Версия 1.0.3 уже установлена.'; exit 0; fi
if [[ $current != "$old1" && $current != "$old2" ]]; then
    echo 'Для этого патча нужен публичный сервер 1.0.1 или 1.0.2.' >&2
    exit 1
fi
if ! command -v xdelta3 >/dev/null; then apt-get install -y xdelta3; fi
source "$(dirname -- "$0")/download.sh"
release=https://github.com/blogerandrey-ux/garageyard-server/releases/download/server-v1.0.3
hash=fb7d38f0bf0653296a67cb83a80dd2f7846e0cf7faa82586f38111fcc9bcbd26
cache="$parent/.downloads-0/$hash"
download_asset "$release/Upgrade-1.0.3.tar.gz" "$cache/Upgrade-1.0.3.tar.gz" "$hash"
work=$(mktemp -d "$parent/.upgrade-XXXXXXXX")
next=$(mktemp -d "$parent/game-1.0.3-XXXXXXXX")
# Never remove a tree selected by the live service, including after interruption.
cleanup() {
    rm -rf -- "$work"
    if [[ $(cat "$package") != "$next" ]]; then rm -rf -- "$next"; fi
}
trap cleanup EXIT
tar -xzf "$cache/Upgrade-1.0.3.tar.gz" -C "$work"
base="$game/$binary"
if [[ $current == "$old1" ]]; then
    xdelta3 -d -s "$base" "$work/previous.vcdiff" "$work/1.0.2"
    [[ $(digest "$work/1.0.2") == "$old2" ]]
    base="$work/1.0.2"
fi
xdelta3 -d -s "$base" "$work/server.vcdiff" "$work/server"
[[ $(digest "$work/server") == "$expected" ]]
chmod 755 "$work/server"
cp -al -- "$game/." "$next/"
mv -Tf "$work/server" "$next/$binary"
for file in Manifest_UFSFiles_Linux.txt Manifest_NonUFSFiles_Linux.txt GarageYard/Content/Paks/GarageYard-LinuxServer.pak; do
    mv -Tf "$work/$file" "$next/$file"
done
chmod 755 "$next"
select_package() {
    local pointer
    pointer=$(mktemp /etc/garageyard/.package-XXXXXXXX)
    printf '%s\n' "$1" >"$pointer"
    chmod --reference="$package" "$pointer"
    chown --reference="$package" "$pointer"
    mv -Tf "$pointer" "$package"
}
running=false
if systemctl is-active --quiet garageyard; then running=true; fi
select_package "$next"
if "$running" && ! systemctl restart garageyard; then
    select_package "$game"
    systemctl restart garageyard
    exit 1
fi
rm -- "$cache/Upgrade-1.0.3.tar.gz"
rmdir -- "$cache"
echo 'GarageYard 1.0.3 установлен.'
