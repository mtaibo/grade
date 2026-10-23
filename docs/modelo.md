# Modelo de evaluación

Primera versión del árbol de evaluación (`Sources/Engine/`), validada contra las 3 guías de
`guide/` (extraídas en `guide/extracted/*.json`). Todavía no hay motor de cálculo, solo los tipos
del árbol — ver "Qué falta" al final.

## Tipos

Siguen los 5 nodos de `guide/proyect.md` §4, como un `indirect enum Node` con un caso por tipo:

- **`Grade`**: nota introducida por el usuario, con su escala, `minimum` y `recovery` opcionales.
- **`Group`**: combina hijos (`WeightedChild`) con media ponderada, suma, máx, mín o mejores N de M.
- **`Alternatives`**: varias ramas (`Branch`), cada una con una condición opcional; se escoge una.
- **`Bonus`**: puntos que se suman al padre, con un tope.
- **`Requirement`**: condición sin nota que bloquea el aprobado (p. ej. asistencia mínima).

`Minimum` (umbral + consecuencia: `doesNotAverage` / `capAt` / `fails`) y `Recovery` viven como
reglas en cualquier nodo, no como tipos de nodo propios — así lo describe el brief.

## Decisión: nodo `Formula` con `Expression` (no estaba en el brief)

Estadística y Matemática Discreta no encajan en `Group`/`Alternatives`: el peso del examen final
varía de forma **continua** según otra nota (p. ej. `P + C + 0.1 * (8 - C) * F`), no es una elección
discreta entre esquemas fijos. Añadí un sexto caso, `Formula`, en vez de forzar la guía a encajar
en `Alternatives` (que es justo lo que el brief pide no hacer).

La primera versión guardaba la fórmula como texto sin evaluar — una laguna marcada, no una
solución. Ya tiene una segunda vuelta: `expression` es ahora un `Expression`
(`Sources/Engine/Expression.swift`), un árbol aritmético (`+ - * / min max` y un condicional
`ifGreaterOrEqual`) con un método `evaluate(_:)` que sí calcula un número dado los valores de sus
variables. `Tests/EngineTests/{Estadistica,MatematicaDiscreta}Tests.swift` lo comprueban contra
ejemplos calculados a mano de las dos guías, incluidas las dos ramas del condicional.

El caso de Matemática Discreta (`F = N si E >= 4, si no min(N, 4.5)`) se resuelve entero dentro del
mismo `Expression`, con `ifGreaterOrEqual` representando la condición sobre `E` directamente. La
primera versión de este documento proponía en cambio un `Minimum(threshold: 4, consequence:
.capAt(4.5))` normal en la variable `E`, aprovechando que encajaba con el patrón de la sección 4.
Lo descarté al tener `Expression`: la condición ya vive en la fórmula, así que un `Minimum` aparte
con el mismo efecto sería una segunda fuente de verdad para la misma regla. `Formula.minimum` queda
para el umbral de aprobado sobre el resultado ya calculado (`F >= 5`), el mismo papel que
`Group.minimum`, no para lógica que ya está dentro de la expresión.

## Otras decisiones

- **Estructura del repo**: `Package.swift` en la raíz (no en `Engine/` como sugería el brief
  original) con destino `Sources/Engine` + `Tests/EngineTests`, y `App/` con un proyecto generado
  por XcodeGen (`project.yml`, gitignored el `.xcodeproj`). Es el mismo patrón que tpapp, visto
  como referencia a petición de Miguel.
- **App de un solo target** (`Mark-iOS`, sin macOS) — el README solo anuncia iOS.
- **`Alternatives.Branch.condition`** es un `String?` libre (p. ej. `"Controles >= 4"`), no una
  expresión estructurada. El brief tampoco lo especifica todavía; no hacía falta más para que las
  3 guías de referencia encajaran.

## Qué falta (no es para ahora)

- Motor de cálculo completo: nota actual, nota proyectada, nota necesaria (búsqueda binaria, §5
  del brief) recorriendo todo el árbol (`Group`, `Alternatives`, `Bonus`...) a partir de notas
  introducidas por el usuario. Por ahora solo `Expression.evaluate` calcula algo, y solo dentro de
  un `Formula` aislado — no hay todavía un "calcula esta `Subject` con estas notas".
- `Alternatives.Branch.condition` sigue siendo un `String` libre, sin evaluar — mismo tipo de hueco
  que tenía `Formula` antes de esta vuelta. Aún no hizo falta resolverlo porque ninguna de las 3
  guías de referencia fuerza una condición real (eligen rama por sesión, no por nota).
- Casos dudosos ya anotados en cada JSON de `guide/extracted/` (régimen de matrícula a tiempo
  parcial en Estadística, componente opcional de prácticas en la oportunidad adelantada de
  Estructura de Computadores) — ninguno de los dos está modelado.
