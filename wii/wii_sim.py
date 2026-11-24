"""Simulador de mando de Wii físicamente coherente (acelerómetro + giroscopio consistentes).
Lo usan `wii_bridge.py fake` y las pruebas de tools/. Ejes del mando: X derecha, Y morro, Z arriba.
Orientación = Rz(guiñada)·Rx(cabeceo): guiñada + = a la IZQUIERDA, cabeceo + = morro arriba.
Azimut del morro (+ = derecha) = -guiñada."""
import math, random


class SimRemote:
    def __init__(self, noise=1.5, seed=1):
        self.t = 0.0
        self.yaw = 0.0      # grados
        self.pitch = 0.0
        self.roll = 0.0
        self.rng = random.Random(seed)
        self.noise = noise
        self.packets = []   # si no es None, se guardan aquí en vez de enviarse

    def packet(self, yaw_rate, pitch_rate, buttons=0, dt=0.01, roll_rate=0.0):
        """R = Rz(yaw)·Rx(pitch)·Ry(roll). Devuelve ω y gravedad en ejes del mando, coherentes con R."""
        sp, cp = math.sin(math.radians(self.pitch)), math.cos(math.radians(self.pitch))
        sr, cr = math.sin(math.radians(self.roll)), math.cos(math.radians(self.roll))
        # v = Rx^T (yaw_rate ẑ) + pitch_rate x̂ ; luego se pasa por Ry^T y se suma roll_rate ŷ
        v = [pitch_rate, yaw_rate * sp, yaw_rate * cp]
        w = [cr * v[0] - sr * v[2], v[1] + roll_rate, sr * v[0] + cr * v[2]]
        g = [0.0, sp, cp]                                   # Rx^T ẑ
        a = [cr * g[0] - sr * g[2], g[1], sr * g[0] + cr * g[2]]
        n = self.noise
        w = [x + self.rng.gauss(0, n) for x in w]
        a = [x + self.rng.gauss(0, 0.01) for x in a]
        self.yaw += yaw_rate * dt
        self.pitch += pitch_rate * dt
        self.roll += roll_rate * dt
        self.t += dt
        return {"t": round(self.t, 4), "a": [round(x, 3) for x in a], "g": [round(x, 1) for x in w], "b": buttons}

    def rest(self, seconds, buttons=0):
        return [self.packet(0.0, 0.0, buttons) for _ in range(int(seconds * 100))]

    def move_to(self, az=None, el=None, seconds=0.6, buttons=0):
        """Movimiento lento y suave (no cuenta como golpe) hasta el azimut/elevación indicados."""
        n = max(1, int(seconds * 100))
        tgt_yaw = self.yaw if az is None else -az
        tgt_pitch = self.pitch if el is None else el
        y0, p0 = self.yaw, self.pitch
        out = []
        for i in range(n):
            u0, u1 = i / n, (i + 1) / n
            f = lambda u: 0.5 - 0.5 * math.cos(math.pi * u)
            yr = (tgt_yaw - y0) * (f(u1) - f(u0)) / (seconds / n)
            pr = (tgt_pitch - p0) * (f(u1) - f(u0)) / (seconds / n)
            out.append(self.packet(yr, pr, buttons, seconds / n))
        return out

    def swing(self, peak_dps, az_to, az_from=None, lift=0.0, buttons=0, dur=0.28):
        """Golpe: barrido de azimut de az_from a az_to con perfil de velocidad en campana.
        peak_dps = velocidad angular máxima aproximada. Si se da lift (°), el morro sube durante el golpe."""
        az0 = -self.yaw if az_from is None else az_from
        sweep = az_to - az0
        # perfil seno: velocidad = A sin(pi u); recorrido = A*dur*2/pi -> A = sweep*pi/(2*dur); si no cuadra con peak, se añade
        # velocidad de cabeceo "de relleno" para llegar a peak sin alterar el recorrido de azimut
        n = int(dur / 0.01)
        out = []
        for i in range(n):
            u = (i + 0.5) / n
            prof = math.sin(math.pi * u)
            yaw_rate = -(sweep * math.pi / (2 * dur)) * prof
            pitch_rate = (lift * math.pi / (2 * dur)) * prof
            # componente de balanceo para alcanzar la velocidad pico pedida (no afecta a azimut ni elevación)
            base = math.hypot(yaw_rate, pitch_rate)
            extra = max(0.0, peak_dps * prof - base)
            # giro extra alrededor del eje Y (alabeo): no cambia hacia dónde apunta el morro
            out.append(self.packet(yaw_rate, pitch_rate, buttons, roll_rate=extra))
        return out

    def toss(self, rise=45.0, dur=0.35, trail=True):
        n = int(dur / 0.01)
        out = []
        for i in range(n):
            u = (i + 0.5) / n
            out.append(self.packet(0.0, (rise * math.pi / (2 * dur)) * math.sin(math.pi * u)))
        if trail:
            out += self.rest(0.25)
            out += self.move_to(el=0.0, seconds=0.5)
        return out
