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
if [[ ! -f "$dest/game/GarageYardServer.sh" ]]; then
    "${root[@]}" install -d -m755 "$dest"
    stage=$("${root[@]}" mktemp -d "$dest/.install-XXXXXXXX")
    trap '"${root[@]}" rm -rf -- "$stage"' EXIT
    "${root[@]}" chown "$(id -u):$(id -g)" "$stage"
    archive=${GARAGEYARD_ARCHIVE:-}
    if [[ -z $archive ]]; then
        if ! gh release download --repo "$repo" --pattern GarageYard-LinuxServer.tar.gz --pattern SHA256SUMS --dir "$stage"; then
            echo 'Нужен релиз LinuxServer с архивом и SHA256SUMS либо локальный GARAGEYARD_ARCHIVE.' >&2
            exit 1
        fi
        archive="$stage/GarageYard-LinuxServer.tar.gz"
        (cd "$stage" && sha256sum -c --strict SHA256SUMS)
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
        if member.isfile():
            (root / member.name).chmod(0o755 if member.mode & 0o111 else 0o644)
PY
    test -f "$stage/game/GarageYardServer.sh"
    test -d "$stage/game/GarageYard/Content/Paks"
    "${root[@]}" mv -T "$stage/game" "$dest/game"
fi
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
