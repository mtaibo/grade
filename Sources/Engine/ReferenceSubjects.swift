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

    // MARK: - Ingeniería Informática (UDC) syllabi, 2025/26

    /// Matemática Discreta of the Informática degree (202306) — not the GCED guide above. The guide's
    /// own text is cut off right after "Para aprobar la asignatura es necesario […]", so a possible
    /// exam minimum is unknown (see `guide/extracted/matematicaDiscretaGEI.json`).
    public static let matematicaDiscretaGEI = Subject(
        name: "Matemática Discreta",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.20, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.80, node: .grade(Grade(name: "Prueba objetiva"))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Three seminar controls give up to 60% (S, in points out of 6); the exam takes whatever is
    /// left (40–100%). Under 2.5 on the exam the seminars are not added and only the exam counts.
    public static let calculo = Subject(
        name: "Cálculo",
        ectsCredits: 6,
        root: .formula(Formula(
            name: "Nota final",
            expression: .ifGreaterOrEqual(
                lhs: .variable("E"), rhs: .constant(2.5),
                then: .add(
                    .variable("S"),
                    .multiply(.multiply(.constant(0.1), .subtract(.constant(10), .variable("S"))), .variable("E"))
                ),
                otherwise: .variable("E")
            ),
            variables: [
                "S": .group(Group(
                    name: "Seminarios",
                    combination: .sum,
                    children: (1...3).map { WeightedChild(weight: 0.20, node: .grade(Grade(name: "Control \($0)", recovery: .savedForExtraordinary))) }
                )),
                "E": .grade(Grade(name: "Examen final")),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// At least 3.5 on the final exam and 5 overall. The second sitting is one exam worth 100%,
    /// which the shared tree can't express, so its parts are all retaken.
    public static let programacion1 = Subject(
        name: "Programación I",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.30, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .recoverableInExtraordinary))),
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Prueba práctica", recovery: .recoverableInExtraordinary))),
                WeightedChild(weight: 0.60, node: .grade(Grade(name: "Examen final", minimum: Minimum(threshold: 3.5, consequence: .fails)))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Under 25% of any part's maximum the guide fails the subject with a 4.9 even if the total
    /// reaches 5 (read as 25% of each part, not of the total — see the extraction's doubtful list).
    public static let fundamentosComputadores = Subject(
        name: "Fundamentos de los Computadores",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.30, node: .grade(Grade(
                    name: "Prácticas de laboratorio",
                    minimum: Minimum(threshold: 2.5, consequence: .capAt(4.9)),
                    recovery: .savedForExtraordinary
                ))),
                WeightedChild(weight: 0.30, node: .grade(Grade(
                    name: "Controles",
                    minimum: Minimum(threshold: 2.5, consequence: .capAt(4.9)),
                    recovery: .recoverableInExtraordinary
                ))),
                WeightedChild(weight: 0.40, node: .grade(Grade(
                    name: "Examen final",
                    minimum: Minimum(threshold: 2.5, consequence: .capAt(4.9))
                ))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    /// Labs 40% and exam 60%, each needing 4.5 or the result is capped at 4.5; problem solving adds
    /// up to one extra point (10%) only once the subject is passed.
    public static let programacion2 = Subject(
        name: "Programación II",
        ectsCredits: 6,
        root: .formula(Self.programacion2Formula)
    )

    private static let programacion2Formula: Formula = {
        let base = Expression.add(
            .multiply(.constant(0.4), .variable("L")),
            .multiply(.constant(0.6), .variable("E"))
        )
        let capped = Expression.min(base, .constant(4.5))
        let counted = Expression.ifGreaterOrEqual(
            lhs: .variable("L"), rhs: .constant(4.5),
            then: .ifGreaterOrEqual(lhs: .variable("E"), rhs: .constant(4.5), then: base, otherwise: capped),
            otherwise: capped
        )
        return Formula(
            name: "Nota final",
            expression: .ifGreaterOrEqual(
                lhs: counted, rhs: .constant(5),
                then: .min(.add(counted, .variable("S")), .constant(10)),
                otherwise: counted
            ),
            variables: [
                "L": .grade(Grade(name: "Prácticas de laboratorio", recovery: .savedForExtraordinary)),
                "E": .grade(Grade(name: "Prueba objetiva")),
                "S": .grade(Grade(name: "Solución de problemas", scaleMax: 1, recovery: .savedForExtraordinary)),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        )
    }()

    /// Labs (up to 3 points), problem solving (2) and exam (5) add up; under 1.5 on the exam the
    /// sum is halved.
    public static let tecnologiaElectronica = Subject(
        name: "Tecnología Electrónica",
        ectsCredits: 6,
        root: .formula({
            let sum = Expression.add(.add(.variable("L"), .variable("P")), .variable("E"))
            return Formula(
                name: "Nota final",
                expression: .ifGreaterOrEqual(
                    lhs: .variable("E"), rhs: .constant(1.5),
                    then: sum,
                    otherwise: .divide(sum, .constant(2))
                ),
                variables: [
                    "L": .grade(Grade(name: "Prácticas de laboratorio", scaleMax: 3, recovery: .savedForExtraordinary)),
                    "P": .grade(Grade(name: "Solución de problemas", scaleMax: 2, recovery: .savedForExtraordinary)),
                    "E": .grade(Grade(name: "Prueba mixta", scaleMax: 5)),
                ],
                minimum: Minimum(threshold: 5, consequence: .fails)
            )
        }())
    )

    /// Two exams (theory 55%, practice 20%) make the objective test; both can be retaken in the
    /// second sitting, and a missed one keeps its first-sitting grade.
    public static let algoritmos = Subject(
        name: "Algoritmos",
        ectsCredits: 6,
        root: .group(Group(
            name: "Nota final",
            combination: .weightedAverage,
            children: [
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Prácticas de laboratorio", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.05, node: .group(Group(
                    name: "Pruebas de respuesta breve",
                    combination: .weightedAverage,
                    children: [
                        WeightedChild(weight: 1, node: .grade(Grade(name: "Prueba 1", recovery: .savedForExtraordinary))),
                        WeightedChild(weight: 1, node: .grade(Grade(name: "Prueba 2", recovery: .savedForExtraordinary))),
                    ]
                ))),
                WeightedChild(weight: 0.10, node: .grade(Grade(name: "Solución de problemas", recovery: .savedForExtraordinary))),
                WeightedChild(weight: 0.75, node: .group(Group(
                    name: "Prueba objetiva",
                    combination: .weightedAverage,
                    children: [
                        WeightedChild(weight: 0.55, node: .grade(Grade(name: "Examen de teoría"))),
                        WeightedChild(weight: 0.20, node: .grade(Grade(name: "Examen de prácticas"))),
                    ]
                ))),
            ],
            minimum: Minimum(threshold: 5, consequence: .fails)
        ))
    )

    public static let all: [Subject] = [
        estructuraComputadores, estadistica, matematicaDiscreta, sistemasOperativos,
        algebra, administracionGestionOrganizaciones, informaticaBasica, disenoSoftware, paradigmasProgramacion,
        matematicaDiscretaGEI, calculo, programacion1, fundamentosComputadores, programacion2, tecnologiaElectronica, algoritmos,
    ]
}
