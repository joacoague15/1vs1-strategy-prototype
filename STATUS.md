# Estado del Proyecto

## Estado actual: Sandbox funcional

El juego es un sandbox donde el jugador controla ambos equipos (rojo y azul) manualmente. No hay IA ni spawning automatico de enemigos.

## Que funciona
- Zona roja: cuadrado unico de 300x300 centrado en (640,360). 4 zonas azules de 100x100
- Compra de tropas con costos diferenciados por equipo y tipo
- Colocacion en la zona correcta segun equipo
- Colision de unidades: no se pueden superponer (distancia minima 32px)
- Ghost de placement se muestra rojo cuando la posicion esta ocupada
- Drag and drop para reposicionar tropas (vuelve a posicion original si hay colision)
- Lane determinado por posicion relativa al centro usando diagonales (N/S/E/O)
- Flecha de direccion se actualiza en tiempo real durante drag
- Combate automatico con ataques instantaneos (sin proyectiles)
- Tropas sobrevivientes se resetean al terminar la ronda
- Economia dual (oro rojo / oro azul) con income por ronda
- Editor de oro (spinbox + botones +10/+100) para ambos equipos
- Fabricas de azul para aumentar income
- STOP WAVE para cancelar batalla y resetear
- Velocidad x1/x2/x4
- Reiniciar juego completo
- Venta de unidades (click derecho, devuelve 50% del costo)

## Archivos muertos (no se usan)
- `scripts/wave_defs.gd` - definiciones de oleadas, no se spawnean enemigos por script
- `scripts/projectile.gd` + `scenes/projectile.tscn` - los ataques son instantaneos

## Cosas pendientes / ideas
- [ ] El tanque no tiene danio definido en UNITS.md (se uso 20 por defecto)
- [ ] El lanzallamas no tiene HP definido en UNITS.md (se uso 100 por defecto)
- [ ] No hay feedback visual del ataque (el danio se aplica pero no se ve el disparo)
- [ ] No hay sistema de IA para el equipo azul
- [ ] No hay win condition ni objetivo
- [ ] Las fabricas no tienen representacion visual
- [ ] wave_defs.gd y projectile.gd se pueden eliminar si se confirma que no se van a usar

## Historial de cambios
1. Proyecto inicial: 2 zonas (izq/der), RPS, stats iguales, una economia
2. Refactor a layout de cruz: centro rojo + 4 lados azules
3. Economia dual (oro rojo / oro azul separados)
4. Eliminado selector manual de lane: auto-calculo por posicion con diagonales
5. Desactivado game over: rondas pasan siempre, ambos equipos sobreviven
6. Eliminado spawn de enemigos por script: solo unidades manuales
7. Agregado STOP WAVE y velocidad x1/x2/x4
8. Unidades con personalidad: Zerg (rojo) vs Terran (azul) con stats unicos
9. Ataques instantaneos: eliminado sistema de proyectiles
10. Velocidades especificas por unidad segun UNITS.md
11. Layout uniforme: todas las zonas son cuadrados de 100x100. Cruz simetrica centrada en (640,360). 4 rojas adyacentes al centro vacio, 4 azules a 10px. Eliminadas diagonales, lane por zona
12. Colision de unidades: no se pueden superponer al comprar ni al reposicionar (distancia minima 32px). Feedback visual rojo cuando posicion esta ocupada
13. Zona roja unificada: las 4 zonas rojas + centro vacio se fusionaron en un solo cuadrado de 300x300. Lane se determina por posicion relativa al centro usando diagonales
14. Zonas azules extendidas: cada zona azul ahora cubre todo el largo del borde rojo correspondiente (300x100 para N/S, 100x300 para E/O)
15. Feedback visual de ataques: linea de disparo (ranged), flash blanco (danio recibido), slash (melee), cono naranja (lanzallamas)
16. Debug menu (F1): panel para modificar stats de unidades en runtime (HP, damage, range, speed, fire rate, flame arc). Aplica a base stats y unidades existentes
17. Firebat lanzallamas: ataque AOE en cono de 60°. Danio completo al target, 50% a enemigos secundarios en el cono. Arco configurable desde debug menu
