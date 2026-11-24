# Tenis 3D (estilo Top Spin) — Godot 4.6.2

Juego de tenis 1 vs CPU con tu personaje `Barbarian.glb`, tu `raqueta.glb` y tu librería
`tenista_animaciones.res`. Abre la carpeta como proyecto en Godot 4.6.2 y pulsa F5.

## Controles (sólo mando de Wii Remote Plus)

Al arrancar aparece el **menú**: cruceta ↑↓ elige, **A** confirma, ←→ cambia la sensibilidad.
**PARTIDO · ENTRENAMIENTO DE GOLPES · SENSIBILIDAD DEL MANDO**. **HOME** vuelve al menú desde cualquier sitio.

| Acción | Cómo |
|---|---|
| **Golpear** | un **gesto** de swing: el mando mide el momento, la fuerza y la dirección |
| **Tipo de golpe** | ningún botón = topspin · **A** = plano · **B** = cortado · **A+B** = globo (si el swing sube) o dejada |
| **Fuerza** | velocidad angular máxima del swing (giroscopio): suave = poca fuerza, rápido = toda la fuerza |
| **Dirección** | hacia dónde **apunta el mando al golpear**, respecto a tu posición de "listo": izquierda / centro / derecha |
| **Saque** | **levanta el morro del mando** para lanzar la pelota y golpea cuando la barra entre en la zona verde (1 o 2 también lanzan) |
| Moverse | automático; **+** lo pasa a manual (cruceta) |
| Otros | **−** panel con los datos del gesto · cruceta ↑↓ dificultad, ←→ superficie (partido, antes de sacar) · **A / 1 / 2** reinicia al acabar el partido |

## Entrenamiento de golpes (calibra el mando a TU forma de golpear)
Menú → ENTRENAMIENTO. Una máquina (la CPU) te tira bolas lentas a tu derecha (**drive**) o a tu izquierda (**revés**) y tú
respondes **sin botones (topspin)**. Son 4 bloques de 5 bolas:
**drive → derecha · drive → izquierda · revés → derecha · revés → izquierda**.
En cada bloque se pide una intensidad distinta: **SUAVE, MEDIA, MEDIA, FUERTE, FUERTE** (lo ves en pantalla). Si fallas la bola o
usas un botón, esa bola no cuenta y se repite (máx. 10 intentos por bloque).
De cada golpe se guarda el pico de fuerza (°/s), hacia dónde apuntaba el mando, cuánto subió y el timing. Al terminar se
calcula y se guarda en `user://wii_profile.json` (también quedan las 20 muestras en bruto):
- **Rango de fuerza**: tu swing suave → fuerza mínima, tu swing fuerte → fuerza máxima (`power_min_dps` / `power_max_dps`).
- **Umbral de detección**: el 80 % de tu swing más suave (entre 400 y 800 °/s). Por debajo de eso no es un golpe.
- **Dirección por tipo de golpe**: tu "centro" y tu "rango" izquierda/derecha **por separado para drive y revés**
  (el revés no barre igual que el drive). Con perfil, izquierda = −1 y derecha = +1 corresponden a TUS golpes de entrenamiento.
- Resumen final: medias, dispersión (±°) y si sueles golpear tarde o pronto. El partido usa el perfil automáticamente.
Repite el entrenamiento cuando quieras (sobrescribe el perfil).

## Sensibilidad del mando (menos golpes accidentales)
Menú → SENSIBILIDAD: **BAJA / MEDIA / ALTA** (multiplica los umbrales ×1,35 / ×1 / ×0,75). Además hay filtros nuevos:
- el swing tiene que **mantenerse** por encima del umbral (`confirm_hold`), así que una sacudida seca no cuenta;
- tras un golpe hay que **volver a calmar el mando** antes de poder armar otro (`rearm_ratio`);
- **re-cero automático** del giroscopio cuando el mando está quieto (sin deriva ni "fantasmas");
- el juego **ignora el gesto si no viene una bola que puedas devolver** o si es demasiado pronto (cursor muy lejos de la zona verde).

## Cómo se reconoce el gesto (`scripts/wii_input.gd`)
- **Orientación**: filtro complementario (Mahony) que fusiona giroscopio y acelerómetro; da hacia dónde apunta el mando
  (azimut) y cuánto sube (elevación) sin deriva de inclinación.
