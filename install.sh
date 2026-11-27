#!/usr/bin/env bash
set -euo pipefail
repo=blogerandrey-ux/garageyard-server
src=$(cd "$(dirname "$0")" && pwd)
unit=/etc/systemd/system
lib=/usr/local/lib/garageyard
root=()
if (( EUID != 0 )); then root=(sudo); fi
command -v python3 >/dev/null
[[ -d /run/systemd/system ]] || { echo 'Требуется Linux с работающим systemd.' >&2; exit 1; }
case ${1:-game} in
directory)
    "${root[@]}" install -Dm755 "$src/directory.py" "$lib/directory.py"
    "${root[@]}" install -m644 "$src/garageyard-directory.service" "$unit/"
    "${root[@]}" systemctl daemon-reload
    "${root[@]}" systemctl enable --now garageyard-directory
    echo 'Общий каталог слушает UDP 14080.'
    exit 0 ;;
game) ;;
*) echo 'Использование: bash install.sh [game|directory]' >&2; exit 2 ;;
esac
[[ $(uname -m) == x86_64 ]] || { echo 'Нужен Linux x86-64.' >&2; exit 1; }
dest=$(realpath -m "${GARAGEYARD_HOME:-/srv/garageyard}")
if [[ ! -d $dest ]]; then "${root[@]}" install -d -m755 "$dest"; fi
exec 8<"$dest"
flock -n 8 || { echo 'Установка в этом каталоге уже выполняется.' >&2; exit 1; }
if [[ ! -f "$dest/game/GarageYardServer.sh" ]]; then
    stage=$("${root[@]}" mktemp -d "$dest/.install-XXXXXXXX")
    trap '"${root[@]}" rm -rf -- "$stage"' EXIT
    "${root[@]}" chown "$(id -u):$(id -g)" "$stage"
    archive=${GARAGEYARD_ARCHIVE:-}
    if [[ -z $archive ]]; then
        source "$src/download.sh"
        release="https://github.com/$repo/releases/latest/download"
        name=GarageYard-LinuxServer.tar.gz
        curl --fail --location --silent --show-error --retry 3 "$release/SHA256SUMS" -o "$stage/SHA256SUMS"
        hash=$(awk -v name="$name" 'NF == 2 && ($2 == name || $2 == "*" name) {print $1}' "$stage/SHA256SUMS")
        [[ $hash =~ ^[a-f0-9]{64}$ ]] || { echo "В SHA256SUMS нет однозначной суммы для $name." >&2; exit 1; }
        cache="$dest/.downloads-$(id -u)"
        "${root[@]}" install -d -m700 -o "$(id -u)" -g "$(id -g)" "$cache"
        archive="$cache/$hash/$name"
        download_asset "$release/$name" "$archive" "$hash"
    fi
    mkdir "$stage/game"
    python3 - "$archive" "$stage/game" <<'PY'
import pathlib, sys, tarfile
root = pathlib.Path(sys.argv[2])
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        if not (member.isfile() or member.isdir()) or not (root / member.name).resolve().is_relative_to(root):
            raise SystemExit(f'Недопустимый файл в архиве: {member.name}')
        archive.extract(member, root, set_attrs=False)
        (root / member.name).chmod(0o755 if member.isdir() or member.mode & 0o111 else 0o644)
PY
    test -f "$stage/game/GarageYardServer.sh"
    test -d "$stage/game/GarageYard/Content/Paks"
    "${root[@]}" mv -T "$stage/game" "$dest/game"
    if [[ -z ${GARAGEYARD_ARCHIVE:-} ]]; then rm -- "$archive"; rmdir -- "$cache/$hash"; fi
fi
exec 8<&-
if ! getent passwd garageyard >/dev/null; then
    "${root[@]}" useradd --system --user-group --home-dir /var/lib/garageyard --shell /usr/sbin/nologin garageyard
fi
"${root[@]}" install -d -m750 -o root -g garageyard /etc/garageyard
printf '%s\n' "$dest/game" | "${root[@]}" tee /etc/garageyard/package >/dev/null
"${root[@]}" install -Dm755 "$src/garageyard.py" /usr/local/bin/garageyard
"${root[@]}" install -m644 "$src/garageyard.service" "$unit/"
"${root[@]}" systemctl daemon-reload
"${root[@]}" /usr/local/bin/garageyard setup
echo 'Управление: sudo garageyard'
