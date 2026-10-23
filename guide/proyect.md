# App universitaria de notas — Brief del proyecto

Este documento explica qué es el proyecto, por qué existe y cómo quiero que se trabaje en él. Léelo entero antes de empezar.

---

## 1. Quién soy y por qué hago esto

- Soy Miguel, estudiante de Ingeniería Informática en la Universidade da Coruña (UDC).
- Programo en Swift y SwiftUI. Mi objetivo a largo plazo es trabajar como ingeniero de software en Apple.
- Hasta ahora todos mis proyectos son personales. Con este quiero publicar mi primera app en la App Store y ganar algo de dinero con ella, aunque sea poco.

Intención del proyecto, por orden de importancia:

1. **Validar rápido.** No quiero pasar meses construyendo algo que nadie use. Primero una versión mínima que se pueda probar con estudiantes reales.
2. **Portfolio.** Una app publicada, con usuarios reales y bien construida por dentro (arquitectura limpia, tests, frameworks nativos de Apple).
3. **Ingresos modestos.** Gratis con una parte de pago. Cubrir los 99 € anuales del Apple Developer Program ya sería un buen resultado el primer año.
4. **Uso propio.** Yo mismo la voy a usar cada día con mis asignaturas.

---

## 2. Qué es la app

Una app de iOS para estudiantes universitarios que representa **cualquier sistema de evaluación** y te dice en cada momento:

- Qué nota llevas en cada asignatura.
- **Cuánto necesitas sacar en lo que queda** para aprobar o para llegar a una nota objetivo.
- Qué fechas tienes (entregas, exámenes).
- Tu media del expediente ponderada por créditos.

### Lo que la diferencia

Las apps de estudiantes que existen son agendas genéricas, normalmente en inglés. Ninguna entiende el sistema de evaluación de las universidades españolas:

- Nota mínima en un componente para que haga media.
- Parciales liberatorios.
- Prácticas obligatorias o no recuperables.
- Convocatoria ordinaria y extraordinaria.
- Pesos que cambian según la nota de otra parte. Ejemplo real: 40 % final, 40 % controles, 20 % prácticas; pero si los controles no llegan a 4, el final pasa a valer un 80 %.

La pregunta central que la app responde es: **"¿cuánto necesito sacar en el final?"**

### Principios

- **Modelo flexible, interfaz simple.** Toda la complejidad vive en el motor de evaluación. El usuario nunca ve fórmulas.
- **Local primero.** SwiftData, con sincronización por iCloud (CloudKit) más adelante. Sin servidor propio ni cuentas.
- **Español primero.** Escala de 0 a 10, convocatorias, créditos ECTS.
- **Estética nativa de Apple.** Minimalista, siguiendo las Human Interface Guidelines. Nada de diseño genérico.

---

## 3. Estrategia: empezar pequeño y crecer con guías reales

No vamos a diseñar el modelo perfecto de antemano. El plan es:

1. **Empezar con 3 guías docentes muy distintas entre sí** (están en la carpeta `guias/`).
2. Diseñar el modelo mínimo que cubra esas 3.
3. Implementar el **motor de cálculo con tests**. Cada guía es un caso de test.
4. Ir añadiendo guías de 5 en 5, de ramas distintas, y ajustar el modelo cuando algo no encaje.
5. Cuando 10 guías seguidas no obliguen a cambiar el modelo, está listo y empieza la interfaz completa.

Antes de publicar, el esquema de datos se puede cambiar libremente. Por eso iterar es seguro ahora. La restricción llega al publicar con CloudKit.

### Versión mínima para validar (prioridad absoluta)

Antes de la app completa, una versión mínima que pueda probar con unos 20 compañeros de distintas carreras por TestFlight, **antes de los exámenes de enero**:

- Crear asignaturas y configurar su evaluación.
- Introducir notas.
- Ver la nota actual y **cuánto necesitas en lo que queda**.

Sin widgets, sin expediente, sin notificaciones, sin pagos, sin IA. Si la usan y piden cosas, se sigue. Si nadie la abre, se ha perdido poco tiempo.

