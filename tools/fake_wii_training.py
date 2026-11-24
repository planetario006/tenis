# Prueba del modo entrenamiento con un mando simulado: lee las señales "CUE" que imprime el juego
# (godot --headless --path . -- --train --debug) y envía el gesto correspondiente en el momento justo.
# Uso:  python3 tools/fake_wii_training.py [ruta_godot]
import json, socket, subprocess, sys, time, os
root = __file__.rsplit("/tools", 1)[0]
sys.path.insert(0, root + "/wii")
from wii_sim import SimRemote
godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
r = SimRemote()
def play(pk):
    for p in pk:
        s.sendto(json.dumps(p).encode(), ("127.0.0.1", 9876))
        time.sleep(0.01)
PEAK = {"SUAVE": 650, "MEDIA": 1000, "FUERTE": 1400}
# el "jugador" simulado: el revés barre con otro centro que el drive
AZ = {("drive", "R"): (24, -8), ("drive", "L"): (-16, 10), ("reves", "R"): (30, 6), ("reves", "L"): (-8, 14)}
proc = subprocess.Popen([godot, "--headless", "--path", root, "--", "--train", "--debug", "--seconds=170"], stdout=subprocess.PIPE, text=True, cwd=root)
play(r.rest(1.0))
for line in proc.stdout:
    line = line.strip()
    if os.environ.get("V") and not line.startswith(("ERROR","   at")): print("   >", line, flush=True)
    if line.startswith("CUE"):
        _, kind, d, inten = line.split()
        az_to, az_from = AZ[(kind, d)]
        print(line, flush=True)
        play(r.swing(PEAK[inten], az_to, az_from, dur=0.26))
        play(r.move_to(az=0.0, el=0.0, seconds=0.4))
    elif line.startswith(("PERFIL", "FIN")):
        print(line, flush=True)
        if line.startswith("PERFIL"):
            break
proc.terminate()
