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
18. Mejoras de bomba del marine (panel F7, combinables): cantidad (2+ cargas antes del cooldown), acido (area que dania por segundo), adrenalina (area que da +40% velocidad de ataque/movimiento a aliados por 6s), ralentizar (area de nitrogeno que reduce 50% velocidad a enemigos mientras la tocan), circuitos (segunda explosion con mitad de danio). Todas las variables configurables en F7 y persistidas en units.json/niveles. Test headless en tests/bomb_upgrades_test.tscn
19. Mejoras de hellbat y medic (panel F7 reorganizado en 3 columnas, todas combinables y configurables). Hellbat/dash: embestida (explosion al final del dash que paraliza enemigos 2s), defensa (aliados sobre el recorrido reciben 60 de escudo por 6s), napalm (el recorrido quema 6s: 25 danio/s a light, 15 a armored). Medic: medicina (se cura a si mismo lo que cura), ataque (+20% velocidad de ataque al aliado mientras lo cura), movimiento (+40% velocidad si hay aliado con <50% HP en rango), escudo (sobrecurar a un aliado full genera escudo hasta 50). Test headless en tests/dash_medic_upgrades_test.tscn
20. Persistencia de mejoras en data/upgrades.json: el Apply del panel F7 guarda ahi (units.json ya no incluye las claves de mejoras). Se cargan al iniciar con prioridad sobre units.json
21. Editor de niveles: dificultad de la mision (facil/mediana/dificil) y creditos que otorga ganarla, editables en F6 y persistidos en el JSON del nivel. Los creditos solo se guardan (todavia no hay billetera/meta-economia que los acredite)
22. Rango de vision de las azules (aggro_range, 8 tiles default, configurable en F4 "General Blue"): marine y hellbat idle o en attack-move persiguen al enemigo mas cercano dentro de ese rango; el medic busca aliados heridos dentro del mismo rango (antes era rango infinito). Reemplaza el aggro especial de 6 tiles del hellbat
23. Vision como stat por unidad: aggro_range global reemplazado por vision_range (en tiles) en los datos de cada unidad azul (units.json), editable por unidad en el panel F1 ("Vision (tiles)"). Las unidades seleccionadas dibujan una circunferencia con su rango de vision (celeste atacantes, verde medic)
