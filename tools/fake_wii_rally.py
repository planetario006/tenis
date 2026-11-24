# Peloteo con mando simulado: la CPU saca, el jugador corre solo a la pelota y tú das gestos.
import json, socket, sys, time
sys.path.insert(0, __file__.rsplit("/tools", 1)[0] + "/wii")
from wii_sim import SimRemote
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
r = SimRemote()
def play(pk):
    for p in pk:
        s.sendto(json.dumps(p).encode(), ("127.0.0.1", 9876))
        time.sleep(0.01)
play(r.rest(1.0))
for i in range(30):
    az = [30, -30, 0][i % 3]
    play(r.swing(900 + 500 * ((i * 0.37) % 1.0), az, -az / 2, buttons=[0, 1, 2][i % 3]))
    play(r.move_to(az=0.0, el=0.0, seconds=0.4) + r.rest(0.2 + 0.1 * (i * 7 % 5)))
