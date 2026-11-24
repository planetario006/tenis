# Prueba de extremo a extremo con un mando simulado (físicamente coherente):
# 1) levantar el mando lanza la pelota; no golpeo -> RETOSS  2) lanzo otra vez y saco  3) peloteo izquierda/derecha.
import json, socket, sys, time
sys.path.insert(0, __file__.rsplit("/tools", 1)[0] + "/wii")
from wii_sim import SimRemote
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
r = SimRemote()
def play(pk):
    for p in pk:
        s.sendto(json.dumps(p).encode(), ("127.0.0.1", 9876))
        time.sleep(0.01)
def ready(sec=0.6):
    play(r.move_to(az=0.0, el=0.0, seconds=0.4) + r.rest(sec))
play(r.rest(1.5))
print("lanzar (1)"); play(r.toss())
play(r.rest(2.2))                          # no golpeo: la pelota debe volver a mi mano
print("lanzar (2)"); play(r.toss(dur=0.3, trail=False))
play(r.rest(0.3))
print("golpe de saque a la derecha + A"); play(r.swing(1300, 30, -15, buttons=1))
ready(1.0)
for i in range(8):
    az = 30 if i % 2 == 0 else -30
    print("golpe", "derecha" if az > 0 else "izquierda")
    play(r.swing(1100, az, -az / 2, buttons=[0, 1, 2][i % 3]))
    ready(0.8)
print("fin")
