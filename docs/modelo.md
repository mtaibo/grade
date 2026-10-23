# Modelo de evaluación

Árbol de evaluación (`Sources/Engine/`) y motor de cálculo (`Sources/Engine/Calculation.swift`),
validados contra las 3 guías de `guide/` (extraídas en `guide/extracted/*.json`, construidas en
Swift en `Sources/Engine/ReferenceSubjects.swift`). Hay una UI mínima en SwiftUI
(`App/Sources/SubjectListView.swift`) que lo deja ver funcionando — ver "Qué falta" al final para
lo que sigue sin existir.

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

## Motor de cálculo (`Calculation.swift`)

Implementa el §5 del brief sobre el árbol `Node` directamente, sin un tipo "`Subject` con notas"
aparte:

- **`Node.evaluate(_:pendingFraction:)`**: el valor de un nodo dadas las notas ya introducidas
  (`[String: Double]`, por nombre de hoja) y una fracción `0...1` de su propia escala para
  cualquier hoja sin nota — `0` da el peor caso (como si lo pendiente sacara un 0), `1` el mejor.
  Es monótona en `pendingFraction` por construcción (toda combinación es una suma de pesos no
  negativos), comprobado explícitamente en `CalculationTests` con una muestra en `[0, 1]` sobre
  las 3 asignaturas — es la propiedad que pide el brief para poder buscar binariamente.
- **`Node.neededFraction(_:target:)`**: búsqueda binaria sobre esa fracción para encontrar la nota
  necesaria — "la misma nota en todos los pendientes", tal como describe el brief para esta
  primera versión (fijar solo algunas y resolver el resto queda para el simulador, más adelante).
- **`Node.status(_:)`**: `guaranteed` / `possible` / `impossible`, comparando el peor y el mejor
  caso contra `minimumThreshold` (el `Minimum` del nodo, o 5 por defecto).
- **`Node.scaleMax`**: casi siempre 10, salvo un `Group` con `combination: .sum` cuyas hijas no
  cubren toda la escala — su propio máximo queda en `Σ pesos * 10`, para que al ponderarlo un
  `Group` ancestro dé el porcentaje correcto. Así es como "Solución de problemas" (dos pruebas al
  20% cada una, es decir 40% del total) encaja sin inventar un tipo de nodo nuevo.

No está wireado: `Requirement` (sin valor numérico, no bloquea nada todavía) ni ninguna condición
real en `Alternatives` (usa la rama por defecto o la primera) — ninguna de las 3 guías de
referencia lo necesita aún, igual que con `Formula` antes de que `Expression` existiera.

## UI mínima (`SubjectListView.swift`)

Una lista de las 3 asignaturas de referencia (`Subject.all`) → detalle con un `TextField` numérico
por nota (teclado `.decimalPad`, como un PIN: solo dígitos y coma/punto, sin teclado completo), y
debajo el resultado en vivo: nota si no entra nada más, mejor nota posible, una etiqueta de estado
(asegurado/posible/imposible) y, si es `possible`, la media que hace falta en lo pendiente.

Probada en el simulador (build + `xcrun simctl launch`): la lista carga datos reales de `Engine`
correctamente. No pude verificar visualmente la pantalla de detalle (campos de texto, resultado)
porque este entorno no tiene una ventana de Simulator.app real a la que hacer tap — solo el
framebuffer vía `simctl screenshot`. El código en sí es SwiftUI estándar (`Form`/`TextField`
/`LabeledContent`) y la lógica que muestra está cubierta por los 18 tests de `EngineTests`; aun así,
revísalo tú en tu Mac antes de darlo por bueno.

### Persistencia: `GradeStore.swift`, un puente antes de SwiftData

Las notas que se escriben en la UI se guardan con `UserDefaults` (`GradeStore.load`/`save`), como
JSON por asignatura, clave `com.migueltaibo.mark.grades.<nombre>`. Es deliberadamente provisional:
el brief ya tiene un modelo de datos pensado para SwiftData (§6 — Calificación separada del nodo,
reglas como JSON versionado, restricciones de CloudKit desde el principio), pero construirlo ahora
sería adelantarse a un diseño que todavía no se ha validado con asignaturas reales creadas por un
usuario (hoy solo hay las 3 de referencia, fijas en el código). `UserDefaults` cubre lo que se pidió
— "que se quede guardado" — sin comprometer esa decisión de antemano. Cuando llegue SwiftData, solo
`GradeStore.swift` cambia; `SubjectDetailView` ya solo conoce `load`/`save`.

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

- **Persistencia**: SwiftData, sin ella no hay forma de guardar una asignatura o una nota entre
  aperturas de la app. La UI actual es solo una demo de la lógica.
- **`Alternatives.Branch.condition`** sigue siendo un `String` libre, sin evaluar — mismo tipo de
  hueco que tenía `Formula` antes de esta vuelta. Aún no hizo falta resolverlo porque ninguna de
  las 3 guías de referencia fuerza una condición real (eligen rama por sesión, no por nota).
- **`Requirement`** no está wireado a ningún booleano de entrada — no hay forma de marcar "esto se
  cumple" ni de que bloquee el aprobado. Ninguna de las 3 guías de referencia lo necesita todavía.
- **Simulador de "fija algunas, resuelve el resto"**: `neededFraction` asume la misma nota en
  todos los componentes pendientes (tal como pide esta primera versión del brief); fijar unos y
  resolver solo otros es trabajo futuro explícito.
- Casos dudosos ya anotados en cada JSON de `guide/extracted/` (régimen de matrícula a tiempo
  parcial en Estadística, componente opcional de prácticas en la oportunidad adelantada de
  Estructura de Computadores) — ninguno de los dos está modelado.
