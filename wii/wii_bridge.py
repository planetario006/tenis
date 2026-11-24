#!/usr/bin/env python3
"""
wii_bridge.py — Wii Remote Plus (MotionPlus integrado) -> UDP/JSON hacia el juego de Godot.

Uso (dentro de WSL, después de los pasos usbipd / bluetooth):

    python3 wii_bridge.py calibrate       # UNA VEZ: calibra ejes del giroscopio agitando el mando (automático)
    python3 wii_bridge.py stream          # envía datos a Godot (por defecto)
    python3 wii_bridge.py fake            # simula un mando (sin hardware) para probar el juego

El mando se usa como una raqueta: el gesto da momento, fuerza y dirección del golpe; los botones eligen el
golpe (ninguno=topspin, A=plano, B=cortado, A+B=globo/dejada); levantar el morro lanza la pelota del saque.

`calibrate` averigua solo qué eje del giroscopio es cuál y su signo comparándolos con la gravedad que mide el
acelerómetro (no hay que "adivinar" ejes). Guarda la matriz `gyro_map` en wii_config.json. El puente envía el
giroscopio ya en ejes del mando: X derecha · Y morro · Z arriba (giro positivo = regla de la mano derecha).

Opciones útiles:
    --addr AA:BB:CC:DD:EE:FF   salta el escaneo (si ya conoces la MAC)
    --host IP                  destino UDP (por defecto: auto; en WSL2 = IP de Windows)
    --port 9876                puerto UDP (debe coincidir con wii_config.json)

Paquete enviado a ~100 Hz:  {"t": s, "a": [ax,ay,az] (g), "g": [wx,wy,wz] (°/s, ejes del mando), "b": máscara}
Máscara de botones: A=1 B=2 UNO=4 DOS=8 MAS=16 MENOS=32 HOME=64 ARRIBA=128 ABAJO=256 IZQ=512 DER=1024

NOTA: protocolo implementado desde la especificación pública de Wii Remote / MotionPlus. Para
encontrar el mando pulsa 1+2 (luces parpadeando) antes de lanzar `stream` o `calibrate`.
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


def load_map(path):
    """Matriz 3x3 (lista de 9) que pasa el giroscopio crudo a ejes del mando. Identidad si no hay calibración."""
    ident = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    try:
        m = json.load(open(path)).get("gyro_map")
        if m and len(m) == 9:
            return [float(x) for x in m], True
    except Exception:
        pass
    return ident, False


def apply_map(m, v):
    return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
            m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
            m[6] * v[0] + m[7] * v[1] + m[8] * v[2]]


def rotations24():
    """Las 24 matrices de rotación 'de cubo' (permutaciones con signos y det=+1)."""
    import itertools
    out = []
    for perm in itertools.permutations(range(3)):
        for sg in itertools.product((1, -1), repeat=3):
            m = [0] * 9
            for r in range(3):
                m[r * 3 + perm[r]] = sg[r]
            det = (m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6]))
            if det == 1:
                out.append(m)
    return out


def _unit(a):
    n = math.sqrt(sum(x * x for x in a))
    return [x / n for x in a] if n > 1e-6 else None


def _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def estimate_gyro_map(samples):
    """samples: [(acc_g(3), gyro_raw_dps(3) sin sesgo, dt)] mientras se mueve el mando.
    Con la gravedad u (hacia arriba, en ejes del mando): du/dt = -ω × u  =>  ω_perp = -u × du/dt.
    Se elige la rotación de cubo R que mejor correlaciona R·g con ω_perp. Devuelve (R, puntuación 0..1)."""
    ref = []     # [(ω_perp, gyro_raw)]
    prev = None
    sm_u = None
    for acc, g, dt in samples:
        n = math.sqrt(sum(x * x for x in acc))
        if not (0.85 < n < 1.15):
            prev = None
            continue
        u = [x / n for x in acc]
        sm_u = u if sm_u is None else [0.6 * sm_u[i] + 0.4 * u[i] for i in range(3)]
        if prev is not None:
            du = [(sm_u[i] - prev[i]) / dt for i in range(3)]
            c = _cross(sm_u, du)
            ref.append(([-x for x in c], g, sm_u))
        prev = list(sm_u)
    if len(ref) < 100:
        return None, 0.0
    best, best_score = None, -1.0
    for R in rotations24():
        num = den1 = den2 = 0.0
        for wp, g, u in ref:
            w = apply_map(R, g)
            d = w[0] * u[0] + w[1] * u[1] + w[2] * u[2]
            wperp = [w[i] - d * u[i] for i in range(3)]
            num += sum(wperp[i] * wp[i] for i in range(3))
            den1 += sum(x * x for x in wperp)
            den2 += sum(x * x for x in wp)
        score = num / math.sqrt(den1 * den2) if den1 > 0 and den2 > 0 else 0.0
        if score > best_score:
            best, best_score = R, score
    return best, best_score


def run_stream(args):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    host = args.host or default_host()
    print(f"Enviando a {host}:{args.port}  (Ctrl+C para salir)")
    gmap, calibrated = load_map(args.out)
    if not calibrated:
        print("! Aún no hay calibración de ejes: ejecuta primero `python3 wii_bridge.py calibrate`.")
    wm = connect(args)
    t_start = time.time()
    last_print = 0
    try:
        while True:
            r = wm.read()
            if not r:
                continue
            mask, acc, g = r
            gx = apply_map(gmap, [g[i] - wm.gyro_bias[i] for i in range(3)])
            pkt = {"t": round(time.time() - t_start, 4), "a": [round(v, 3) for v in acc], "g": [round(v, 1) for v in gx], "b": mask}
            sock.sendto(json.dumps(pkt, separators=(",", ":")).encode(), (host, args.port))
            if time.time() - last_print > 1.0:
                last_print = time.time()
                print("\r|g|=%6.0f °/s  acc=(%.2f,%.2f,%.2f)  botones=%s   " % (math.sqrt(sum(v * v for v in gx)), *acc, [n for i, n in enumerate(BTN_NAMES) if mask >> i & 1]), end="")
    except KeyboardInterrupt:
        pass
    finally:
        wm.close()


def run_calibrate(args):
    """Calibración automática de ejes: agita/gira el mando libremente ~10 s (despacio, en todas direcciones)."""
    wm = connect(args)
    input("\nAgarra el mando como una raqueta. Pulsa ENTER y durante 10 s GÍRALO libremente en todas direcciones\n"
          "(morro arriba/abajo, a izquierda/derecha, volteándolo), con movimientos suaves, sin golpes bruscos. ")
    samples = []
    t_prev = time.time()
    t0 = t_prev
    while time.time() - t0 < 10.0:
        r = wm.read()
        if not r:
            continue
        now = time.time()
        dt = max(0.002, min(0.05, now - t_prev))
        t_prev = now
        _, acc, g = r
        samples.append((acc, [g[i] - wm.gyro_bias[i] for i in range(3)], dt))
    R, score = estimate_gyro_map(samples)
    wm.close()
    if R is None:
        sys.exit("Muy pocos datos válidos: mueve el mando más y con más suavidad.")
    print("Coincidencia con la gravedad: %.2f (1.0 = perfecta)" % score)
    if score < 0.6:
        print("! Coincidencia baja: repite agitando más despacio y en más direcciones.")
    cfg = {}
    if os.path.exists(args.out):
        cfg = json.load(open(args.out))
    cfg["gyro_map"] = R
    cfg["port"] = args.port
    json.dump(cfg, open(args.out, "w"), indent=2)
    print("gyro_map =", R, "-> guardado en", args.out)


def run_fake(args):
    """Simula un mando físicamente coherente: lanza, golpea a derecha/izquierda/centro con distintos botones."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from wii_sim import SimRemote
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    host = args.host or "127.0.0.1"
    print(f"[fake] enviando a {host}:{args.port}")
    r = SimRemote()
    plan = [("lanzar", lambda: r.toss()),
            ("golpe a la derecha + A", lambda: r.swing(1300, 30, -15, buttons=1)),
            ("golpe al centro", lambda: r.swing(1000, 0, -10)),
            ("golpe a la izquierda + B", lambda: r.swing(1300, -30, 15, buttons=2)),
            ("globo (A+B, sube)", lambda: r.swing(1000, 0, -10, lift=40, buttons=3))]
    n = 0
    while True:
        name, fn = plan[n % len(plan)]
        print("[fake] gesto:", name)
        n += 1
        pk = r.rest(2.0) + fn() + r.rest(0.3) + r.move_to(az=0.0, el=0.0, seconds=0.5)
        for p in pk:
            sock.sendto(json.dumps(p, separators=(",", ":")).encode(), (host, args.port))
            time.sleep(0.01)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", nargs="?", default="stream", choices=["stream", "calibrate", "fake"])
    ap.add_argument("--addr")
    ap.add_argument("--host")
    ap.add_argument("--port", type=int, default=9876)
    ap.add_argument("--hci", default="hci0")
    ap.add_argument("--cal-seconds", type=float, default=2.0)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "wii_config.json"))
    args = ap.parse_args()
    {"stream": run_stream, "calibrate": run_calibrate, "fake": run_fake}[args.mode](args)


if __name__ == "__main__":
    main()
