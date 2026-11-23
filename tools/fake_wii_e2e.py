# Prueba de extremo a extremo con un mando simulado:
# 1) gesto de lanzar -> NO golpea -> la pelota se recupera (RETOSS)  2) lanza otra vez y golpea (saque)
# 3) luego golpes alternando recto / cruzado mientras el jugador corre solo a la pelota.
import json, socket, time, math
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
T = [0.0]
def send(g=(0, 0, 0), b=0):
    s.sendto(json.dumps({"t": T[0], "a": [0, 0.1, 1.0], "g": list(g), "b": b}).encode(), ("127.0.0.1", 9876))
    T[0] += 0.01
    time.sleep(0.01)
def rest(sec):
    for _ in range(int(sec * 100)):
        send()
def gesture(peak, vec, mask=0, dur=0.30):
    t = 0.0
    while t < dur:
        amp = peak * math.sin(math.pi * t / dur)
        send((vec[0] * amp, vec[1] * amp, vec[2] * amp), mask)
        t += 0.01
rest(1.5)
print("lanzar (1)"); gesture(900, (1, 0, 0))
rest(2.2)                          # no golpeo: la pelota debe volver a mi mano
print("lanzar (2)"); gesture(900, (1, 0, 0))
rest(0.62)
print("golpe de saque cruzado + A"); gesture(1200, (0.3, 0.1, 0.9), 1)
rest(1.0)
for i in range(8):
    vec = (0.3, 0.1, 0.9) if i % 2 == 0 else (-0.8, 0.0, 0.1)
    print("golpe", "cruzado" if i % 2 == 0 else "recto")
    gesture(1100, vec, 0)
    rest(1.1)
print("fin")
