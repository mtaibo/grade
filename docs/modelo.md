# Modelo de evaluación

Árbol de evaluación (`Sources/Engine/`) y motor de cálculo (`Sources/Engine/Calculation.swift`),
validados contra las 9 guías de `guide/` (extraídas en `guide/extracted/*.json`, construidas en
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
  todas las asignaturas de referencia — es la propiedad que pide el brief para poder buscar binariamente.
- **`Node.neededFraction(_:target:)`**: búsqueda binaria sobre esa fracción para encontrar la nota
  necesaria — "la misma nota en todos los pendientes", tal como describe el brief para esta
  primera versión (fijar solo algunas y resolver el resto queda para el simulador, más adelante).
- **`Node.status(_:)`**: `guaranteed` / `possible` / `impossible`, comparando el peor y el mejor
  caso contra `minimumThreshold` (el `Minimum` del nodo, o 5 por defecto).
- **`Node.scaleMax`**: casi siempre 10, salvo un `Group` con `combination: .sum` cuyas hijas no
  cubren toda la escala — su propio máximo queda en `Σ pesos * 10`, para que al ponderarlo un
  `Group` ancestro dé el porcentaje correcto. Así es como "Solución de problemas" (dos pruebas al
  20% cada una, es decir 40% del total) encaja sin inventar un tipo de nodo nuevo.

**Mínimos que suspenden** (`Node.meetsMinimums`): un `Minimum` con consecuencia `.fails` en
cualquier parte (p. ej. "al menos un 40 % del examen para aprobar", Sistemas Operativos) bloquea el
aprobado aunque la media llegue al 5. Entra en `status` y en `neededFraction`: la nota necesaria es
la que alcanza la media *y* todos esos mínimos. Es monótono igual que `evaluate`, así que comparte la
misma búsqueda binaria. El modelo ya lo expresaba desde el principio; el motor no lo comprobaba hasta
que la cuarta guía lo hizo necesario — con un 10 en prácticas y un 3,8 en el examen decía "Aprobada".
**Mínimos con tope** (`capAt`): si una parte no llega a su mínimo y la consecuencia es un tope, el
resultado de su padre se limita a ese valor — "si no llegas a un 4, la nota final no pasa de 4,5"
(Diseño Software) o "de 4,9" (Informática Básica). Se aplica dentro de `evaluate`, porque cambia el
número que se ve y no solo el aprobado. También es monótono: subir esa parte por encima de su
mínimo solo puede levantar el tope. Lo pidió la segunda tanda de guías.
`.doesNotAverage` sigue sin conectarse: ninguna guía lo necesita todavía.

No está wireado: `Requirement` (sin valor numérico, no bloquea nada todavía) ni ninguna condición
real en `Alternatives` (usa la rama por defecto o la primera) — ninguna de las guías de
referencia lo necesita aún, igual que con `Formula` antes de que `Expression` existiera.

## Estructura de la app

Un `TabView` con cuatro pestañas: **Calendario**, **Asignaturas**, **Expediente** y **Ajustes**.
Calendario va a la izquierda del todo, pero la app abre en Asignaturas (`TabView(selection:)`).
El "Hoy" del brief (§10) queda cubierto de momento por el Calendario.

La app se declara en español (`CFBundleDevelopmentRegion` y `developmentLanguage: es`), para que
los componentes del sistema (calendario, selectores de fecha) no caigan al inglés.

### Calendario (`CalendarView.swift`)

- **Arriba**, el calendario mensual nativo de iOS (`UICalendarView`, envuelto porque SwiftUI no
  tiene uno que pueda marcar días), con un punto naranja en cada día con entrega o examen.
- **Debajo**, la lista de próximas entregas. Si tocas un día, solo las de ese día ("Ver todas"
  vuelve a la lista completa).
- **Cada fila**: fecha, parte y asignatura, y a la derecha la nota si ya está puesta o cuánto falta
  ("Mañana", "En 5 días", "Hace 2 días" en rojo). Al tocarla se abre la asignatura.

Los días se comparan con un tipo propio (`CalendarDay`: año, mes, día), no con `DateComponents`:
los que devuelve UIKit y los construidos desde un `Date` son iguales pero pueden tener un hash
distinto, y los puntos aparecían o no según la ejecución. Comprobado en tres ejecuciones seguidas.

### Fechas en las partes

`Grade` gana una `date` opcional en `Engine`: es la "fecha" que el brief pone en cada nodo (§6),
y así va pegada a su nota (si la renombras o la mueves, la fecha va con ella). El cálculo no la
usa. Solo las notas llevan fecha, no los grupos: lo que se entrega o se examina es una nota
concreta. Un test comprueba que un `library.json` guardado antes (sin fechas) sigue cargando.

En el editor, cada nota tiene "Fecha de entrega o examen": desactivada por defecto, y al activarla
empieza en hoy a las 23:59 (la hora típica de una entrega). En el detalle se ve debajo del nombre.

### Inicio (`HomeView.swift`)

- **Selector de curso** como fila de cápsulas bajo el título grande (el nombre del curso). Antes
  estaba en el menú del título (`toolbarTitleMenu`), pero la flecha apenas se ve y no se
  descubría. El curso elegido se recuerda por dispositivo (`@AppStorage`).
- **Resumen del curso** ("Cómo va el curso"): cuántas asignaturas están aprobadas, en juego y no
  llegan.
- **Una tarjeta por asignatura**: nombre grande, la nota actual (peor caso, lo ya asegurado, "—"
  si no hay ninguna nota, con "de 10" debajo), una
  barra 0–10 (relleno sólido hasta lo asegurado, tenue hasta el mejor caso, marca en el umbral) y
  una línea de estado ("Aprobada", "Necesitas un X en lo que falta"…). Debajo del nombre, la
  convocatoria y la fecha del examen cuando aportan algo (extraordinaria, o examen con fecha). Sin
  créditos ni "x de y notas": Miguel los vio como ruido.
- **Editar** cada asignatura deslizando la tarjeta o con pulsación larga; el pie de la lista lo
  dice, porque un gesto oculto no se descubre solo.

Los cursos de ejemplo agrupan las asignaturas según el curso que indica su guía: 1.º (Estadística,
Matemática Discreta, Álgebra, Administración y Gestión de Organizaciones, Informática Básica) y 2.º
(Estructura de Computadores, Sistemas Operativos, Diseño Software, Paradigmas de Programación). Añadir asignaturas o cursos todavía no
existe, a propósito.

### Editor de asignatura (`SubjectEditorView.swift`) — la parte modular

Una hoja con borrador ("Cancelar"/"Guardar"); la biblioteca solo cambia al guardar.

- **Asignatura**: nombre, créditos, nota para aprobar (el `Minimum` del nodo raíz).
- **Grupos**: cómo se combinan (media ponderada, suma, la mejor, la peor, las mejores N) y sus
  partes, cada una con nombre, peso en % y escala. Cada forma de combinar se explica en el pie.
  Una parte nueva se lleva el peso que falte para el 100 % (antes empezaba en 0 %), y el pie avisa
  en naranja si los pesos no suman 100 % o confirma en verde si sí. Se añaden partes (nota o grupo)
  y se borran deslizando. Un grupo dentro de otro se edita igual, de forma recursiva.
- **Fórmulas** (Estadística, Matemática Discreta): se muestra la fórmula legible y se editan sus
  variables (nombre y escala), pero no la fórmula — editar un `Expression` desde la UI es un
  problema de diseño aparte.
- **Renombrar una nota mueve su calificación guardada** con ella; las calificaciones de partes
  borradas se descartan al guardar. Dos notas con el mismo nombre bloquean el guardado (las notas
  se guardan por nombre de hoja).

Para poder listar, borrar y editar partes sin identificarlas por su nombre (que es editable),
`WeightedChild` gana un `id: UUID` en `Engine`. Es el único cambio de modelo que pidió el editor.

### Asignatura (`SubjectDetailView.swift`)

Rehecha como tarjetas (antes era un `Form` que parecía la app de Ajustes y era incómoda de rellenar):

- **Nombre** en grande y **selector Ordinaria / Extraordinaria**. Abre en la convocatoria activa
  (la extraordinaria en cuanto tenga alguna nota).
- **Resumen**: "Llevas asegurado X / 10", estado (Aprobada / En juego / No llega / Sin notas),
  barra de rango con leyenda (asegurado, hasta dónde puede llegar, con cuánto se aprueba) y una
  frase de conclusión en el color del estado: la media que hace falta en lo pendiente, que ya está
  aprobada o que ya no llega.
- **Pista inicial** mientras no hay ninguna nota: qué hacer en la pantalla y qué devuelve la app.
- **Examen de esa convocatoria**: fecha y hora, cuánto falta ("En 40 días"), y sale en el Calendario.
- **"Tus notas"**: encabezado con la instrucción (tocar una casilla, lo vacío cuenta como
  pendiente). Las casillas miden 44 pt de alto, se resaltan al escribir en ellas y el "sobre" es
  una casilla visible, no un número suelto tras una barra.
- **Una tarjeta por parte**: nombre, peso y los puntos que aporta de los que puede dar ("1,6 / 2").
  La entrada depende de cómo se pone la nota:
  - **Nota**: valor y "sobre".
  - **Porcentaje**: "85 %".
  - **Letras**: botones A B C…
  - **Grupo de 4 o más notas sueltas** (p. ej. 10 pruebas de prácticas): cuadrícula compacta de
    casillas ("P1", "P2"…), no una lista.
  - **Otros grupos**: filas con nombre.
- **Fórmulas**: una tarjeta por variable y la fórmula legible debajo.

### Convocatorias: ordinaria y extraordinaria

Cada asignatura guarda las notas de las dos convocatorias por separado (`entries` y
`extraordinaryEntries` en `SubjectRecord`, más la fecha del examen de cada una). Es la "Calificación
separada del nodo, por convocatoria" del brief (§6), en versión JSON.

La extraordinaria usa la misma estructura que la ordinaria, y la `recovery` de cada nota decide qué
pasa:

- **Se guarda** (`notRecoverable`, `savedForExtraordinary`, `savedForNextYear`,
  `partiallyRecoverableInFinal`): aparece ya puesta con la nota de la ordinaria ("De la ordinaria").
  Si la cambias, se guarda como nota de la extraordinaria, y "Volver a la de la ordinaria" la
  deshace.
- **Se repite** (sin `recovery` o `recoverableInExtraordinary`, lo normal en un examen): empieza vacía.

En el editor es un único interruptor por nota: "Se guarda para la extraordinaria". Al ajustar las
asignaturas de ejemplo, Estructura de Computadores pasa a tener las prácticas no recuperables e
Informática Básica las conserva, como dicen sus guías.

Limitación conocida: no hay una estructura distinta para la extraordinaria. Una guía que cambia los
pesos en la extraordinaria (Estructura de Computadores: examen al 80 %) queda aproximada. Tener dos
árboles por asignatura complicaría bastante el editor y todavía no compensa.

### Formas de poner una nota (`Grade.inputStyle`)

`Grade` gana un `inputStyle` opcional en `Engine`: nota (por defecto), porcentaje o letras con su
equivalencia sobre 10. Es la "escala" que el brief pone en cada nodo (§4/§6); el motor no la usa,
porque la app convierte lo que escribes (`GradeEntry`) a la escala del nodo antes de calcular. Un
porcentaje se guarda sobre 100, y una letra como su valor sobre 10 junto a la letra, para volver a
mostrarla. Equivalencia por defecto: A 10, B 7,5, C 5, D 2,5, E 0, editable por nota en el editor.
Cada letra tiene un `id` estable para poder editar la tabla sin identificar filas por su contenido.

En el editor también se pueden añadir **varias notas de golpe** ("10 notas" → Prueba 1…10, con el
mismo peso), pensado para prácticas con muchas pruebas cortas.

### Nota sobre otra escala: `GradeEntry` (valor + "sobre cuánto")

Un profesor puede dar una nota sobre una escala distinta a la del nodo del modelo (p. ej. sobre 2
en vez de sobre 10). Cada entrada guarda `{ value, outOf, letter? }` y `SubjectProgress` la convierte a la
escala del nodo (`value / outOf * node.scaleMax`) antes de pasársela al motor — el motor sigue
viendo solo `[String: Double]` en su propia escala. Cuando el "sobre" no coincide con el del nodo,
la fila muestra la conversión ("= 7,5/10").

### Expediente (`RecordView.swift`) y Ajustes (`SettingsView.swift`)

- **Expediente**: media ponderada por créditos (brief §2) de las asignaturas con todas las notas
  puestas, créditos superados, y cada asignatura por curso con su nota final o "En curso".
- **Ajustes**: borrar todas las notas, restaurar las asignaturas de ejemplo (con confirmación) y
  la versión.

### Estado y persistencia: `Library.swift`, un puente antes de SwiftData

Cursos, asignaturas (árbol editable) y notas viven en un `Library` (`@Observable`, inyectado por
entorno) y se guardan en un único JSON en Application Support. Todos los tipos de `Engine` son
`Codable`, con un test que comprueba que las asignaturas de referencia sobreviven a la ida y vuelta por JSON.
Toda mutación pasa por un método de `Library`, así que solo hay un sitio que guarda.

Sustituye al `UserDefaults` de antes, que solo guardaba notas: al poder editar la estructura, hay
que guardar también el árbol. La primera vez migra las notas que hubiera en `UserDefaults`.

El fichero recuerda qué asignaturas de ejemplo ya se ofrecieron (`offeredExamples`). Así, una
asignatura de referencia nueva (Sistemas Operativos y luego otras cinco) llega sola a una instalación existente, sin
tocar sus notas ni sus cambios, y sin volver a meter una que ya estaba. Los ficheros del formato
anterior (una lista de cursos sin más) se siguen leyendo: se da por ofrecido lo que contienen.
Comprobado en el simulador con un fichero antiguo con notas.

Sigue siendo provisional: el brief tiene pensado un modelo SwiftData (§6, con CloudKit). Todavía no
compensa construirlo — no existen asignaturas creadas por un usuario, solo las 3 de ejemplo.
`SubjectProgress` junta lo que el motor dice de una asignatura y lo usan las tres pantallas.

### Verificación

Comprobado con capturas en el simulador: la pantalla de asignatura nueva (ordinaria con cuadrícula
de 10 pruebas, letras y porcentaje; extraordinaria con notas que pasan de la ordinaria), el editor
de letras, inicio (con selector de curso y pestañas), editores,
Expediente, Ajustes, Calendario con fechas de ejemplo (también en oscuro), la fecha en el editor de
una parte y en el detalle. Como en este entorno no se puede tocar el simulador, las pantallas que no
son la inicial se abrieron con un selector temporal por variable de entorno, que se quitó después.
Lo que no se ha podido probar es la interacción: abrir el menú de curso, deslizar para editar,
guardar un cambio y escribir notas.

## Guías de referencia

9 guías, todas del Grado en Ingeniería Informática de la UDC salvo Matemática Discreta (Grado en
Ciencia e Ingeniería de Datos). Cada una tiene su PDF en `guide/`, su extracción en
`guide/extracted/` citando el texto original y su árbol en `ReferenceSubjects.swift`, con tests.

| Guía | Forma | Qué aportó al modelo |
| --- | --- | --- |
| Estructura de Computadores | Media ponderada con un subgrupo de suma | `scaleMax` de un grupo `.sum` |
| Estadística | Fórmula, peso del examen variable | `Formula` + `Expression` |
| Matemática Discreta | Fórmula con tope condicional | condicional en `Expression` |
| Sistemas Operativos | Media + mínimo del 40 % en el examen | mínimos que suspenden (`meetsMinimums`) |
| Álgebra | Media ponderada | nada (encaja) |
| Administración y Gestión de Organizaciones | Media ponderada de 4 partes | nada (encaja) |
| Informática Básica | Media en puntos + tope de 4,9 bajo el mínimo | `capAt` conectado al motor |
| Diseño Software | Media + tope de 4,5 bajo el mínimo de cualquier parte | (`capAt`, igual) |
| Paradigmas de Programación | Fórmula, igual que Estadística | nada (encaja) |

El brief pide seguir añadiendo guías hasta que 10 seguidas no obliguen a cambiar el modelo. De esta
segunda tanda de 5, tres encajaron sin cambios y dos pidieron conectar `capAt`, que el modelo ya
tenía pero el motor no aplicaba. El contador vuelve a empezar desde Paradigmas de Programación.

Dudas abiertas de esta tanda (detalle en cada JSON): Álgebra tiene dos descripciones cortadas con
"[...]" en la propia guía, que podrían esconder una regla. En Diseño Software, la tabla dice "no hace
media" pero el texto concreta un tope de 4,5 (se modela el tope), y las notas se guardan para la
segunda oportunidad solo si son ≥ 4, un matiz que el modelo de recuperación no tiene.

## Icono de la app

`App/Sources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png`: un check minimalista (trazo
negro redondeado sobre blanco), generado con PIL en vez de con Xcode/un diseñador — mismo estilo
plano de un solo color que el icono de tpapp. Un único tamaño universal (como ya tenía configurado
`Contents.json`), sin variantes para modo oscuro/tintado. Visto en la pantalla de inicio del
simulador, se lee bien incluso en miniatura.

## Otras decisiones

- **Estructura del repo**: `Package.swift` en la raíz (no en `Engine/` como sugería el brief
  original) con destino `Sources/Engine` + `Tests/EngineTests`, y `App/` con un proyecto generado
  por XcodeGen (`project.yml`, gitignored el `.xcodeproj`). Es el mismo patrón que tpapp, visto
  como referencia a petición de Miguel.
- **App de un solo target** (`Mark-iOS`, sin macOS) — el README solo anuncia iOS.
- **`Alternatives.Branch.condition`** es un `String?` libre (p. ej. `"Controles >= 4"`), no una
  expresión estructurada. El brief tampoco lo especifica todavía; no hacía falta más para que las
  guías de referencia encajaran.

## Qué falta (no es para ahora)

- **SwiftData** en lugar del JSON de `Library` (brief §6), cuando haya asignaturas creadas por
  usuarios.
- **Editar fórmulas** (añadir/mover/borrar asignaturas ya existe; cursos se crean solos por año).
- **`Alternatives.Branch.condition`** sigue siendo un `String` libre, sin evaluar — mismo tipo de
  hueco que tenía `Formula` antes de esta vuelta. Aún no hizo falta resolverlo porque ninguna de
  las guías de referencia fuerza una condición real (eligen rama por sesión, no por nota).
- **`Requirement`** no está wireado a ningún booleano de entrada — no hay forma de marcar "esto se
  cumple" ni de que bloquee el aprobado. Ninguna de las guías de referencia lo necesita todavía.
- **Simulador de "fija algunas, resuelve el resto"**: `neededFraction` asume la misma nota en
  todos los componentes pendientes (tal como pide esta primera versión del brief); fijar unos y
  resolver solo otros es trabajo futuro explícito.
- Casos dudosos ya anotados en cada JSON de `guide/extracted/` (régimen de matrícula a tiempo
  parcial en Estadística, componente opcional de prácticas en la oportunidad adelantada de
  Estructura de Computadores) — ninguno de los dos está modelado.

## Año, cuatrimestre y pantalla principal (oct 2026)

- `Course` guarda `year` (el nombre «N.º año» se deriva). `SubjectRecord.term` es el cuatrimestre
  **absoluto** de la carrera (año 2 → cuatrimestres 3 y 4) y es opcional (`nil` = anual). Solo la UI
  lo muestra relativo al año («2.º año · 1.er cuatrimestre»): ver `Period.swift`.
- `Library.Snapshot.version` = 2; las bibliotecas anteriores reciben el cuatrimestre de las
  asignaturas de ejemplo (campo `period` de cada guía) una sola vez.
- Pestañas: Calendario / Asignaturas / Cuenta (Expediente y ajustes dentro de Cuenta).
- Inicio: título grande con año + cuatrimestre, tarjetas con solo icono y nombre, menú de vista
  arriba a la izquierda (solo «Tarjetas»), menú de periodo y «+» arriba a la derecha. Las anuales
  salen bajo «Todo el año». Icono y color de la tarjeta se derivan del nombre/id, no se guardan.

### Carrera personalizable y tarjetas (oct 2026)

- `DegreeSettings` (en `Library`, guardado en el snapshot): años de carrera, periodos por año y
  nombre del periodo («Cuatrimestre», «Semestre»…). Se edita en Cuenta → Tu carrera. Cambiar los
  periodos por año reubica cada asignatura en su mismo año y posición, recortada al nuevo máximo.
- `SubjectRecord.symbol` / `colorName` (opcionales): icono y color elegidos en «Personalizar»; si
  faltan, `SubjectStyle` los deriva del nombre/id.
- Menú de la tarjeta: Personalizar, Mover, Editar evaluación, Eliminar.

## Plantillas de carrera (oct 2026)

`Sources/Engine/DegreeTemplates.swift`: un `DegreeTemplate` es una lista de asignaturas con su año y su cuatrimestre *relativo* (1.º o 2.º del año; la app lo convierte al número absoluto con los ajustes de Tu carrera). La primera es `.informatica` (Grado en Ingeniería Informática, UDC, guías 2025/26): 1.º completo y el 1.er cuatrimestre de 2.º (15 asignaturas; falta el 2.º cuatrimestre de 2.º). En la app vive en Cuenta → Plantillas; «Añadir a mi carrera» (`Library.apply`) añade lo que no esté ya por nombre en ese curso, así que repetirlo no duplica ni toca notas.

Ya no se siembran asignaturas de ejemplo al instalar: la app arranca vacía y se carga una plantilla o se añaden a mano. «Restaurar ejemplos» pasó a «Borrar todas las asignaturas».

Siete guías nuevas modeladas (cada una con su JSON citado en `guide/extracted/` y tests a mano en `InformaticaTemplateTests`): Cálculo (fórmula tipo Estadística con un `ifGreaterOrEqual` para el mínimo del examen), Programación I, Matemática Discreta del Grado en Informática (`matematicaDiscretaGEI`, distinta de la GCED, cuya guía está cortada con «[…]»), Fundamentos de los Computadores (mínimo del 25 % de cada parte con tope 4,9), Programación II (110 %: la solución de problemas es un punto extra solo con la asignatura aprobada), Tecnología Electrónica (suma de puntos, mitad si el examen < 1,5) y Algoritmos (la prueba objetiva agrupa teoría 55 % y prácticas 20 %).

Límites conocidos: sigue sin haber árbol propio para la extraordinaria. Programación I (examen único al 100 %) y Fundamentos (examen al 70 %, sin controles) la aproximan marcando partes como recuperables. El PDF `q3/estruturaComputadores.pdf` era el del *Máster* (código 100571), no el del Grado: se mantiene el modelo del Grado (202314), que tiene los mismos pesos.

## Examen final, colores, editar partes y copia de seguridad (oct 2026)

- `Grade.isFinalExam` marca el examen final (todas las plantillas lo llevan; las asignaturas guardadas antes lo reciben una vez por nombre en `Library.flagFinalExams`). Una parte cuyas notas son todas examen final sale en su propia tarjeta (`ExamCard`) con un hueco Ordinaria y otro Extraordinaria, cada uno con su nota, su barra y su fecha; tocar un hueco abre solo esa nota en esa convocatoria. Ya no hay selector de convocatoria: el resto de partes usa `activeSession`.
- Barras: azules mientras falte alguna nota de la sección; completa, color por nota: <5 rojo, <7 amarillo, <9 verde, ≥9 morado (`GradeBand`). La longitud es la nota de la parte sobre su máximo.
- Editor: en cada parte, «Cuántas notas» (`Node.resizeNotes`) la convierte en place entre una nota y N notas iguales; el mínimo de la nota pasa al grupo. «Es el examen final» en los ajustes de cada nota.
- Copia de seguridad: `.mark` (`com.migueltaibo.mark.backup`, JSON) con todos los cursos, asignaturas, notas, fechas y ajustes de carrera (`Backup.swift`, `MarkBackup`, versión 1). Cuenta → Copia de seguridad: exportar (hoja de compartir) e importar; abrir un `.mark` desde Archivos/AirDrop pasa por la misma confirmación. Importar sustituye todo.

## Guía docente en el móvil (oct 2026)

Menú `…` de cada asignatura: sin guía solo «Subir guía» (selector de PDF, se valida con `PDFDocument`); con guía, «Abrir guía» (visor `PDFView` en una hoja, con compartir) y «Borrar guía». Los PDF viven en `Application Support/Guides/<id de la asignatura>.pdf` (`Library.setGuide/removeGuide/guideURL`, `guideIDs` observable) y se borran con la asignatura. Van dentro del `.mark` (`MarkBackup.guides`, id → datos en base64, opcional: las copias antiguas siguen abriéndose); importar sustituye también las guías.

## Simulador (oct 2026)

Menú `…` → «Simulador»: abre a pantalla completa la misma pantalla de asignatura sobre una `Library(simulating:)` desechable (una copia en memoria de la asignatura con sus notas actuales, sin archivo: `save()` no hace nada). Todo lo que se escribe vive solo ahí y se pierde al salir con la ✕ (arriba a la izquierda, sustituye al `<`). Dentro se oculta el menú `…` (nada de editar, guías ni fechas) y sale una etiqueta «Simulador · no se guarda nada». Se detecta con `EnvironmentValues.isSimulating`.

## Editor de fórmulas (oct 2026)

`Sources/Engine/FormulaText.swift`: `Expression.parse(_:variables:)` lee una fórmula escrita a mano (`+ - * /`, paréntesis, `min(a; b)`, `max(a; b)`, `si(a >= b; entonces; si no)` también con `<=`; decimales con coma o punto; argumentos separados por `;`) con errores legibles, y `Expression.source` la imprime de vuelta (las 6 fórmulas de referencia hacen ida y vuelta, `FormulaTextTests`). `renamingVariable` renombra una letra en toda la fórmula. `Formula.maxShare(of:)` calcula lo máximo que puede aportar una variable a la nota (en puntos sobre 10).

En el editor, una asignatura con fórmula tiene: un campo de texto de la fórmula con botones para insertar variables y operadores (se aplica en cuanto se lee; si no, queda la última buena y sale el motivo), una vista previa (todo al máximo / todo a 0) y la lista de variables (letra, nombre, cuántas notas, cómo se pone cada una; añadir; borrar solo si la fórmula no la usa). Al revés, el grupo raíz (media ponderada o suma) tiene «Convertir en fórmula»: cada parte pasa a una variable (inicial del nombre) y los pesos a coeficientes. En la pantalla de asignatura las partes de una fórmula muestran «hasta N %».
