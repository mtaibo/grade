<div align="center">

# 🧮 Mark

**A tracker for your university subjects, grades and assignments — and what you need on what's left.**

<br/>

![Status](https://img.shields.io/badge/status-planning-yellow)
![Made with](https://img.shields.io/badge/made%20with-Swift-orange)
![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)

</div>

---

Mark is a tracker for university students: subjects, grades, assignments and deadlines in one place, built to model **any** grading scheme instead of a generic one. It's my first project aimed at the App Store: a minimal version first, tested with real students, then grown into something I'd pay for myself.

## Why I'm building it

The grade-tracking apps that exist are generic agendas, usually in English, that don't understand how Spanish universities actually grade: minimum scores to average in, exam parts that exempt you from the final, non-recoverable coursework, ordinary and extraordinary sessions, weights that change depending on another part's grade.

- **Validate fast** — a minimal version tested with real students before building months of features nobody asked for
- **A real portfolio piece** — published, with real users, built with clean architecture, tests and native Apple frameworks
- **Modest income** — free with a small paid tier, enough to cover the Apple Developer Program fee
- **My own use** — I track my own subjects with it every day

## What it does

For each subject, it answers one question: **"what do I need on the final?"** It models a subject's grading as a tree of components (grades, groups, alternative schemes, bonuses, requirements), so it can express real cases a generic agenda can't:

```
Subject
└─ Alternatives (by condition)
   ├─ If midterms ≥ 4:  Final 40% · Midterms 40% · Labs 20%
   └─ Otherwise:        Final 80% · Labs 20%
```

- **Flexible model, simple interface** — all the complexity lives in the calculation engine, the user never sees a formula
- **Local first** — SwiftData, with iCloud sync (CloudKit) planned, no backend or accounts
- **Built for the Spanish system** — 0–10 scale, ordinary/extraordinary sessions, ECTS credits
- **Native feel** — minimal, following Apple's Human Interface Guidelines

## Status

Still at the modelling stage: validating the evaluation tree against real course syllabi (`guide/`) before writing any app code. The plan is to start with 3 very different syllabi, build a calculation engine with tests against them, then add syllabi in batches of 5 until 10 in a row stop forcing model changes.

The first milestone is a minimal TestFlight build — create subjects, enter grades, see what's needed to pass — tried with ~20 students before January exams. Full details and the complete plan are in [`guide/proyect.md`](guide/proyect.md) (in Spanish).

## Structure

```
mark/
├── README.md
└── guide/
    ├── proyect.md                          project brief: goals, model, roadmap
    ├── guiaDocente_estadistica.pdf          reference syllabus
    ├── guiaDocente_estructuraComputadores.pdf
    └── guiaDocente_matematicaDiscreta.pdf
```

## Tech stack

| Layer | Technology |
|---|---|
| **Engine** | Swift Package, no SwiftUI/SwiftData dependency, value types |
| **Persistence** | SwiftData, iCloud sync via CloudKit (planned) |
| **UI** | SwiftUI |
| **Tests** | Swift Testing, one case per syllabus plus edge cases |