---

## 4. Modelo de evaluación (propuesta inicial, a validar con las guías)

La nota de una asignatura es un **árbol de componentes**. Cada nodo decide cómo se calcula a partir de sus hijos.

### Tipos de nodo

| Nodo | Qué hace | Ejemplo |
| --- | --- | --- |
| Nota | Valor introducido por el usuario, con su escala | Parcial 1: 7,5 sobre 10 |
| Grupo | Combina hijos: media ponderada, suma, máximo, mínimo, mejores N de M | Prácticas: media de las 4 mejores de 5 |
| Alternativas | Varios esquemas; elige uno por condición o el mejor | Final al 80 % si los controles no llegan a 4 |
| Bonificación | Suma puntos al padre, con tope | +0,5 por participación, máximo 10 |
| Requisito | Condición sin nota que bloquea el aprobado | Asistencia mínima del 80 % |

### Reglas que puede llevar cualquier nodo

- **Nota mínima**, con consecuencia: no hace media, la nota del padre queda limitada (por ejemplo a 4,5) o la asignatura queda suspensa.
- **Liberatorio**: si se supera el umbral, elimina esa materia del final.
- **Recuperación**: recuperable en la extraordinaria, no recuperable, nota guardada para la extraordinaria, guardada para el curso siguiente.
- **Escala**: nota máxima distinta de 10, apto/no apto, no presentado (distinto de un 0).

### Ejemplo

```
Asignatura
└─ Alternativas (por condición)
   ├─ Si Controles ≥ 4:  Final 40 % · Controles 40 % · Prácticas 20 %
   └─ Si no:             Final 80 % · Prácticas 20 %
```

### Casos conocidos que el modelo debería cubrir

Media ponderada simple · nota mínima para hacer media · nota limitada si no se llega al mínimo · parciales liberatorios · continua o final, la mejor · pesos condicionales · mejores N de M · prácticas no recuperables · nota guardada para la extraordinaria · prácticas convalidadas de otro curso · asistencia obligatoria · apto/no apto · bonificaciones con tope · escalas distintas (sobre 100, sobre 20) · no presentado · evaluación única alternativa · matrícula de honor (marca manual, no calculable).

Esta lista es orientativa. Si una guía no encaja, el modelo cambia. No fuerces una guía a encajar en el modelo.

---

## 5. Motor de cálculo

Es la pieza más importante del proyecto.

- **Swift Package independiente**, sin dependencias de SwiftUI ni SwiftData. Trabaja con tipos valor (`struct`, `enum`).
- Entrada: el árbol de una asignatura y sus calificaciones. Salida: resultados.

### Qué calcula

- **Nota actual**: sobre lo evaluado y sobre el total.
- **Nota proyectada**: suponiendo una nota en lo pendiente.
- **Nota necesaria**: el mínimo en lo pendiente para aprobar o para llegar a una nota objetivo.
- **Estado**: aprobado asegurado, aprobado posible, imposible, bloqueado por un requisito.

### Nota necesaria

- La nota final no baja al subir una nota parcial (monotonía). Por eso una **búsqueda binaria** encuentra el mínimo necesario aunque haya condiciones, máximos y topes.
- Con varios componentes pendientes, se calcula la misma nota en todos. Más adelante, el simulador permitirá fijar algunos y resolver el resto.
- Comprueba la monotonía en los tests. Si alguna guía la rompe, avísame: cambia el enfoque.

### Tests

- Cada guía docente se convierte en un caso de test con notas de ejemplo y resultado esperado calculado a mano.
- Incluye casos límite: justo en el mínimo, no presentado, aprobado imposible, todo evaluado.
- Usa Swift Testing.

---

## 6. Modelo de datos (para cuando llegue la app)

Todavía no es prioridad, pero el motor debe diseñarse pensando en esto:

