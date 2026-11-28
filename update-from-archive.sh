#!/usr/bin/env bash
set -euo pipefail
archive=$(realpath "${1:?Укажите полный архив GarageYard-LinuxServer-X.Y.Z.tar.gz из Releases}")
if (( EUID != 0 )); then exec sudo bash "$0" "$archive"; fi
exec 9>/run/lock/garageyard-update.lock
flock -n 9 || { echo 'Уже выполняется обновление.' >&2; exit 1; }
name=$(basename "$archive")
[[ "$name" =~ ^GarageYard-LinuxServer-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz$ ]]
version=${BASH_REMATCH[1]}
hash=$(awk -v name="$name" '{sub(/\r$/, "")} $2 == name {print $1}' "$(dirname "$archive")/SHA256SUMS.txt")
[[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]]
printf '%s  %s\n' "$hash" "$archive" | sha256sum --check --status
pointer=/etc/garageyard/package
read -r previous < "$pointer"
test -d "$previous"
if [[ -f "$previous/.release-sha256" && $(cat "$previous/.release-sha256") == "$hash" ]]; then
    echo "Версия $version уже установлена."
    exit 0
fi
next=$(mktemp -d "$(dirname "$previous")/game-$version-XXXXXXXX")
tar --no-same-owner -xzf "$archive" -C "$next"
binary=GarageYard/Binaries/Linux/GarageYardServer
test -x "$next/$binary"
chmod 755 "$next"
echo "$hash" > "$next/.release-sha256"
select_package() {
    local temp
    temp=$(mktemp /etc/garageyard/.package-XXXXXXXX)
    printf '%s\n' "$1" > "$temp"
    chmod --reference="$pointer" "$temp"
    chown --reference="$pointer" "$temp"
    mv -T "$temp" "$pointer"
}
running=false
if systemctl is-active --quiet garageyard; then running=true; fi
rollback() {
    local result=$?
    if (( result != 0 )); then
        select_package "$previous"
        if "$running"; then systemctl restart garageyard; fi
    fi
}
trap rollback EXIT
if "$running"; then systemctl stop garageyard; fi
if [[ -d "$previous/GarageYard/Saved" ]]; then cp -a "$previous/GarageYard/Saved" "$next/GarageYard/"; fi
select_package "$next"
if "$running"; then
    systemctl start garageyard
    ready=false
    for ((i=0; i<30; i++)); do
        if pgrep -u garageyard -f -- "$next/$binary" >/dev/null && ss -Hlun 'sport = :7777' | grep -q .; then
            ready=true; break
        fi
        sleep 1
    done
    "$ready"
fi
echo "GarageYard $version установлен в $next. Предыдущая версия сохранена в $previous."
