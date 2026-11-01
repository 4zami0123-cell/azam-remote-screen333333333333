"""Azam Share - Windows screen sharing server. Your iPhone connects directly to this PC."""
import asyncio, ctypes, io, json, os, secrets, socket, sys, threading, time, ipaddress
from urllib.parse import urlparse, parse_qs

import mss
from PIL import Image, ImageDraw, ImageTk
import qrcode, psutil
from websockets.asyncio.server import serve
import tkinter as tk
from tkinter import ttk

APP = "Azam Share"
CFG_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "AzamShare")
CFG_PATH = os.path.join(CFG_DIR, "config.json")
QUALITY = {"low": (960, 50), "medium": (1280, 62), "high": (1920, 75)}


# ---------- config ----------
def load_cfg():
    cfg = {"port": 8765, "token": secrets.token_hex(16), "monitor": 1, "quality": "medium", "fps": 15}
    try:
        with open(CFG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except Exception:
        pass
    save_cfg(cfg)
    return cfg


def save_cfg(cfg):
    os.makedirs(CFG_DIR, exist_ok=True)
    with open(CFG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


def local_ips():
    """Home network addresses first, then Tailscale (100.64.0.0/10)."""
    lan, ts = [], []
    cgnat = ipaddress.ip_network("100.64.0.0/10")
    for addrs in psutil.net_if_addrs().values():
        for a in addrs:
            if a.family != socket.AF_INET:
                continue
            ip = ipaddress.ip_address(a.address)
            if ip.is_loopback or ip.is_link_local:
                continue
            (ts if ip in cgnat else lan).append(a.address)
    return lan, ts


# ---------- capture ----------
def cursor_pos():
    if sys.platform != "win32":
        return None

    class P(ctypes.Structure):
        _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

    p = P()
    ctypes.windll.user32.GetCursorPos(ctypes.byref(p))
    return p.x, p.y


class Capturer:
    def __init__(self, cfg):
        self.cfg = cfg

    def monitors(self):
        with mss.mss() as s:
            return s.monitors[1:]

    def grab(self, sct):
        mons = sct.monitors
        idx = self.cfg["monitor"] if 1 <= self.cfg["monitor"] < len(mons) else 1
        m = mons[idx]
        raw = sct.grab(m)
        img = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")
        cp = cursor_pos()
        if cp and m["left"] <= cp[0] < m["left"] + m["width"] and m["top"] <= cp[1] < m["top"] + m["height"]:
            x, y = cp[0] - m["left"], cp[1] - m["top"]
            r = max(6, img.width // 220)
            ImageDraw.Draw(img).ellipse([x - r, y - r, x + r, y + r], fill=(242, 181, 68), outline=(0, 0, 0), width=2)
        maxw, q = QUALITY.get(self.cfg["quality"], QUALITY["medium"])
        if img.width > maxw:
            img = img.resize((maxw, round(img.height * maxw / img.width)), Image.BILINEAR)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q)
        return buf.getvalue()


# ---------- server ----------
class Server:
    def __init__(self, cfg):
        self.cfg, self.cap = cfg, Capturer(cfg)
        self.clients = 0
        self.frame, self.seq = None, 0
        self.cond = None
        self.error = None

    def start(self):
        threading.Thread(target=lambda: asyncio.run(self._main()), daemon=True).start()

    async def _main(self):
        self.cond = asyncio.Condition()
        try:
            async with serve(self._handler, "0.0.0.0", self.cfg["port"],
                             max_size=2 ** 16, ping_interval=10, ping_timeout=20):
                await self._producer()
        except OSError as e:
            self.error = str(e)

    async def _producer(self):
        sct = mss.mss()
        while True:
            if self.clients == 0:  # capture only while someone is watching
                await asyncio.sleep(0.25)
                continue
            t0 = time.perf_counter()
            try:
                data = await asyncio.to_thread(self.cap.grab, sct)
            except Exception:  # lock screen, UAC prompt, display change
                sct = mss.mss()
                await asyncio.sleep(0.5)
                continue
            async with self.cond:
                self.frame, self.seq = data, self.seq + 1
                self.cond.notify_all()
            await asyncio.sleep(max(0, 1 / self.cfg["fps"] - (time.perf_counter() - t0)))

    async def _handler(self, ws):
        token = parse_qs(urlparse(ws.request.path).query).get("token", [""])[0]
        if not secrets.compare_digest(token, self.cfg["token"]):
            await ws.close(4001, "bad token")
            return
        self.clients += 1
        last = self.seq
        try:
            await ws.send(json.dumps({"name": socket.gethostname()}))
            while True:
                async with self.cond:
                    await self.cond.wait_for(lambda: self.seq != last)
                    data, last = self.frame, self.seq
                await ws.send(data)  # a slow phone simply skips frames
        except Exception:
            pass
        finally:
            self.clients -= 1

    def pair_payload(self):
        lan, ts = local_ips()
        info = {"name": socket.gethostname(), "hosts": lan + ts, "port": self.cfg["port"], "token": self.cfg["token"]}
        return "AZAMSHARE:" + json.dumps(info, separators=(",", ":"))


# ---------- UI ----------
BG, PANEL, LINE, TEXT, MUTED, AMBER, RED = "#1A1426", "#261D36", "#3A2E4F", "#F3EEF8", "#A99BD1", "#F2B544", "#E86A7A"


def resource(name):
    return os.path.join(getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__))), name)


