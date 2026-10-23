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
                WeightedChild(weight: 0.20, node: .grade(Grade(name: "Prácticas de laboratorio"))),
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

    public static let all: [Subject] = [estructuraComputadores, estadistica, matematicaDiscreta]
}
