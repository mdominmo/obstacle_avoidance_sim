# obstacle_avoidance_sim

Entorno de simulación para evaluar algoritmos de evasión de obstáculos en drones. Genera mundos procedurales en Gazebo Harmonic, simula un dron PX4 (x500) equipado con 4 telémetros (front/back/left/right) y expone sus mediciones como topics ROS2 mediante un bridge, todo orquestado con Docker.

## Componentes

- **`gz_procedural_worlds/`** (submódulo) — Generador de mundos procedurales para Gazebo a partir de configs YAML: define área, zona de spawn, obstáculos (árboles, personas, muros, etc.) e iluminación, y comprueba la conectividad entre el punto de inicio y los objetivos. Incluye además el submódulo `px4-sitl-docker-sim`, que provee el contenedor con PX4 SITL + Gazebo Harmonic + ROS2.
- **`gz_custom_models/`** (submódulo) — Modelos SDF personalizados para el simulador. Actualmente incluye una variante del x500 con sensores de distancia; se prevé añadir modelos con sensores adicionales (cámaras, IMU externas, etc.) a medida que el proyecto evolucione.
- **`config/`** — Plantilla de configuración del `ros_gz_bridge` que mapea los topics de los sensores del dron de Gazebo a ROS2.
- **`docker/`** — Dockerfile del contenedor del bridge (ROS2 Humble + `ros_gz_bridge`).
- **`scripts/run_simulation.sh`** — Script principal: construye las imágenes Docker necesarias, genera el mundo, lanza el simulador y el bridge, y los mantiene corriendo hasta que se interrumpa.

## Uso rápido

```bash
git submodule update --init --recursive
./scripts/run_simulation.sh --config gz_procedural_worlds/configs/default.yaml
```

Topics ROS2 expuestos: `/rangefinder/front`, `/rangefinder/back`, `/rangefinder/left`, `/rangefinder/right`.

## Requisitos

- Docker + NVIDIA Container Toolkit (renderizado GPU)
- X11 (simulación con interfaz gráfica)
