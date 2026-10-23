/// The 3 reference syllabi from `guide/` (ordinary session), as real evaluation trees — one
/// definition shared by `EngineTests` and the app's demo UI, instead of building each tree twice.
extension Subject {
    public static let estructuraComputadores = Subject(
        name: "Estructura de Computadores",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.20, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .notRecoverable))),
                WeightedChild(weight: 0.40, node: .group(Group(
                    name: "Solución de problemas",
                    combination: .sum,
                    children: [
                        WeightedChild(weight: 0.20, node: .grade(Grade(name: "Prueba 1"))),
                        WeightedChild(weight: 0.20, node: .grade(Grade(name: "Prueba 2"))),
                    ]
                ))),
                WeightedChild(weight: 0.40, node: .grade(Grade(name: "Prueba objetiva"))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    public static let estadistica = Subject(
        name: "Estadística",
        ectsCredits: 6,
        root: .formula(Formula(
            name: "Nota final",
            expression: .add(
                .add(.variable("P"), .variable("C")),
                .multiply(
                    .multiply(.constant(0.1), .subtract(.constant(8), .variable("C"))),
                    .variable("F")
                )
            ),
            variables: [
                "P": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 2, recovery: .notRecoverable)),
                "C": .grade(Grade(name: "Controles (temas 1 y 2)", scaleMax: 2, recovery: .partiallyRecoverableInFinal)),
                "F": .grade(Grade(name: "Examen final", scaleMax: 10)),
            ]
        ))
    )

    public static let matematicaDiscreta = Subject(
        name: "Matemática Discreta",
        ectsCredits: 6,
        root: .formula(Self.matematicaDiscretaFormula)
    )

    private static let matematicaDiscretaFormula: Formula = {
        let n = Expression.add(
            .add(.variable("P"), .variable("M")),
            .multiply(
                .multiply(.constant(0.1), .subtract(.constant(7), .variable("M"))),
                .variable("E")
            )
        )
        return Formula(
            name: "Nota final",
            expression: .ifGreaterOrEqual(
                lhs: .variable("E"), rhs: .constant(4),
                then: n,
                otherwise: .min(n, .constant(4.5))
            ),
            variables: [
                "P": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 3, recovery: .notRecoverable)),
                "M": .grade(Grade(name: "Prueba Moodle", scaleMax: 2, recovery: .partiallyRecoverableInFinal)),
                "E": .grade(Grade(name: "Examen final", scaleMax: 10)),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        )
    }()

    /// The first guide with a minimum on a single part (40% of the exam) that fails the subject even
    /// when the average reaches 5.
    public static let sistemasOperativos = Subject(
        name: "Sistemas Operativos",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.25, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.75, node: .grade(Grade(name: "Prueba objetiva", minimum: Minimum(threshold: 4, consequence: .fails)))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    public static let algebra = Subject(
        name: "Álgebra",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.30, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.70, node: .grade(Grade(name: "Prueba objetiva"))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    public static let administracionGestionOrganizaciones = Subject(
        name: "Administración y Gestión de Organizaciones",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Prácticas a través de TIC", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Seminario", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Solución de problemas", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.70, node: .grade(Grade(name: "Prueba mixta"))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Graded in points like the guide (labs out of 4, exam out of 6); under 2.4 on the exam caps
    /// the final grade at 4.9.
    public static let informaticaBasica = Subject(
        name: "Informática Básica",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.40, node: .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 4, recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.60, node: .grade(Grade(
                    name: "Prueba mixta",
                    scaleMax: 6,
                    minimum: Minimum(threshold: 2.4, consequence: .capAt(4.9)),
                    recovery: .recoverableInExtraordinary
                ))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Under 4 on either labs or the exam caps the final grade at 4.5.
    public static let disenoSoftware = Subject(
        name: "Diseño Software",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.33, node: .grade(Grade(
                    name: "Prácticas de laboratorio",
                    minimum: Minimum(threshold: 4, consequence: .capAt(4.5)),
                    recovery: .savedForExtraordinary
                ))),
                WeightedChild(weight: 0.67, node: .grade(Grade(
                    name: "Prueba objetiva",
                    minimum: Minimum(threshold: 4, consequence: .capAt(4.5)),
                    recovery: .savedForExtraordinary
                ))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Same shape as Estadística: practical tests consolidate up to 20% (P, out of 2) and the
    /// exam is worth whatever is left up to 80%.
    public static let paradigmasProgramacion = Subject(
        name: "Paradigmas de Programación",
        ectsCredits: 6,
        root: .formula(Formula(
            name: "Nota final",
            expression: .add(
                .add(.variable("L"), .variable("P")),
                .multiply(
                    .multiply(.constant(0.1), .subtract(.constant(8), .variable("P"))),
                    .variable("E")
                )
            ),
            variables: [
                "L": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 2, recovery: .savedForExtraordinary)),
                "P": .grade(Grade(name: "Pruebas prácticas", scaleMax: 2, recovery: .savedForExtraordinary)),
                "E": .grade(Grade(name: "Prueba objetiva", scaleMax: 10)),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    public static let all: [Subject] = [
        estructuraComputadores, estadistica, matematicaDiscreta, sistemasOperativos,
        algebra, administracionGestionOrganizaciones, informaticaBasica, disenoSoftware, paradigmasProgramacion,
    ]
}
