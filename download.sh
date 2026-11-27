# Shared by the game installer and updater. Keep the .aria2 control file next to
# the payload so aria2 can resume non-contiguous pieces after an interruption.
download_asset() {
    local url=$1 target=$2 expected=$3
    local dir name actual
    dir=$(dirname -- "$target")
    name=$(basename -- "$target")
    mkdir -p -m700 -- "$dir"

    if [[ -f $target && ! -e $target.aria2 ]]; then
        actual=$(sha256sum <"$target")
        if [[ ${actual%% *} == "$expected" ]]; then return 0; fi
        rm -- "$target"
    fi
    if ! command -v aria2c >/dev/null; then
        local elevate=()
        if (( EUID != 0 )); then elevate=(sudo); fi
        if ! "${elevate[@]}" apt-get install -y aria2; then
            "${elevate[@]}" apt-get update
            "${elevate[@]}" apt-get install -y aria2
        fi
    fi
    echo "Скачивание $name, до 8 одновременных соединений."
    aria2c --no-conf --continue=true --max-connection-per-server=8 --split=8 \
        --min-split-size=4M --auto-save-interval=1 --file-allocation=none \
        --auto-file-renaming=false --max-tries=5 --retry-wait=2 \
        --console-log-level=warn --summary-interval=5 \
        --dir="$dir" --out="$name" "$url"
    if [[ -e $target.aria2 ]]; then
        echo "Загрузка $name прервана. Повторите команду для продолжения." >&2
        return 1
    fi
    actual=$(sha256sum <"$target")
    if [[ ${actual%% *} != "$expected" ]]; then
        rm -f -- "$target" "$target.aria2"
        echo "Ошибка SHA-256 файла $name. Повторите команду для новой загрузки." >&2
        return 1
    fi
}