- **Momento**: el golpe se "arma" a 260 °/s y se **confirma** a 460 °/s (valores por defecto, × sensibilidad; el entrenamiento los ajusta a ti). El ir-y-venir lento del brazo (backswing) no cuenta.
  Hay 0,40 s de enfriamiento entre golpes, y ya no hace falta quedarse quieto entre uno y otro.
- **Fuerza**: pico de velocidad angular (380 → 1500 °/s por defecto) con curva `power_curve`.
- **Dirección**: azimut ponderado por velocidad en la parte rápida del swing, relativo a tu posición de "listo" (que se adapta
  sola mientras estás quieto; así no importa hacia dónde mires con el mando). ±38° = esquina. Si te sale al revés:
  `"invert_lateral": true`.
- **Globo / dejada** (A+B): globo si el morro sube ≥ 22° durante el swing; si no, dejada.
- **Lanzar**: el morro sube ≥ 28° sobre la posición de listo a ≥ 70 °/s. El gesto de lanzar no cuenta como golpe.
- Todos los umbrales están en `wii/wii_config.json` (los nombres y valores por defecto, en `WiiInput.cfg`).

## Timing = calidad del golpe
La barra decide cuánto se cumple lo que hiciste con el mando:
- Zona verde: la bola va **exactamente hacia el lado indicado (hasta la línea)** y con **toda la fuerza** del gesto.
- Peor timing: la dirección se **atrae hacia el centro** (35 % de fidelidad en el peor caso), la bola sale más corta, con
  **hasta 40 % menos fuerza** y más dispersión. El HUD muestra PERFECTO / BIEN / PRONTO / TARDE.
- Saque: el gesto elige izquierda/derecha dentro del cuadro de saque; con mal timing cae más centrado y corto.

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
python3 wii/wii_bridge.py calibrate   # UNA VEZ: agita el mando 10 s; detecta solos los ejes del giroscopio -> wii_config.json
python3 wii/wii_bridge.py stream      # envía el mando a Godot por UDP 9876
python3 wii/wii_bridge.py fake        # sin hardware: simulador coherente (lanza, golpea izquierda/derecha, globo)
```
Pulsa 1+2 en el mando al conectar. Con WSL2 (NAT) envía a la IP de Windows (por defecto); permite UDP 9876 en el firewall
o usa red "mirrored". `--host IP` fuerza destino. `calibrate` compara el giroscopio con la gravedad del acelerómetro y elige
la matriz de ejes que encaja (no hay que decir qué es guiñada o cabeceo). Si tu `wii_config.json` antiguo tiene
`yaw_axis`/`pitch_axis`, bórralos: ya no se usan.

## Estado de las pruebas
- El entrenamiento se probó de principio a fin con el simulador (`tools/fake_wii_training.py`: 20 golpes, perfil guardado y
  leído por el partido). Con un mando real los números saldrán distintos: para eso es el entrenamiento.
- Probado con un mando **simulado coherente** (`wii/wii_sim.py`): reconocimiento de izquierda/centro/derecha, fuerza,
  A/B/A+B, globo vs dejada, backswing ignorado, posición de "listo" desplazada, lanzar con gesto, re-lanzar, saque y
  peloteo dentro del juego (Godot 4.6.2 headless), y la calibración automática de ejes (acierta la matriz en simulación).
- **No probado con un mando real**: protocolo Bluetooth/MotionPlus escrito desde la especificación pública. Ajusta
  umbrales con el panel `−` (muestra |ω|, elevación, azimut y el último gesto).
- Tu librería sólo trae `idle`, 4 carreras, `drive_topspin` y `reves_topspin`: el resto de golpes se distinguen por física.
- Sólo individuales; sin cambio de lado; cámara fija detrás del jugador cercano.

## Pruebas incluidas
- `python3 tools/gen_scenario.py && godot --headless --path . --script tools/test_gestures.gd` (reconocimiento de gestos)
- `python3 tools/fake_wii_training.py /ruta/a/godot` (arranca Godot en modo `--train` y responde a cada bola)
- `tools/fake_wii_e2e.py` (lanzar/re-lanzar/saque/peloteo) y `tools/fake_wii_rally.py` con
  `godot --headless --path . -- --play --debug --seconds=40` (`--play` salta el menú; `--train` entra directo al entrenamiento)
