#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# A HYPRLAND WINDOW'S TOPLEVEL IDENTIFIER, for `grim -T` — the window's own
# buffer, nothing behind it and nothing over it, rather than a crop of the
# screen.
#
#   toplevel.py ADDRESS     prints the identifier of the window hyprctl calls
#                           ADDRESS (0x5555f0a67ea0); exits 1 if none
#
# grim wants the ext-foreign-toplevel-list identifier, which hyprctl never
# shows. Hyprland's own toplevel-mapping protocol says which window each
# handle is, so: list the handles, ask for each one's address, print the one
# that matches. Plain Wayland wire protocol over the socket — no pywayland
# on this machine, and the handful of messages here do not need it.

import os
import socket
import struct
import sys


class Wire:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"],
                            os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(path)
        self.buf = b""
        self.last = 1

    def new(self):
        self.last += 1
        return self.last

    def send(self, obj, op, body=b""):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(body)) << 16) | op) + body)

    def events(self):
        while True:
            while len(self.buf) >= 8:
                obj, so = struct.unpack_from("<II", self.buf)
                size = so >> 16
                if len(self.buf) < size:
                    break
                yield obj, so & 0xFFFF, self.buf[8:size]
                self.buf = self.buf[size:]
            more = self.sock.recv(65536)
            if not more:
                return
            self.buf += more

    # everything sent so far answered: wl_display.sync, then read to its done
    def roundtrip(self, on):
        cb = self.new()
        self.send(1, 0, struct.pack("<I", cb))
        for obj, op, body in self.events():
            if obj == cb:
                return
            on(obj, op, body)


def wstr(text):
    b = text.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * ((4 - len(b) % 4) % 4)


def rstr(body, at=0):
    n = struct.unpack_from("<I", body, at)[0]
    return body[at + 4:at + 4 + n - 1].decode(errors="replace")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: toplevel.py ADDRESS")
    want = int(sys.argv[1], 16)
    w = Wire()

    registry = w.new()
    w.send(1, 1, struct.pack("<I", registry))
    globs = {}

    def on_global(obj, op, body):
        if obj == registry and op == 0:
            globs[rstr(body, 4)] = struct.unpack_from("<I", body)[0]
    w.roundtrip(on_global)

    def bind(iface):
        if iface not in globs:
            sys.exit(1)
        oid = w.new()
        w.send(registry, 0, struct.pack("<I", globs[iface]) + wstr(iface) + struct.pack("<II", 1, oid))
        return oid
    listing = bind("ext_foreign_toplevel_list_v1")
    mapper = bind("hyprland_toplevel_mapping_manager_v1")

    # the list sends every handle at once, each with its identifier
    ids, asks = {}, {}

    def on_event(obj, op, body):
        if obj == listing and op == 0:
            ids[struct.unpack_from("<I", body)[0]] = ""
        elif obj in ids and op == 4:
            ids[obj] = rstr(body)
        elif obj in asks and op == 0:
            hi, lo = struct.unpack_from("<II", body)
            if (hi << 32) | lo == want and ids.get(asks[obj]):
                print(ids[asks[obj]])
                sys.exit(0)
    w.roundtrip(on_event)
    for handle in list(ids):
        ask = w.new()
        asks[ask] = handle
        w.send(mapper, 0, struct.pack("<II", ask, handle))
    w.roundtrip(on_event)
    sys.exit(1)


if __name__ == "__main__":
    main()
