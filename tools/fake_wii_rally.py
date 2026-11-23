# Peloteo con mando simulado: la CPU saca, el jugador corre solo a la pelota y tú das gestos.
import json, socket, time, math
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
T = [0.0]
def send(g=(0, 0, 0), b=0):
    s.sendto(json.dumps({"t": T[0], "a": [0, 0.1, 1.0], "g": list(g), "b": b}).encode(), ("127.0.0.1", 9876))
    T[0] += 0.01
    time.sleep(0.01)
def gesture(peak, vec, mask=0, dur=0.30):
    t = 0.0
    while t < dur:
        amp = peak * math.sin(math.pi * t / dur)
        send((vec[0] * amp, vec[1] * amp, vec[2] * amp), mask)
        t += 0.01
for _ in range(100): send()
for i in range(30):
    cross = (i % 2 == 0)
    vec = (0.3, 0.1, 0.9) if cross else (-0.8, 0.0, 0.1)
    gesture(900 + 500 * ((i * 0.37) % 1.0), vec, [0, 1, 2][i % 3])
    for _ in range(40 + (i * 7) % 30): send()
