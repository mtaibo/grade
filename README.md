<div align="center">

# 🧮 Grade

**A tracker for your subjects, grades and assignments.**

<br/>

![Status](https://img.shields.io/badge/status-prototype-orange)
![Made with](https://img.shields.io/badge/made%20with-Swift-orange)
![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)

</div>

---

Grade is a tracker for your subjects, grades, assignments and deadlines in one place, built to model **any** grading scheme instead of a generic one. It's my first project aimed at the App Store: a minimal version first, tested with real students, then grown into something I'd pay for myself.

## Why I'm building it

The grade-tracking apps that exist are generic agendas, usually in English, that don't understand how Spanish universities actually grade: minimum scores to average in, exam parts that exempt you from the final, non-recoverable coursework, ordinary and extraordinary sittings, weights that change depending on another part's grade.

- **Validate fast** — a minimal version tested with real students before building months of features nobody asked for
- **A real portfolio piece** — published, with real users, built with clean architecture, tests and native Apple frameworks
- **Modest income** — free with a small paid tier, enough to cover the Apple Developer Program fee
- **My own use** — I track my own subjects with it every day

## The app

For each subject, it answers one question: **"what do I need on the final?"**

<table>
<tr>
<td width="50%" valign="top">

### 📚 Subjects
The home screen, one course at a time (switched from the title). A card per subject with the grade secured so far, a 0–10 bar from worst to best case with the pass mark, and what's still needed: "Necesitas un 4,2 en lo que falta".

**SwiftUI · Observation**

</td>
<td width="50%" valign="top">

### 📝 Subject
Ordinary and extraordinary sittings, each with its exam date. One card per part showing its weight and the points it has earned, with an input that matches how the teacher grades it: points out of anything, a percentage, letters (A, B, C…), or a compact grid for many small tests.

**SwiftUI**

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 🧩 Editor
Reshape any subject to match its real syllabus: parts and nested groups, weights, how they combine (weighted average, sum, best N…), scale, pass mark, input style, whether a grade carries over to the extraordinary sitting, and due dates.

**SwiftUI**

</td>
<td width="50%" valign="top">

### 📅 Calendar
A month view with a dot on every day something is due — lab hand-ins and both exam sittings — and the list of what's coming, each with the grade if it's in or how many days are left.

**SwiftUI · UICalendarView**

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 🎓 Record
The credit-weighted average and credits passed, over the subjects whose grades are all in.

**SwiftUI**

</td>
<td width="50%" valign="top">

### ⚙️ [`Engine`](Sources/Engine/)
The calculation library: the evaluation tree, current grade, best case, pass status and grade needed (binary search). No UI dependency, value types only, tested against 9 real syllabi.

**Swift Package · Swift Testing**

</td>
</tr>
</table>

## Architecture

```
┌─────────────────────── App (SwiftUI) ───────────────────────┐
│  Calendar   ·   Subjects   ·   Subject / Editor   ·  Record  │
│                         │                                   │
│                 Library (@Observable)                       │
│    courses → subjects → tree + grades per sitting           │
│                 saved as one JSON file                      │
└─────────────────────────┬───────────────────────────────────┘
                          │  grades converted to each part's scale
┌─────────────────────────▼───────────────────────────────────┐
│  Engine (Swift Package, no SwiftUI)                         │
│  Node tree: Grade · Group · Formula · Alternatives · …      │
│  evaluate · neededFraction · status · minimums · caps       │
└─────────────────────────────────────────────────────────────┘
```

The engine knows nothing about screens or storage: it takes a subject's tree and the grades entered so far and returns numbers. Everything about how a grade is typed (out of 2, 85 %, a "B") is converted in the app before it gets there. Persistence is a local JSON file for now; the plan is SwiftData with iCloud sync once subjects can be created from scratch.

## How it works

```
Syllabus (guía docente, PDF)
        │  read the evaluation section
        ▼
Evaluation rules as JSON (guide/extracted/), citing the original text
        │  build the tree in Swift
        ▼
Subject tree  ──►  tests with hand-calculated grades
        │
        ▼
Grades entered (ordinary / extraordinary)
        │
        ▼
evaluate(pending = 0) → what you have     evaluate(pending = 1) → best case
        │
        ▼
binary search over "same grade on everything pending" → what you need
```

### Modelling real syllabi

Every rule found so far comes from an actual syllabus in [`guide/`](guide/): continuous weights that depend on another grade (`Formula`, e.g. Estadística's `P + C + 0.1 · (8 − C) · F`), minimums on one part that fail the subject regardless of the average (Sistemas Operativos), and minimums that cap the final grade at 4.5 or 4.9 (Diseño Software, Informática Básica). When a syllabus doesn't fit, the model changes instead of the syllabus being forced into it. The plan is to keep adding syllabi in batches until 10 in a row need no change. Decisions and open gaps are in [`docs/modelo.md`](docs/modelo.md) (in Spanish).

### Ordinary and extraordinary sittings

Each subject keeps both sittings' grades. In the extraordinary one, parts the syllabus keeps (labs, usually) carry over and can be overridden; the rest, usually the exam, starts empty. 🚧 Both sittings share one structure, so a syllabus that reweights the exam in the extraordinary sitting is approximated.

## Tech stack

| Layer | Technology |
|---|---|
| **Engine** | Swift Package, no SwiftUI/SwiftData dependency, value types |
| **UI** | SwiftUI |
| **Persistence** | Local JSON for now; SwiftData with iCloud sync via CloudKit planned |
| **Project** | XcodeGen (`App/project.yml`), the `.xcodeproj` is generated |
| **Tests** | Swift Testing: one suite per syllabus, every mix of evaluations against the engine's invariants, and the app's model (saving, backups, studies) run on the Mac |

## How to run

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/mtaibo/grade.git
cd grade
make test                                              # engine and app model tests
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig
# set DEVELOPMENT_TEAM in Local.xcconfig to your Apple team ID
make open                                              # generates and opens the Xcode project
make device                                            # builds, installs and opens it on a paired iPhone
```

### Website

[`web/`](web/) is the small site at [grade.migueltaibo.com](https://grade.migueltaibo.com): what the app does, with a live "what do you need in the exam" example, plus the privacy policy and support pages the App Store asks for. Plain HTML and CSS served by nginx in a container that joins [tpcloud](https://github.com/mtaibo/tpcloud)'s gateway network, whose Caddy proxies the subdomain to it. On the Pi, with tpcloud up:

```bash
make web                                               # docker compose -f web/docker-compose.yml up -d --build
```

The full brief and roadmap are in [`guide/proyect.md`](guide/proyect.md) (in Spanish). The first milestone is a TestFlight build tried with ~20 students before the January exams.
