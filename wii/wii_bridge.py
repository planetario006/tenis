#!/usr/bin/env python3
"""
wii_bridge.py — Wii Remote Plus (MotionPlus integrado) -> UDP/JSON hacia el juego de Godot.

Uso (dentro de WSL, después de los pasos usbipd / bluetooth que ya conoces):

    python3 wii_bridge.py axes            # calibración guiada de ejes -> escribe wii_config.json
    python3 wii_bridge.py stream          # envía datos a Godot (por defecto)
    python3 wii_bridge.py fake            # simula un mando (sin hardware) para probar el juego

Gestos: levantar el mando (morro arriba) lanza la pelota del saque; el golpe se distingue por botones
(ninguno=topspin, A=plano, B=cortado, A+B=globo/dejada) y la dirección por el barrido lateral del gesto
(recto = paralelo, cruzado = cruzado). El botón + activa/desactiva el movimiento automático.

Opciones útiles:
    --addr AA:BB:CC:DD:EE:FF   salta el escaneo (si ya conoces la MAC)
    --host IP                  destino UDP (por defecto: auto; en WSL2 = IP de Windows)
    --port 9876                puerto UDP (debe coincidir con wii_config.json)
    --signs 1,1,1              signos de (cabeceo, alabeo, guiñada) del giroscopio

Paquete enviado a ~100 Hz:  {"t": s, "a": [ax,ay,az] (g), "g": [pitch, roll, yaw] (°/s), "b": máscara}
Máscara de botones: A=1 B=2 UNO=4 DOS=8 MAS=16 MENOS=32 HOME=64 ARRIBA=128 ABAJO=256 IZQ=512 DER=1024

NOTA: protocolo implementado desde la especificación pública de Wii Remote / MotionPlus. Para
encontrar el mando pulsa 1+2 (luces parpadeando) antes de lanzar `stream` o `axes`.
"""
import argparse
import json
import math
import os
import re
import socket
import subprocess
import sys
import time

BTN_NAMES = ["A", "B", "UNO", "DOS", "MAS", "MENOS", "HOME", "ARRIBA", "ABAJO", "IZQ", "DER"]


def default_host():
    """En WSL2 (NAT) Godot en Windows se alcanza por la puerta de enlace; con red 'mirrored' vale 127.0.0.1."""
    try:
        if "microsoft" in open("/proc/version").read().lower():
            out = subprocess.run(["ip", "route"], capture_output=True, text=True).stdout
            m = re.search(r"default via (\d+\.\d+\.\d+\.\d+)", out)
            if m:
                return m.group(1)
    except Exception:
        pass
    return "127.0.0.1"


def check_bluetooth(hci="hci0"):
    try:
        out = subprocess.run(["hciconfig", hci], capture_output=True, text=True).stdout
    except FileNotFoundError:
        print("! hciconfig no está instalado (sudo apt install bluez)")
        return False
    ok = "UP RUNNING" in out
    print(("✓ " if ok else "✗ ") + f"{hci}: " + ("UP RUNNING" if ok else "no está UP RUNNING -> sudo service bluetooth start; sudo hciconfig hci0 up"))
    return ok


