#!/usr/bin/env python3
"""UDP rendezvous for GarageYard. Only observed source endpoints are listed."""
import argparse
import hashlib
import hmac
import secrets
import socket
import time

SIZE = 256
TTL = 35
LIMIT = 512


class Directory:
    def __init__(self):
        self.key = secrets.token_bytes(32)
        self.live = {}

    def cookie(self, peer, bucket):
        data = f"{peer[0]}:{peer[1]}/{bucket}".encode("ascii")
        return hmac.new(self.key, data, hashlib.sha256).hexdigest()[:32]

    def handle(self, packet, peer, now):
        if len(packet) != SIZE or packet[-1] != 0:
            return None
        fields = packet.split(b"\0", 1)[0].decode("ascii", "replace").split("|")
        if fields[:1] != ["GYDIR1"]:
            return None
        args = fields[1:]
        bucket = int(now // 15)
        if args == ["HELLO"]:
            reply = f"COOKIE|{self.cookie(peer, bucket)}"
        elif len(args) == 2 and args[0] == "REGISTER":
            if any(hmac.compare_digest(args[1].encode(), self.cookie(peer, b).encode())
                   for b in (bucket, bucket - 1)):
                if peer in self.live or len(self.live) < LIMIT:
                    self.live[peer] = now + TTL
            return None
        elif args == ["BYE"]:
            self.live.pop(peer, None)
            return None
        elif len(args) == 3 and args[0] == "LIST":
            nonce, cursor = args[1:]
            if len(nonce) != 32 or any(c not in "0123456789ABCDEFabcdef" for c in nonce):
                return None
            if not cursor.isdecimal() or len(cursor) > 3:
                return None
            offset = int(cursor)
            hosts = sorted(p for p, until in self.live.items() if until > now)
            page = hosts[offset:offset + 8]
            following = offset + len(page)
            entries = ",".join(f"{ip}:{port}" for ip, port in page)
            reply = f"PAGE|{nonce}|{offset}|{following if following < len(hosts) else -1}|{entries}"
        else:
            return None
        return ("GYDIR1|" + reply).encode("ascii").ljust(SIZE, b"\0")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=14080)
    args = parser.parse_args()
    directory = Directory()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("", args.port))
        cleanup = 0
        while True:
            data, peer = sock.recvfrom(SIZE + 1)
            now = time.monotonic()
            if now >= cleanup:
                directory.live = {p: t for p, t in directory.live.items() if t > now}
                cleanup = now + 5
            response = directory.handle(data, peer, now)
            if response:
                try:
                    sock.sendto(response, peer)
                except OSError:
                    pass


if __name__ == "__main__":
    main()