class App:
    def __init__(self):
        self.cfg = load_cfg()
        self.srv = Server(self.cfg)
        self.srv.start()
        self.root = r = tk.Tk()
        r.title(APP)
        r.configure(bg=BG)
        r.geometry("440x740")
        r.minsize(400, 660)
        try:
            r.iconbitmap(resource("icon.ico"))
        except Exception:
            pass
        f = ("Segoe UI", 10)
        tk.Label(r, text=APP, bg=BG, fg=TEXT, font=("Segoe UI Semibold", 18)).pack(pady=(18, 0))
        tk.Label(r, text="صوّر الكود من تطبيق Azam Share في الآيفون", bg=BG, fg=MUTED, font=f).pack()
        card = tk.Frame(r, bg="white", padx=10, pady=10)
        card.pack(pady=14)
        self.qr = tk.Label(card, bg="white")
        self.qr.pack()
        self.status = tk.Label(r, bg=BG, fg=MUTED, font=("Segoe UI Semibold", 11))
        self.status.pack()
        self.addr = tk.Label(r, bg=BG, fg=MUTED, font=("Segoe UI", 9), justify="center")
        self.addr.pack(pady=(4, 10))

        box = tk.Frame(r, bg=PANEL, padx=16, pady=12, highlightbackground=LINE, highlightthickness=1)
        box.pack(fill="x", padx=20)
        ttk.Style().theme_use("clam")

        def row(label, values, current, key, conv=str):
            fr = tk.Frame(box, bg=PANEL)
            fr.pack(fill="x", pady=4)
            tk.Label(fr, text=label, bg=PANEL, fg=TEXT, font=f).pack(side="right")
            var = tk.StringVar(value=str(current))
            cb = ttk.Combobox(fr, textvariable=var, values=values, state="readonly", width=16)
            cb.pack(side="left")

            def changed(_):
                self.cfg[key] = conv(var.get().split(" ")[0])
                save_cfg(self.cfg)

            cb.bind("<<ComboboxSelected>>", changed)

        mons = self.srv.cap.monitors()
        mvals = [f"{i + 1} ({m['width']}x{m['height']})" for i, m in enumerate(mons)]
        row("الشاشة", mvals, mvals[max(0, min(self.cfg["monitor"], len(mvals)) - 1)], "monitor", int)
        row("الجودة", ["low", "medium", "high"], self.cfg["quality"], "quality")
        row("الإطارات في الثانية", ["10", "15", "24", "30"], self.cfg["fps"], "fps", int)

        tk.Button(r, text="رمز جديد (يفصل كل الأجهزة المربوطة)", command=self.new_token, bg=PANEL, fg=TEXT,
                  activebackground=LINE, activeforeground=TEXT, relief="flat", font=f, padx=10, pady=6).pack(pady=14)
        tk.Label(r, text="made by azam", bg=BG, fg=LINE, font=("Segoe UI", 8)).pack(side="bottom", pady=6)
        self.last_payload = None
        self.tick()

    def new_token(self):
        self.cfg["token"] = secrets.token_hex(16)
        save_cfg(self.cfg)
        self.last_payload = None

    def tick(self):
        if self.srv.error:
            self.status.config(text=f"تعذّر تشغيل الخادم على المنفذ {self.cfg['port']}", fg=RED)
        else:
            n = self.srv.clients
            self.status.config(text=f"● يشاهد الآن: {n}" if n else "جاهز، بانتظار الجوال", fg=AMBER if n else MUTED)
        payload = self.srv.pair_payload()
        if payload != self.last_payload:  # network changed or new token
            self.last_payload = payload
            img = qrcode.make(payload, box_size=6, border=1).convert("RGB").resize((250, 250), Image.NEAREST)
            self.qr_img = ImageTk.PhotoImage(img)
            self.qr.config(image=self.qr_img)
            lan, ts = local_ips()
            lines = [f"البيت: {ip}" for ip in lan] + [f"من أي مكان (Tailscale): {ip}" for ip in ts]
            if not ts:
                lines.append("Tailscale مو شغّال: الاتصال من البيت بس")
            self.addr.config(text="\n".join(lines))
        self.root.after(1000, self.tick)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    if sys.platform == "win32":
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
        except Exception:
            pass
    App().run()