def scan_for_wiimote(timeout=12):
    print("Pulsa 1+2 en el mando (las luces parpadean)... buscando.")
    out = subprocess.run(["hcitool", "scan", "--flush", "--length=%d" % max(4, timeout // 1)], capture_output=True, text=True).stdout
    for line in out.splitlines():
        m = re.search(r"([0-9A-F]{2}(?::[0-9A-F]{2}){5})\s+(.*)", line.strip(), re.I)
        if m and ("nintendo" in m.group(2).lower() or "rvl" in m.group(2).lower()):
            print("Encontrado:", m.group(1), m.group(2))
            return m.group(1)
    return None


class Wiimote:
    """Conexión L2CAP cruda (PSM 0x11 control, 0x13 interrupción) sin dependencias externas."""

    def __init__(self, addr):
        self.addr = addr
        self.ctl = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
        self.intr = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
        self.ctl.connect((addr, 0x11))
        self.intr.connect((addr, 0x13))
        self.intr.settimeout(0.5)
        self.cal_zero = (128, 128, 128)
        self.cal_one = (153, 153, 153)
        self.gyro_bias = [0.0, 0.0, 0.0]

    def send(self, rid, *data):
        self.intr.send(bytes([0xA2, rid]) + bytes(data))

    def leds(self, mask):
        self.send(0x11, (mask & 0xF) << 4)

    def write_mem(self, addr, data):
        data = bytes(data)
        pad = data + b"\x00" * (16 - len(data))
        self.send(0x16, 0x04, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, len(data), *pad)
        time.sleep(0.05)

    def read_mem(self, addr, size, eeprom=False, timeout=1.0):
        self.send(0x17, 0x00 if eeprom else 0x04, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, (size >> 8) & 0xFF, size & 0xFF)
        buf = b""
        t0 = time.time()
        while time.time() - t0 < timeout and len(buf) < size:
            try:
                pkt = self.intr.recv(64)
            except socket.timeout:
                continue
            if len(pkt) > 7 and pkt[1] == 0x21:
                n = (pkt[4] >> 4) + 1
                buf += pkt[7:7 + n]
        return buf[:size]

    def init(self):
        self.leds(0x1)
        cal = self.read_mem(0x0016, 7, eeprom=True)
        if len(cal) >= 7 and cal[0] and cal[4] > cal[0]:
            self.cal_zero = (cal[0], cal[1], cal[2])
            self.cal_one = (cal[4], cal[5], cal[6])
        # Activar el MotionPlus integrado (Wii Remote Plus): escribir 0x04 en 0xA600FE
        self.write_mem(0xA600FE, b"\x04")
        time.sleep(0.15)
        self.send(0x12, 0x04, 0x35)           # botones + acelerómetro + 16 bytes de extensión, continuo
        time.sleep(0.1)
        self.leds(0x9)

    @staticmethod
    def _buttons(b1, b2):
        m = 0
        if b2 & 0x08: m |= 1        # A
        if b2 & 0x04: m |= 2        # B
        if b2 & 0x02: m |= 4        # 1
        if b2 & 0x01: m |= 8        # 2
        if b1 & 0x10: m |= 16       # +
        if b2 & 0x10: m |= 32       # -
        if b2 & 0x80: m |= 64       # HOME
        if b1 & 0x08: m |= 128      # arriba
        if b1 & 0x04: m |= 256      # abajo
        if b1 & 0x01: m |= 512      # izquierda
        if b1 & 0x02: m |= 1024     # derecha
        return m

    def read(self):
        """Devuelve (mask, acc_g, gyro_raw_dps(pitch,roll,yaw)) o None si el paquete no es 0x35."""
        try:
            pkt = self.intr.recv(64)
        except socket.timeout:
            return None
        if len(pkt) < 23 or pkt[1] != 0x35:
            return None
        b1, b2 = pkt[2], pkt[3]
        raw = (pkt[4], pkt[5], pkt[6])
        acc = tuple((raw[i] - self.cal_zero[i]) / max(1.0, float(self.cal_one[i] - self.cal_zero[i])) for i in range(3))
        e = pkt[7:13]
        yaw = ((e[3] & 0xFC) << 6) | e[0]
        roll = ((e[4] & 0xFC) << 6) | e[1]
        pitch = ((e[5] & 0xFC) << 6) | e[2]
        yaw_slow, pitch_slow, roll_slow = bool(e[3] & 2), bool(e[3] & 1), bool(e[4] & 2)

        def rate(v, slow):
            return (v - 8192) * ((440.0 if slow else 2000.0) / 8192.0)

        g = (rate(pitch, pitch_slow), rate(roll, roll_slow), rate(yaw, yaw_slow))
        return self._buttons(b1, b2), acc, g

    def calibrate_gyro(self, seconds=2.0):
        print(f"Calibrando giroscopio {seconds:.0f} s: deja el mando QUIETO sobre la mesa...")
        acc = [0.0, 0.0, 0.0]
        n = 0
        t0 = time.time()
        while time.time() - t0 < seconds:
            r = self.read()
            if r:
                for i in range(3):
                    acc[i] += r[2][i]
                n += 1
        if n:
            self.gyro_bias = [a / n for a in acc]
        print("sesgo (°/s):", [round(b, 2) for b in self.gyro_bias])

    def close(self):
        for s in (self.intr, self.ctl):
            try:
                s.close()
            except Exception:
                pass


def connect(args):
    check_bluetooth(args.hci)
    addr = args.addr or scan_for_wiimote()
    if not addr:
        sys.exit("No se encontró ningún mando. Pulsa 1+2 y reintenta (o usa --addr).")
    print("Conectando a", addr, "...")
    wm = Wiimote(addr)
    wm.init()
    wm.calibrate_gyro(args.cal_seconds)
    return wm


def signs(args):
    return [float(x) for x in args.signs.split(",")]


def run_stream(args):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    host = args.host or default_host()
    print(f"Enviando a {host}:{args.port}  (Ctrl+C para salir)")
    sg = signs(args)
    wm = connect(args)
    t_start = time.time()
    last_print = 0
    try:
        while True:
            r = wm.read()
            if not r:
                continue
            mask, acc, g = r
            gx = [sg[i] * (g[i] - wm.gyro_bias[i]) for i in range(3)]
            pkt = {"t": round(time.time() - t_start, 4), "a": [round(v, 3) for v in acc], "g": [round(v, 1) for v in gx], "b": mask}
            sock.sendto(json.dumps(pkt, separators=(",", ":")).encode(), (host, args.port))
            if time.time() - last_print > 1.0:
                last_print = time.time()
                print("\r|g|=%6.0f °/s  acc=(%.2f,%.2f,%.2f)  botones=%s   " % (math.sqrt(sum(v * v for v in gx)), *acc, [n for i, n in enumerate(BTN_NAMES) if mask >> i & 1]), end="")
    except KeyboardInterrupt:
        pass
    finally:
        wm.close()


def run_axes(args):
    """Calibración guiada: averigua qué eje del giroscopio es cabeceo / guiñada y su signo."""
    sg = signs(args)
    wm = connect(args)

    def measure(prompt, seconds=3.0):
        input(f"\n{prompt}\n   (pulsa ENTER y haz el movimiento durante {seconds:.0f} s) ")
        peak = [0.0, 0.0, 0.0]
        t0 = time.time()
        while time.time() - t0 < seconds:
            r = wm.read()
            if not r:
                continue
            g = [sg[i] * (r[2][i] - wm.gyro_bias[i]) for i in range(3)]
            for i in range(3):
                if abs(g[i]) > abs(peak[i]):
                    peak[i] = g[i]
        axis = max(range(3), key=lambda i: abs(peak[i]))
        print("   picos (cabeceo, alabeo, guiñada) =", [round(p) for p in peak], "-> eje dominante", axis)
        return axis, (1.0 if peak[axis] > 0 else -1.0)

    print("\nSujeta el mando como una raqueta (botones hacia arriba, apuntando al frente).")
    ya, ys = measure("1) GUIÑADA: gira el mando a la IZQUIERDA como un volante plano (apunta más a la izquierda)")
    pa, ps = measure("2) CABECEO: levanta el MORRO del mando hacia arriba y bájalo")
    cfg = {"port": args.port, "yaw_axis": ya, "yaw_sign": ys, "pitch_axis": pa, "pitch_sign": ps}
    print("\nConfiguración sugerida (se fusiona con wii/wii_config.json):", cfg)
    if args.out:
        base = {}
        if os.path.exists(args.out):
            base = json.load(open(args.out))
        base.update(cfg)
        json.dump(base, open(args.out, "w"), indent=2)
        print("Guardado en", args.out)
    print("Nota: 'yaw_sign' positivo = apuntar a la izquierda aumenta la guiñada; si en el juego la cruz va al revés, invierte yaw_sign.")
    wm.close()


def run_fake(args):
    """Simula un mando (sin hardware). Ciclo: gesto de lanzar (morro arriba), golpe cruzado con A,
    golpe recto sin botón, golpe cruzado con B... Útil para probar el juego."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    host = args.host or "127.0.0.1"
    print(f"[fake] enviando a {host}:{args.port}")
    t0 = time.time()
    patterns = [  # (nombre, gyro por eje [cabeceo, alabeo, guiñada] como fracción del pico, botones)
        ("lanzar", (1.0, 0.0, 0.0), 0),
        ("cruzado+A", (0.3, 0.1, 0.9), 1),
        ("recto", (-0.8, 0.0, 0.1), 0),
        ("cruzado+B", (0.3, 0.1, 0.9), 2),
    ]
    n = 0
    next_swing = t0 + 2.0
    swing_start = None
    peak = 900.0
    mask = 0
    vec = (0, 0, 0)
    while True:
        now = time.time()
        g = [0.0, 0.0, 0.0]
        if swing_start is None and now >= next_swing:
            swing_start = now
            name, vec, mask = patterns[n % len(patterns)]
            peak = 700.0 + 700.0 * ((n * 0.37) % 1.0)
            print("[fake] gesto:", name)
            n += 1
        if swing_start is not None:
            u = now - swing_start
            if u < 0.28:
                amp = peak * math.sin(math.pi * u / 0.28)
                g = [vec[0] * amp, vec[1] * amp, vec[2] * amp]
            else:
                swing_start = None
                next_swing = now + 1.6
                mask = 0
        pkt = {"t": round(now - t0, 4), "a": [0.0, 0.1, 1.0], "g": g, "b": mask}
        sock.sendto(json.dumps(pkt, separators=(",", ":")).encode(), (host, args.port))
        time.sleep(0.01)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", nargs="?", default="stream", choices=["stream", "axes", "fake"])
    ap.add_argument("--addr")
    ap.add_argument("--host")
    ap.add_argument("--port", type=int, default=9876)
    ap.add_argument("--hci", default="hci0")
    ap.add_argument("--signs", default="1,1,1")
    ap.add_argument("--cal-seconds", type=float, default=2.0)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "wii_config.json"))
    args = ap.parse_args()
    {"stream": run_stream, "axes": run_axes, "fake": run_fake}[args.mode](args)


if __name__ == "__main__":
    main()
