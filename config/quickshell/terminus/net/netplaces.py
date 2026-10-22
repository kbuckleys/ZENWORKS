#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# NETPLACES — terminus' network places, through GIO (gvfs does the work).
#
#   netplaces.py list                    the network mounts there are now
#   netplaces.py mount URI [--user U] [--domain D] [--remember] [--accept]
#                                        the password, if any, on stdin
#   netplaces.py unmount URI
#
# One JSON object on stdout. A mount answers {"ok": true, "path": …} — path
# is gvfs' FUSE directory, where terminus browses it — or {"ok": false,
# "why": "auth" | "question" | "missing" | "error", "message": …}.
#
# The password never rides on argv (ps shows argv). --remember hands it to
# gvfs to keep in the Secret Service, so the next mount needs none. A
# question gvfs asks (an unknown SSH host key) is not answered here: it is
# handed back, and --accept says yes to it once the user has.

import json
import sys

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except Exception as e:  # no PyGObject
    print(json.dumps({"ok": False, "why": "missing", "message": str(e)}))
    sys.exit(0)


def say(obj):
    print(json.dumps(obj))
    sys.stdout.flush()


def listing():
    rows = []
    for m in Gio.VolumeMonitor.get().get_mounts():
        root = m.get_root()
        scheme = root.get_uri_scheme() or ""
        # local disks are lsblk's (the sidebar's Disks); phones, cameras and
        # the like are not places on a network
        if scheme in ("file", "mtp", "gphoto2", "afc", "burn", "cdda", "trash", "recent"):
            continue
        rows.append({"uri": root.get_uri(), "name": m.get_name(), "path": root.get_path() or "",
                     "scheme": scheme})
    say({"ok": True, "mounts": rows})


def has_backend(uri):
    scheme = GLib.Uri.peek_scheme(uri) or ""
    return scheme in Gio.Vfs.get_default().get_supported_uri_schemes()


def mount(uri, user, domain, password, remember, accept):
    if not has_backend(uri):
        say({"ok": False, "why": "missing", "message": "No gvfs backend for " + (GLib.Uri.peek_scheme(uri) or uri)})
        return
    f = Gio.File.new_for_uri(uri)
    op = Gio.MountOperation()
    loop = GLib.MainLoop()
    state = {"asked": 0, "result": None}

    def ask_password(op, message, default_user, default_domain, flags):
        state["asked"] += 1
        # asked again: what was given was refused
        if state["asked"] > 1:
            state["result"] = {"ok": False, "why": "auth", "message": message}
            op.reply(Gio.MountOperationResult.ABORTED)
            return
        if not user and not password and (flags & Gio.AskPasswordFlags.ANONYMOUS_SUPPORTED):
            op.set_anonymous(True)
        else:
            if flags & Gio.AskPasswordFlags.NEED_USERNAME:
                op.set_username(user or default_user or GLib.get_user_name())
            if flags & Gio.AskPasswordFlags.NEED_DOMAIN:
                op.set_domain(domain or default_domain or "")
            if flags & Gio.AskPasswordFlags.NEED_PASSWORD:
                if not password:
                    state["result"] = {"ok": False, "why": "auth", "message": message}
                    op.reply(Gio.MountOperationResult.ABORTED)
                    return
                op.set_password(password)
            op.set_password_save(Gio.PasswordSave.PERMANENTLY if remember else Gio.PasswordSave.NEVER)
        op.reply(Gio.MountOperationResult.HANDLED)

    def ask_question(op, message, choices):
        if accept:
            op.set_choice(0)
            op.reply(Gio.MountOperationResult.HANDLED)
            return
        state["result"] = {"ok": False, "why": "question", "message": message, "choices": list(choices)}
        op.reply(Gio.MountOperationResult.ABORTED)

    op.connect("ask-password", ask_password)
    op.connect("ask-question", ask_question)

    def done(f, res):
        try:
            f.mount_enclosing_volume_finish(res)
            state["result"] = {"ok": True, "path": f.get_path() or ""}
        except GLib.Error as e:
            if e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
                state["result"] = {"ok": True, "path": f.get_path() or ""}
            elif state["result"] is None:
                why = "auth" if e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.PERMISSION_DENIED) else "error"
                state["result"] = {"ok": False, "why": why, "message": e.message}
        loop.quit()

    f.mount_enclosing_volume(Gio.MountMountFlags.NONE, op, None, done)
    GLib.timeout_add_seconds(60, lambda: (state.__setitem__("result", state["result"] or
        {"ok": False, "why": "error", "message": "The server did not answer"}), loop.quit()))
    loop.run()
    say(state["result"])


def unmount(uri):
    f = Gio.File.new_for_uri(uri)
    try:
        m = f.find_enclosing_mount(None)
    except GLib.Error:
        say({"ok": True})
        return
    loop = GLib.MainLoop()
    state = {"result": None}

    def done(m, res):
        try:
            m.unmount_with_operation_finish(res)
            state["result"] = {"ok": True}
        except GLib.Error as e:
            state["result"] = {"ok": False, "why": "error", "message": e.message}
        loop.quit()

    m.unmount_with_operation(Gio.MountUnmountFlags.NONE, None, None, done)
    loop.run()
    say(state["result"])


def main(argv):
    if len(argv) < 2:
        say({"ok": False, "why": "error", "message": "usage: list | mount URI | unmount URI"})
        return
    cmd = argv[1]
    if cmd == "list":
        listing()
    elif cmd == "mount" and len(argv) > 2:
        args = argv[3:]
        opt = lambda k: args[args.index(k) + 1] if k in args and args.index(k) + 1 < len(args) else ""
        password = sys.stdin.readline().rstrip("\n") if not sys.stdin.isatty() else ""
        mount(argv[2], opt("--user"), opt("--domain"), password, "--remember" in args, "--accept" in args)
    elif cmd == "unmount" and len(argv) > 2:
        unmount(argv[2])
    else:
        say({"ok": False, "why": "error", "message": "unknown: " + cmd})


if __name__ == "__main__":
    main(sys.argv)
