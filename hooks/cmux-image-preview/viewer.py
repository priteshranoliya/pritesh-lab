#!/usr/bin/env python3
"""Runs inside a cmux split. Tails a queue file of image paths and draws each one
with the kitty graphics protocol (supported by cmux / Ghostty)."""
import base64, fcntl, os, struct, subprocess, sys, tempfile, termios, time

queue = sys.argv[1]
out = sys.stdout.buffer
TMP = tempfile.mkdtemp(prefix="cmux-imgview-")


def winsize():
    try:
        rows, cols, xpx, ypx = struct.unpack("HHHH", fcntl.ioctl(1, termios.TIOCGWINSZ, b"\0" * 8))
    except OSError:
        rows, cols, xpx, ypx = 40, 100, 0, 0
    cw = xpx / cols if xpx else 8.0
    ch = ypx / rows if ypx else 16.0
    return rows, cols, cw, ch


def dims(p):
    r = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", p], capture_output=True, text=True)
    w = h = 0
    for line in r.stdout.splitlines():
        if "pixelWidth" in line:
            w = int(line.split()[-1])
        elif "pixelHeight" in line:
            h = int(line.split()[-1])
    return w, h


def as_png(p, w, h):
    """kitty f=100 needs PNG; also shrink huge images so the transfer stays fast."""
    if p.lower().endswith(".png") and max(w, h) <= 2400:
        return p
    dst = os.path.join(TMP, f"{time.time_ns()}.png")
    subprocess.run(["sips", "-s", "format", "png", "-Z", "2400", p, "--out", dst], capture_output=True)
    return dst


def show(p):
    if not os.path.isfile(p):
        return
    w, h = dims(p)
    if not w or not h:
        return
    rows, cols, cw, ch = winsize()
    max_c, max_r = max(cols - 1, 10), max(rows - 3, 5)
    scale = min(max_c * cw / w, max_r * ch / h, 1.0)
    c = max(1, round(w * scale / cw))
    r = max(1, round(h * scale / ch))

    stamp = time.strftime("%H:%M:%S")
    out.write(f"\n\x1b[2m{stamp}\x1b[0m \x1b[1m{os.path.basename(p)}\x1b[0m \x1b[2m{w}×{h}\x1b[0m\n".encode())
    out.write(f"\x1b[2m{p}\x1b[0m\n".encode())

    data = base64.standard_b64encode(open(as_png(p, w, h), "rb").read())
    first = True
    while data:
        chunk, data = data[:4096], data[4096:]
        ctl = f"a=T,f=100,q=2,c={c},r={r}," if first else ""
        out.write(b"\x1b_G" + ctl.encode() + b"m=" + (b"1" if data else b"0") + b";" + chunk + b"\x1b\\")
        first = False
    out.write(b"\n")
    out.flush()


def main():
    out.write(b"\x1b]2;Claude images\x07\x1b[2mWaiting for images from Claude...\x1b[0m\n")
    out.flush()
    pos = 0
    while True:
        try:
            with open(queue) as f:
                f.seek(pos)
                while True:
                    line = f.readline()
                    if not line.endswith("\n"):
                        break
                    pos = f.tell()
                    show(line.strip())
        except FileNotFoundError:
            pass
        except Exception as e:
            out.write(f"\x1b[31m{e}\x1b[0m\n".encode()); out.flush()
        time.sleep(0.3)


if __name__ == "__main__":
    main()
