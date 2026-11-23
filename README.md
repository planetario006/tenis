# Tenis 3D (estilo Top Spin) — Godot 4.6.2

Juego de tenis 1 vs CPU con tu personaje `Barbarian.glb`, tu `raqueta.glb` y tu librería
`tenista_animaciones.res`. Abre la carpeta como proyecto en Godot 4.6.2 y pulsa F5.

## Controles

| | Mando de Wii (Remote Plus) | Teclado |
|---|---|---|
| Golpear | **gesto** (fuerza, momento y dirección) | ESPACIO |
| Topspin / Plano / Cortado | ningún botón / **A** / **B** | — / J / K |
| Globo / Dejada | **A+B**: gesto hacia arriba = globo, gesto corto = dejada | J+K (+I = globo) |
| **Dirección** | **recto = paralelo, cruzado = cruzado** (ver abajo) | Q paralelo · E cruzado · nada = centro |
| **Saque** | **levanta el mando (morro arriba) para lanzar la pelota** y golpea a tiempo (A plano · B cortado · nada kick) | ESPACIO (lanzar), ESPACIO (golpear) |
| Moverse | **automático** (corre solo a la pelota); `+` lo desactiva | `M` alterna auto/manual; en manual flechas o WASD |
| Fuerza | velocidad del gesto | Shift fuerte / Ctrl suave |

Otras teclas: `V` invierte recto/cruzado, `C` superficie, `F1-F3` dificultad, `R` reinicia, `HOME` (Wii) re-centra.

## Cómo funciona ahora
- **Saque con el mando**: levantas el mando (el gesto de cabeceo hacia arriba lanza la pelota) y luego golpeas cuando
  la barra de timing entre en la zona verde. **Si no golpeas, o fallas el swing, no hay falta**: la pelota
  vuelve a tu mano y repites el lanzamiento hasta golpearla. (1/2 o ESPACIO también lanzan.)
- **Movimiento automático** (por defecto): el jugador corre solo hasta el punto de golpeo; tú sólo eliges el tipo
  de golpe y el momento. Desactívalo con `M` o el botón `+` del mando y se controla con las flechas/WASD.
  También con `--manual` al arrancar.
- **Sin marcadores en el campo rival**: ya no hay aro de apuntado ni cuadro de saque resaltado. Sólo queda la
  **X amarilla en tu campo** (dónde botará la pelota del rival) y la barra de timing (zona verde final).
- **Dirección = cómo golpeas**: el barrido lateral del gesto decide recto o cruzado.
  - Gesto recto (poco barrido) → bola **paralela**, al lado de donde golpeas (si golpeas desde la derecha, a la línea de la derecha).
  - Gesto que cruza (barrido amplio hacia el lado contrario) → bola **cruzada**, al lado opuesto.
  - Medio → hacia el centro. En el saque: barrido grande = saque abierto, pequeño = a la T.
  - Si en tu mano te sale al revés: `V` o `"invert_lateral": true` en `wii/wii_config.json`.
    Umbrales: `cross_min_deg` / `cross_max_deg`.
- **El timing decide la calidad del tiro**: con el cursor en la zona verde la bola va **ajustada a la línea y con
  toda la fuerza del gesto**; con peor timing va **más al centro, más corta y con menos fuerza** (y más errores).
  La barra, el texto PERFECTO/BIEN/TARDE/PRONTO y la etiqueta (paralelo/cruzado/al centro) lo reflejan.

## Reglas
Dentro/fuera con líneas, red/let, saque a cuadro diagonal con 2 intentos, el saque no se devuelve antes del bote,
doble bote, 15-30-40, ventaja, juegos, sets y tie-break. El lado de saque alterna cada punto (derecha en pares,
izquierda en impares; el 2.º saque repite lado) y el sacador queda siempre detrás de la línea de fondo, en su mitad.

## Física
`scripts/ball_physics.gd`: gravedad, arrastre, **efecto Magnus**, decaimiento del espín y rebote con **modelo de
impulso rígido** (restitución normal + fricción/rodadura). Topspin muerde y mantiene velocidad; el cortado derrapa.
Pista dura y tierra. El planificador resuelve el ángulo (o la velocidad en globo/dejada) con la física completa.

## Adaptación al personaje
Medido sobre tus animaciones (`tools/sample2.gd`): brazo corto (0.67 u de 2.2 u), raqueta en la mano derecha, revés a
dos manos, contacto en t≈0.55 s. Se usa el contacto real de la raqueta (`Player.CONTACT_HEAD`) para colocar al
jugador (lunge ≤ 1.9 m) y que la raqueta coincida con la pelota.

## Mando de Wii
PowerShell (admin): `usbipd list` / `usbipd bind --busid 2-10` / `usbipd attach --wsl --busid 2-10 --auto-attach`
WSL: `lsusb` · `sudo service bluetooth start` · `sudo hciconfig hci0 up` · `hciconfig -a` (UP RUNNING)
```
python3 wii/wii_bridge.py axes     # calibración guiada de ejes -> escribe wii/wii_config.json
python3 wii/wii_bridge.py stream   # envía el mando a Godot por UDP 9876
python3 wii/wii_bridge.py fake     # sin hardware: simula lanzar/golpes para probar el juego
```
Pulsa 1+2 en el mando al lanzar. Con WSL2 (NAT) envía a la IP de Windows (por defecto); permite UDP 9876 en el
firewall o usa red "mirrored". `--host IP` fuerza destino. Ejes: `axes` pide girar a la izquierda (guiñada) y
levantar el morro (cabeceo); lo usan el gesto de lanzar y el barrido recto/cruzado.

## Estado de las pruebas
- Probado: física, partidos IA vs IA completos, flujo del mando con paquetes simulados (lanzar con gesto,
  re-lanzar si no golpeas, saque, peloteo con movimiento automático y recto/cruzado), render con Mesa.
- **No probado con un mando real**: el protocolo Bluetooth/MotionPlus está escrito desde la especificación pública.
  Los umbrales del gesto (lanzar, recto/cruzado, fuerza) son estimaciones: ajústalos en `wii/wii_config.json`.
- Tu librería sólo trae `idle`, 4 carreras, `drive_topspin` y `reves_topspin`: plano/cortado/globo/dejada usan esos
  movimientos y se distinguen por física. El saque es procedural (`Player.SERVE_POSES`).
- Sólo individuales; sin cambio de lado; cámara fija detrás del jugador cercano.

## Pruebas incluidas
`tools/fake_wii_e2e.py` (lanzar/re-lanzar/saque) y `tools/fake_wii_rally.py` (peloteo) con
`godot --headless --path . -- --debug --seconds=25` (añade `--first_server=1` para el peloteo).
