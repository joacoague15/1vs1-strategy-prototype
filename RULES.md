# Auto-Battler 2D - Reglas del Juego

## Concepto
Sandbox de auto-battler 2D. El jugador controla ambos equipos (rojo y azul), posicionando tropas manualmente en sus zonas respectivas. Al iniciar la ronda, las tropas avanzan y pelean automaticamente.

## Layout del mapa (1280x720)
Centrado en (640, 360). Zona roja es un cuadrado unico de 300x300.
Zonas azules son 4 cuadrados de 100x100 a 10px de los bordes rojos.

```
		   [AZUL N]
		  +-------+
		  |       |
[AZUL O]  |  RED  |  [AZUL E]
		  |       |
		  +-------+
		   [AZUL S]
```

### Coordenadas - Zona roja (1 cuadrado 300x300)
- **RED**: (490,210) a (790,510) → centro en (640,360)
- Lane se determina por posicion relativa al centro usando diagonales

### Coordenadas - Zonas azules (300x100 o 100x300, gap 10px)
- **NORTE** (azul): (490,100) a (790,200) → 300x100
- **SUR** (azul):   (490,520) a (790,620) → 300x100
- **OESTE** (azul): (380,210) a (480,510) → 100x300
- **ESTE** (azul):  (800,210) a (900,510) → 100x300
- Cada zona azul cubre todo el largo del borde rojo correspondiente

### Asignacion de lane
El lane de una tropa roja se calcula por su posicion relativa al centro (640,360) usando diagonales: la unidad recibe el lane del cuadrante donde esta (N/S/E/O). Al hacer drag, la flecha se actualiza en tiempo real.

### Colision de unidades
Las unidades no pueden superponerse. Distancia minima entre centros: 32px. Si al colocar o soltar una tropa la posicion esta ocupada, el placement se rechaza (no se gasta oro / la tropa vuelve a su posicion original). El ghost de placement se muestra rojo cuando la posicion esta ocupada.

## Equipos

### Equipo Rojo (Zerg) - zona centro
| Unidad    | Letra | Costo | HP  | Danio | Rango   | Cooldown | Velocidad |
|-----------|-------|-------|-----|-------|---------|----------|-----------|
| Zergling  | Z     | $50   | 35  | 5     | melee   | 0.4s     | 100 px/s  |
| Hydralisk | H     | $100  | 80  | 12    | 200px   | 0.6s     | 87.5 px/s |
| Roach     | R     | $150  | 140 | 16    | 160px   | 1.5s     | 87.5 px/s |

### Equipo Azul (Terran) - zonas N/S/E/O
| Unidad  | Letra | Costo | HP  | Danio | Rango | Cooldown | Velocidad |
|---------|-------|-------|-----|-------|-------|----------|-----------|
| Marine  | M     | $50   | 50  | 6     | 200px | 0.5s     | 75 px/s   |
| Firebat | F     | $100  | 100 | 8     | 200px | 1.8s     | 75 px/s   | AOE cono 60° |
| Tank    | T     | $150  | 200 | 20    | 280px | 1.0s     | 70 px/s   |

## Combate
- Los ataques son instantaneos (sin proyectil fisico): al disparar, el danio se aplica inmediatamente al objetivo
- Cada unidad busca al enemigo mas cercano del equipo contrario
- Si el enemigo esta en rango: dispara (respetando cooldown)
- Si el enemigo esta fuera de rango: se mueve hacia el
- Si no hay enemigos: avanza en su direccion por defecto
  - Rojas: hacia el lado del sector donde estan posicionadas (N/S/E/O)
  - Azules: hacia el centro del mapa (640, 360)
- **Firebat (lanzallamas)**: ataca en cono (60° por defecto). Danio completo al target principal, 50% a otros enemigos dentro del cono
- **Feedback visual**: linea de disparo (ranged), flash blanco (danio recibido), slash (melee), cono naranja (lanzallamas)

## Economia
- Oro inicial: 200 por equipo
- Ingreso base por ronda: +50 por equipo
- Fabricas (solo azul): +25 de oro adicional por ronda, cuestan $10
- Venta de unidades: devuelve 50% del costo
- Cada equipo tiene oro independiente

## Flujo de juego
1. **Preparacion**: comprar y posicionar tropas en las zonas correspondientes
2. **START WAVE**: comienza la batalla, las tropas pelean automaticamente
3. **Fin de ronda**: cuando un lado se queda sin unidades, la ronda termina
4. Las tropas sobrevivientes de ambos equipos vuelven a su posicion y se curan
5. Se incrementa la ronda y se da income a ambos equipos
6. No hay game over ni victoria: el sandbox continua indefinidamente

## Controles
- **Click izquierdo**: colocar tropa comprada / agarrar tropa para mover
- **Soltar click**: dejar tropa en nueva posicion (se clampea a su zona)
- **Click derecho**: cancelar colocacion / cancelar drag / vender tropa
- **ESC**: cancelar colocacion
- **STOP WAVE**: cancela la batalla actual, resetea todas las tropas a su posicion
- **Boton velocidad**: cicla x1 / x2 / x4 (usa Engine.time_scale)
- **F1**: abre/cierra panel de debug para modificar stats de unidades en runtime
- **Reiniciar**: borra todo y vuelve a ronda 1 con oro inicial

## Archivos del proyecto
- `scripts/game_data.gd` - autoload con enums, economia dual, stats de unidades, tracking
- `scripts/unit.gd` - logica de unidad: stats, movimiento, combate, visual
- `scripts/main.gd` - zonas, placement, drag, dibujo del mapa, control de rondas
- `scripts/hud.gd` - paneles rojo/azul, botones de compra, editor de oro, controles
- `scripts/wave_defs.gd` - definiciones de oleadas (no se usa actualmente)
- `scripts/projectile.gd` - proyectil (no se usa, ataques son instantaneos)
