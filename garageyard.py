#!/usr/bin/env python3
import configparser
import getpass
import grp
import hashlib
import ipaddress
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CONFIG = Path("/etc/garageyard/server.ini")
UNIT = "garageyard.service"
MAPS = {
    "Стройка": "/Game/Construction/ConstructionSite",
    "Автопарк № 7": "/Game/MotorDepot/MotorDepot",
    "Химлаборатория": "/Game/ChemicalLab/ChemicalLab",
}


def choose(title, items):
    while True:
        print(title)
        for n, item in enumerate(items, 1):
            print(f"  {n}. {item}")
        answer = input("> ").strip()
        if answer.isdecimal() and 1 <= int(answer) <= len(items):
            return items[int(answer) - 1]


def name():
    while True:
        value = input("Название сервера (1–32 символа): ").strip()
        if 1 <= len(value) <= 32 and value.isprintable() and not any(c in value for c in '|;"[]=\\'):
            return value
        print("Введите название без служебных символов INI.")


def access(settings):
    private = choose("Доступ в лобби", ["Открытое", "По паролю"]) == "По паролю"
    key = ""
    if private:
        while True:
            password = getpass.getpass("Пароль: ")
            if password and password == getpass.getpass("Повторите пароль: "):
                break
            print("Введите одинаковый непустой пароль.")
        key = hashlib.pbkdf2_hmac("sha256", password.encode(), b"GarageYard/lobby/v1", 200000).hex()
    settings.update(Private=str(private), LobbyKey=key)


def directory():
    while True:
        value = input("IPv4:порт общего каталога (Enter — только локальная сеть): ").strip()
        if not value:
            return ""
        host, _, port = value.partition(":")
        try:
            address = ipaddress.IPv4Address(host)
            port = int(port or 14080)
            if 1 <= port <= 65535:
                return f"{address}:{port}"
        except ValueError:
            pass
        print("Например, 192.168.1.10:14080")


def write(settings):
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config["GarageServers"] = settings
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=CONFIG.parent, delete=False) as out:
        config.write(out, space_around_delimiters=False)
        os.fchown(out.fileno(), 0, grp.getgrnam("garageyard").gr_gid)
        os.fchmod(out.fileno(), 0o640)
        out.flush()
        os.fsync(out.fileno())
    os.replace(out.name, CONFIG)


def read():
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    with CONFIG.open(encoding="utf-8") as file:
        config.read_file(file)
    return dict(config["GarageServers"])


def service(*args):
    subprocess.run(["systemctl", *args, UNIT], check=True)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "menu"
    if command == "run":
        settings = read()
        root = Path("/etc/garageyard/package").read_text().strip()
        os.execv("/bin/bash", ["bash", str(Path(root) / "GarageYardServer.sh"), settings["Map"],
                "-unattended", "-nosound", "-nullrhi", "-port=7777", "-YardQueryPort=14079",
                f"-YardConfig={CONFIG}", "-UserDir=/var/lib/garageyard", "-stdout"])
    if os.geteuid() != 0:
        sys.exit("Запустите управление через sudo garageyard.")
    if command == "setup":
        if not CONFIG.exists():
            settings = {"Map": MAPS[choose("Карта", list(MAPS))], "ServerName": name()}
            access(settings)
            settings["Hidden"] = str(choose("Показывать сервер в списке?", ["Да", "Нет"]) == "Нет")
            settings["DirectoryEndpoint"] = directory()
            write(settings)
        service("enable", "--now")
        return
    if command != "menu":
        sys.exit("Используйте garageyard без аргументов для управления.")
    while True:
        settings = read()
        running = subprocess.run(["systemctl", "is-active", "--quiet", UNIT]).returncode == 0
        state = "работает" if running else "остановлен"
        print(f"\n{settings['ServerName']} · {settings['Map'].split('/')[-1]} · {state}")
        action = choose("Управление", ["Запустить", "Выключить", "Сменить карту", "Открыть / установить пароль",
                        "Скрыть / показать", "Переименовать", "Адрес каталога", "Выйти"])
        if action == "Выйти":
            return
        if action == "Запустить":
            service("enable", "--now")
        elif action == "Выключить":
            service("disable", "--now")
        elif action == "Сменить карту":
            settings["Map"] = MAPS[choose("Новая карта (текущий матч завершится)", list(MAPS))]
            write(settings)
            if running:
                service("restart")
        else:
            if action == "Открыть / установить пароль":
                access(settings)
            elif action == "Скрыть / показать":
                settings["Hidden"] = str(choose("Видимость", ["Показывать", "Скрыть"]) == "Скрыть")
            elif action == "Переименовать":
                settings["ServerName"] = name()
            elif action == "Адрес каталога":
                settings["DirectoryEndpoint"] = directory()
            write(settings)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        sys.exit(1)
