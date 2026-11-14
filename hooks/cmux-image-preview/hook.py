#!/usr/bin/env python3
"""PostToolUse hook: show images Claude touches in a cmux split beside the Claude pane.

Picks up:
  - Read/Write of an image file
  - image paths mentioned in a Bash/MCP call or its output, if the file was modified recently
  - inline base64 images returned by MCP tools (saved to captures/)
Silent no-op outside cmux.
"""
import base64, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(HERE, "state")
CAPTURES = os.path.join(HERE, "captures")
EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".heic")
RECENT_SECS = 180
PATH_RE = re.compile(r"""(?:~|\.{0,2})?/[^\s'"`<>|;,()\[\]{}]+?\.(?:png|jpe?g|gif|webp|bmp|tiff|heic)\b""", re.I)


def cmux(*args):
    r = subprocess.run(["cmux", "--id-format", "uuids", *args], capture_output=True, text=True, timeout=10)
    return r.stdout


def is_image(p):
    return p.lower().endswith(EXTS)


def resolve(p, cwd):
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.realpath(p)


def walk_images(obj, out):
    """Find inline base64 image blocks in an MCP tool response."""
    if isinstance(obj, dict):
        if obj.get("type") == "image":
            data = obj.get("data") or (obj.get("source") or {}).get("data")
            if isinstance(data, str) and len(data) > 100:
                out.append(data)
                return
        for v in obj.values():
            walk_images(v, out)
    elif isinstance(obj, list):
        for v in obj:
            walk_images(v, out)


def collect(ev):
    tool = ev.get("tool_name", "")
    ti = ev.get("tool_input") or {}
    tr = ev.get("tool_response")
    cwd = ev.get("cwd") or os.getcwd()
    found = []

    if tool in ("Read", "Write"):
        fp = ti.get("file_path", "")
        if is_image(fp):
            found.append(resolve(fp, cwd))
        return found

    blobs = []
    walk_images(tr, blobs)
    if blobs:
        os.makedirs(CAPTURES, exist_ok=True)
        for i, b in enumerate(blobs):
            p = os.path.join(CAPTURES, f"{int(time.time()*1000)}-{i}.png")
            try:
                with open(p, "wb") as f:
                    f.write(base64.b64decode(b))
                found.append(p)
            except Exception:
                pass

    text = json.dumps(ti) + "\n" + (tr if isinstance(tr, str) else json.dumps(tr))
    now = time.time()
    for m in PATH_RE.findall(text.replace("\\/", "/")):
        p = resolve(m, cwd)
        try:
            if os.path.isfile(p) and now - os.path.getmtime(p) < RECENT_SECS:
                found.append(p)
        except OSError:
            pass
    return found


def ensure_viewer(state, queue):
    panels = cmux("list-panels")
    vid = state.get("viewer")
    if vid and vid in panels:
        return
    out = cmux("new-split", "right", "--surface", os.environ["CMUX_SURFACE_ID"], "--focus", "false")
    m = re.search(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", out, re.I)
    if not m:
        # fall back: the panel that wasn't there before
        after = cmux("list-panels")
        ids = set(re.findall(r"[0-9A-F]{8}-[0-9A-F-]{27}", after)) - set(re.findall(r"[0-9A-F]{8}-[0-9A-F-]{27}", panels))
        if not ids:
            return
        vid = ids.pop()
    else:
        vid = m.group(0)
    state["viewer"] = vid
    open(queue, "w").close()  # fresh viewer starts from an empty queue
    viewer = os.path.join(HERE, "viewer.py")
    cmux("send", "--surface", vid, f"clear; exec python3 '{viewer}' '{queue}'\n")


def main():
    if not os.environ.get("CMUX_SURFACE_ID"):
        return
    ev = json.load(sys.stdin)
    paths = collect(ev)
    if not paths:
        return

    os.makedirs(STATE_DIR, exist_ok=True)
    sid = os.environ["CMUX_SURFACE_ID"]
    state_f = os.path.join(STATE_DIR, f"{sid}.json")
    queue = os.path.join(STATE_DIR, f"{sid}.queue")
    try:
        state = json.load(open(state_f))
    except Exception:
        state = {}
    seen = state.setdefault("seen", {})

    new = []
    for p in dict.fromkeys(paths):
        key = f"{os.path.getmtime(p):.3f}"
        if seen.get(p) != key:
            seen[p] = key
            new.append(p)
    if not new:
        json.dump(state, open(state_f, "w"))
        return

    ensure_viewer(state, queue)
    with open(queue, "a") as f:
        for p in new:
            f.write(p + "\n")
    if len(seen) > 500:
        state["seen"] = dict(list(seen.items())[-200:])
    json.dump(state, open(state_f, "w"))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(os.path.join(STATE_DIR, "errors.log"), "a") as f:
            f.write(f"{time.ctime()} {type(e).__name__}: {e}\n")