| Entidad | Campos principales | Relaciones |
| --- | --- | --- |
| Curso | año académico, nombre | tiene periodos |
| Periodo | nombre (1.er cuatrimestre, anual), fechas | tiene asignaturas |
| Asignatura | nombre, créditos ECTS, tipo, color | tiene un nodo raíz |
| Nodo | tipo, nombre, peso, orden, escala, fecha, reglas | padre e hijos |
| Calificación | valor, convocatoria, estado (presentado, NP) | pertenece a un nodo |
| Evento | título, fecha, tipo | nodo opcional |

Decisiones ya tomadas:

- **Calificación separada del nodo**, para soportar ordinaria, extraordinaria y repetir curso.
- **Reglas guardadas como JSON con número de versión** dentro del nodo, no como entidades. CloudKit no permite borrar ni renombrar campos después de publicar; con JSON versionado, el código migra las reglas al leerlas.
- **Restricciones de CloudKit desde el principio**: propiedades opcionales o con valor por defecto, relaciones opcionales, sin `@Attribute(.unique)`.
- Capa de traducción entre las entidades de SwiftData y los tipos valor del motor.

---

## 7. Tareas de esta primera sesión

1. **Leer las 3 guías docentes** de `guias/`. Solo interesa el apartado de evaluación.
2. **Extraer cada una** a `guias/extraidas/<nombre>.json` con un esquema común: componentes, pesos, mínimos, condiciones, recuperación, asistencia, bonificaciones y cualquier caso raro, citando brevemente el texto original de cada regla.
3. **Escribir `docs/modelo.md`**: el modelo de evaluación propuesto, por qué, cómo se expresa cada guía con él y qué queda dudoso.
4. **Crear el Swift Package del motor** con los tipos del modelo y el cálculo de nota actual y nota necesaria.
5. **Escribir los tests**: al menos un caso por guía, más casos límite.
6. **Terminar con un resumen**: qué funciona, qué no encaja, qué decisiones necesitas que tome yo.

### Fuera de esta sesión

- Interfaz de la app (SwiftUI).
- SwiftData y CloudKit.
- Widgets, notificaciones, pagos.
- IA de importación de guías.

---

## 8. Estructura del repositorio

```
/
├─ PROYECTO.md          este documento
├─ guias/               PDFs de guías docentes
│  └─ extraidas/        una extracción JSON por guía
├─ docs/
│  └─ modelo.md         modelo de evaluación y decisiones
├─ Engine/              Swift Package del motor de cálculo
│  ├─ Sources/
│  └─ Tests/
└─ App/                 proyecto de Xcode (más adelante)
```

---

## 9. Forma de trabajar

- **Código, nombres y comentarios en inglés. Documentación en español.**
- Swift moderno: Swift 6, concurrencia estricta, Swift Testing, Observation.
- Simple antes que genérico. No añadas abstracciones que ninguna guía real necesite todavía.
- **Pregúntame antes de una decisión difícil de deshacer.** Para lo demás, decide y explícalo en `docs/modelo.md`.
- Si una guía es ambigua, no inventes la regla: márcala como dudosa.
- Cuando cambies el modelo, todos los tests de guías anteriores deben seguir pasando.
- Prefiero ficheros completos a fragmentos sueltos cuando me enseñes código.

---

## 10. Lo que viene después (contexto, no para ahora)

- **Monetización**: gratis con todo el motor de evaluación; pago único (3-5 €) para cursos ilimitados, expediente, widgets y plantillas propias.
- **IA de importación (de pago)**: el usuario comparte el PDF de la guía y la asignatura queda configurada. Primero se probará con Foundation Models en el dispositivo; si no es fiable, una API en la nube. Las extracciones de `guias/extraidas/` servirán para evaluar su calidad.
- **UX de configuración**: plantillas de partida, editor progresivo, reglas expresadas como frases ("si Controles es menor que 4, el Final pasa a valer un 80 %"), vista previa en vivo.
- **Pantallas**: Hoy, Asignaturas, Expediente, Ajustes. Detalle de asignatura con la nota actual y "necesitas un X en el final" bien visibles.
- **Publicación**: TestFlight con compañeros en enero; App Store a principios de febrero de 2027, con el inicio del segundo cuatrimestre.
