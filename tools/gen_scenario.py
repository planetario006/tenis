"""Genera /tmp/scenario.json con gestos simulados para tools/test_gestures.gd."""
import json, sys
sys.path.insert(0, __file__.rsplit("/tools", 1)[0] + "/wii")
from wii_sim import SimRemote

r = SimRemote()
segs = []
def add(label, pk, back=True):
    pk = pk + r.rest(0.15)
    if back:  # el jugador vuelve a la posición de listo
        pk += r.move_to(az=READY[0], el=0.0, seconds=0.6)
    segs.append({"label": label, "packets": pk + r.rest(0.6)})
READY = [0.0]

add("reposo", r.rest(1.5))
add("toss", r.toss())
# azimut de listo = 0; golpes con distinta dirección / fuerza
add("derecha fuerte  (az +30, 1300)", r.swing(1300, 30, -20))
add("izquierda fuerte(az -30, 1300)", r.swing(1300, -30, 20))
add("centro medio    (az 0, 900)", r.swing(900, 0, -15))
add("derecha suave   (az +30, 550)", r.swing(550, 30, -10))
add("plano A         (az 10, 1100)", r.swing(1100, 10, -10, buttons=1))
add("cortado B       (az 10, 1100)", r.swing(1100, 10, -10, buttons=2))
add("globo A+B sube  (lift 40)", r.swing(1000, 0, -10, lift=40, buttons=3))
add("dejada A+B corto", r.swing(500, 0, -5, lift=0, buttons=3, dur=0.2))
# listo desplazado a la derecha 20°: sigue siendo relativo a la posición de listo
READY[0] = 20.0
add("mover listo +20", r.move_to(az=20, seconds=1.2) + r.rest(1.0))
add("derecha rel (+20→+50)", r.swing(1200, 50, 20))
add("backswing lento (no es golpe)", r.move_to(az=-20, seconds=0.35))
add("golpe izq. con listo +20", r.swing(1200, -10, 30))
json.dump(segs, open("/tmp/scenario.json", "w"))
print("segmentos:", len(segs))
