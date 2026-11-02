// The whole page is one continuous take: Grade's check mark opens into the app, and every section of the site is a
// moment inside it. All styling goes through classes and CSSOM, so the site's CSP (style-src 'self') holds.
(() => {
  const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
  const mid = (a, b, u) => a + (b - a) * u
  const clamp01 = x => Math.min(1, Math.max(0, x))
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  const fmt = (v, d = 2) => v.toLocaleString('es-ES', { minimumFractionDigits: 0, maximumFractionDigits: d })
  const fmt1 = v => v.toLocaleString('es-ES', { minimumFractionDigits: 1, maximumFractionDigits: 1 })

  // ---- the calculator: same rule as before, Física: labs 40 %, exam 60 % with a 4 as the minimum ----
  const labs = document.getElementById('labs'), labsOut = document.getElementById('labs-out')
  const needed = document.getElementById('needed'), explain = document.getElementById('explain')
  const neededExam = v => {
    // Rounded up to the tenth, so the grade shown always passes.
    const average = Math.ceil(((5 - .4 * v) / .6) * 10 - 1e-9) / 10
    return { average, exam: Math.max(average, 4) }
  }

  // ---- screens ----
  const GLYPH = {
    atom: '<circle cx="12" cy="12" r="1.6" fill="currentColor"/><ellipse cx="12" cy="12" rx="10" ry="4"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(120 12 12)"/>',
    code: '<path d="M8 6 2.500 12 8 18M16 6l5.500 6L16 18M14 4l-4 16"/>',
    cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M10 2v4M14 2v4M10 18v4M14 18v4M2 10h4M2 14h4M18 10h4M18 14h4"/>',
    chart: '<path d="M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-3"/>',
    back: '<path fill="none" stroke="currentColor" stroke-width="2.400" stroke-linecap="round" stroke-linejoin="round" d="M15 5l-7 7 7 7"/>',
    more: '<g fill="currentColor"><circle cx="5" cy="12" r="1.200"/><circle cx="12" cy="12" r="1.200"/><circle cx="19" cy="12" r="1.200"/></g>',
    cal: '<g fill="none" stroke="currentColor" stroke-width="1.800"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/></g>',
    books: '<path d="M5 4h4v16H5zM10 4h4v16h-4zM15.500 5l3.600-1 3 15.500-3.600 1z"/>',
    person: '<circle cx="12" cy="12" r="9.500"/><circle cx="12" cy="10" r="3.400"/><path d="M5.500 19c1.400-3 3.800-4 6.500-4s5.100 1 6.500 4"/>',
    chev: '<path d="M6 9l6 6 6-6"/>',
  }
  const glyph = g => `<svg viewBox="0 0 24 24">${GLYPH[g]}</svg>`
  const STATUS = `<div class="status"><span>9:41</span><svg viewBox="0 0 62 14" fill="#000"><rect x="0" y="9" width="3" height="5" rx=".8"/><rect x="4.500" y="6.500" width="3" height="7.500" rx=".8"/><rect x="9" y="4" width="3" height="10" rx=".8"/><rect x="13.500" y="1" width="3" height="13" rx=".8"/><path d="M28 3.600a10 10 0 0 1 7 2.800l1.200-1.300A11.800 11.800 0 0 0 28 1.700a11.800 11.800 0 0 0-8.200 3.400L21 6.400a10 10 0 0 1 7-2.800zm0 3.700a6.200 6.200 0 0 1 4.300 1.700l1.200-1.300A8 8 0 0 0 28 5.400a8 8 0 0 0-5.500 2.300l1.200 1.300A6.200 6.200 0 0 1 28 7.300zm0 3.600-2.200 1.200L28 14l2.200-1.900z"/><rect x="40" y="1.500" width="20" height="11" rx="3" fill="none" stroke="#000" stroke-opacity=".4"/><rect x="41.500" y="3" width="17" height="8" rx="1.800"/></svg></div><div class="island"></div>`
  const TABS = sel => `<div class="tabbar">${[['Calendario', 'cal'], ['Asignaturas', 'books'], ['Cuenta', 'person']].map(([n, g]) => `<div class="${n === sel ? 'sel' : ''}">${glyph(g)}${n}</div>`).join('')}</div>`
  const ring = f => { const C = 2 * Math.PI * 12; return `<svg class="ring" viewBox="0 0 28 28"><circle cx="14" cy="14" r="12"/><circle class="on" cx="14" cy="14" r="12" stroke-dasharray="${f * C} ${C}"/></svg>` }
  const TILES = [['Algoritmos', 'code', 'indigo', 5 / 6], ['Diseño Software', 'code', 'orange', .5], ['Estructura de Computadores', 'cpu', 'teal', .75], ['Paradigmas de Programación', 'code', 'pink', 2 / 3], ['Física', 'atom', 'blue', .5]]
  const homeHTML = `<div class="scr home"><div class="topbtns"><div class="gbtn">${glyph('cal')}</div><div class="gbtn">${glyph('more')}</div></div><div class="h-year rnd">2º Año</div><div class="h-term rnd">1º Cuatrimestre</div>
    <div class="tiles">${TILES.map(([n, g, c, f]) => `<div class="tile${n === 'Física' ? ' tapped' : ''}"><div class="ic c-${c}">${glyph(g)}</div>${ring(f)}<div class="tname">${n}</div></div>`).join('')}</div>${TABS('Asignaturas')}</div>`
  const subHTML = `<div class="scr sub"><div class="navrow"><div class="gbtn">${glyph('back')}</div><div class="gbtn">${glyph('more')}</div></div>
    <div class="s-name rnd">Física</div><div class="seg"><i class="thumb"></i><div>Ordinaria</div><div>Extraordinaria</div></div>
    <div class="card"><div class="gbig"><span class="gnum rnd" data-g="worst"></span><span class="gof">/ 10</span><span class="pill" data-g="pill"></span><svg class="chev" viewBox="0 0 24 24">${GLYPH.chev}</svg></div>
      <div class="bar"><i class="b" data-g="bestbar"></i><i data-g="worstbar"></i><u></u></div>
      <div class="stats"><div class="stat"><small><i></i>Asegurada</small><b class="rnd" data-g="worst"></b></div><div class="stat"><small><i class="b"></i>Máxima</small><b class="rnd" data-g="best"></b></div></div>
      <div data-g="need-box"><div class="need-t">Para aprobar</div><div class="need-r">Examen<b class="rnd" data-g="need"></b></div></div><div class="verdict" data-g="verdict"></div></div>
    <div class="notes rnd">Notas</div>
    <div class="card part"><div><h4>Prácticas</h4><span class="chip">40 %</span><span class="kept" data-g="kept">De la ordinaria</span></div><span class="pval" data-g="labs"></span></div>
    <div class="card part"><div><h4>Examen</h4><span class="chip">60 %</span></div><span class="pval" data-g="exam"></span></div></div>`
  const FORMULA = 'P + C + 0,1 * (8 - C) * F'
  const editHTML = `<div class="scr edit"><div class="navrow"><div class="gbtn">${glyph('back')}</div></div><div class="s-name rnd">Estadística</div>
    <div class="seg two"><div>Media ponderada</div><div class="fsel">Fórmula</div><i class="thumb thumb-r"></i></div><div class="e-lab">Fórmula</div><div class="formula"><span data-g="formula"></span><u></u></div>
    <div class="e-lab">Variables</div><div class="vars"><p data-var="P"><b>P</b>Prácticas de laboratorio<em>sobre 2</em></p><p data-var="C"><b>C</b>Controles (temas 1 y 2)<em>sobre 2</em></p><p data-var="F"><b>F</b>Examen final<em>sobre 10</em></p></div></div>`
  const calCells = () => {
    // July 2027: the first falls on a Thursday. The dates are an example.
    const marks = { 5: 'pink', 12: 'blue', 19: 'orange' }
    let cells = ''
    for (let i = 0; i < 35; i++) {
      const n = i - 2
      const out = n < 1 || n > 31
      cells += `<span class="${out ? 'out' : n === 5 ? 'hot' : ''}">${out ? (n < 1 ? 30 + n : n - 31) : n}${!out && marks[n] && n !== 5 ? `<i class="d-${marks[n]}"></i>` : ''}</span>`
    }
    return cells
  }
  const calHTML = `<div class="scr cal"><div class="c-title rnd">Calendario</div><div class="month rnd">Julio 2027</div><div class="days">${['L', 'M', 'X', 'J', 'V', 'S', 'D'].map(x => `<small>${x}</small>`).join('')}${calCells()}</div>
    <div class="up">Próximas fechas</div><div class="d-row"><div class="ic c-blue">${glyph('atom')}</div><div><strong>Física</strong><span>Extraordinaria · 5 jul</span></div></div><div class="d-row"><div class="ic c-indigo">${glyph('code')}</div><div><strong>Algoritmos</strong><span>Extraordinaria · 12 jul</span></div></div><div class="d-row"><div class="ic c-orange">${glyph('code')}</div><div><strong>Diseño Software</strong><span>Extraordinaria · 19 jul</span></div></div>${TABS('Calendario')}</div>`
  // An example record, credit-weighted the way the app does it: six credits each.
  const TERMS = [['1º Cuatrimestre', [['Cálculo', 8.69], ['Programación I', 7.6], ['Matemática Discreta', 9.4], ['Informática Básica', 6.84]]], ['2º Cuatrimestre', [['Álgebra', 6.79], ['Estadística', 7.73], ['Física', 5.2], ['Programación II', 8.87]]]]
  const ALL = TERMS.flatMap(t => t[1].map(r => r[1]))
  const AVERAGE = ALL.reduce((a, b) => a + b) / ALL.length
  const band = g => g < 5 ? 'fail' : g < 7 ? 'pass' : g < 9 ? 'good' : 'great'
  const recHTML = `<div class="scr rec"><div class="c-title rnd">Expediente</div><div class="r-stats"><div><b class="rnd" data-g="avg"></b><small>Media</small></div><div><b class="rnd" data-g="passed"></b><small>Aprobadas</small></div><div><b class="rnd" data-g="credits"></b><small>Créditos</small></div></div>
    ${TERMS.map(([t, list]) => `<div class="r-h rnd">${t}<small>Media ${fmt(list.reduce((a, r) => a + r[1], 0) / list.length)}</small></div><div class="r-card">${list.map(([n, g]) => `<p data-row><span>${n}</span><b class="b-${band(g)}">${fmt(g)}</b></p>`).join('')}</div>`).join('')}</div>`

  const stage = document.getElementById('stage')
  stage.innerHTML = `<div class="mount"></div>`
  const mount = stage.firstElementChild
  const phone = html => { const n = document.createElement('div'); n.className = 'phone'; n.innerHTML = `<div class="phone-in">${html}${STATUS}</div>`; mount.append(n); return n }
  const calP = phone(calHTML), recP = phone(recHTML)
  const main = phone(`<div class="lay under">${homeHTML}</div><div class="lay over">${subHTML}</div><div class="lay edit-l">${editHTML}</div><div class="lay cal-l">${calHTML}</div><div class="lay rec-l">${recHTML}</div><div class="dim"></div><div class="popup"><div class="ph">Examen<span>Hecho</span></div><div class="pv"><b data-g="typed"></b><small>sobre 10</small></div></div><div class="splash"></div>`)
  const watch = document.createElement('div'); watch.className = 'watch'
  watch.innerHTML = `<div class="w-name">Física</div><div class="w-num"><span data-g="worst"></span><span class="w-of">/ 10</span></div><div class="bar"><i class="b" data-g="bestbar"></i><i data-g="worstbar"></i><u></u></div>`
  mount.append(watch)
  const svgNS = 'http://www.w3.org/2000/svg'
  const mark = document.createElementNS(svgNS, 'svg'); mark.id = 'mark'; mark.setAttribute('viewBox', '0 0 256 256')
  const markPath = document.createElementNS(svgNS, 'path'); markPath.setAttribute('d', 'M68 140 L116 186 L190 80'); mark.append(markPath); stage.append(mark)
  const scrim = document.createElement('div'); scrim.className = 'scrim'; document.body.append(scrim)
  main.querySelectorAll('.lay').forEach(l => { l.style.position = 'absolute'; l.style.inset = '0'; l.style.overflow = 'hidden' })
  const q = s => main.querySelector(s)
  const under = q('.under'), over = q('.over'), editL = q('.edit-l'), calL = q('.cal-l'), recL = q('.rec-l')
  const splash = q('.splash'), dim = q('.dim'), popup = q('.popup'), tile = q('.tile.tapped'), inner = q('.phone-in')
  const thumb = q('.sub .thumb')
  const all = sel => document.querySelectorAll(`[data-g="${sel}"]`)
  const setText = (sel, value) => all(sel).forEach(n => { if (n.textContent !== value) n.textContent = value })
  const rows = [...main.querySelectorAll('.rec-l [data-row]')]
  const vars = [...main.querySelectorAll('[data-var]')]

  // Everything the subject card shows, from the lab grade, the exam (null while pending) and the sitting.
  function card(v, exam, extra) {
    const worst = .4 * v + .6 * (exam ?? 0), best = .4 * v + .6 * (exam ?? 10)
    setText('worst', fmt(worst)); setText('best', fmt(best))
    setText('labs', fmt(v, 1)); setText('exam', exam === null ? '—' : fmt1(exam))
    setText('need', fmt1(neededExam(v).exam))
    const done = exam !== null, ok = done && exam >= 4 && worst >= 5
    all('worstbar').forEach(n => { n.style.width = worst * 10 + '%'; n.classList.toggle('ok', done && ok); n.classList.toggle('ko', done && !ok) })
    all('bestbar').forEach(n => { n.style.width = best * 10 + '%' })
    all('need-box').forEach(n => { n.style.display = done ? 'none' : '' })
    all('verdict').forEach(n => {
      n.style.display = done ? '' : 'none'
      n.classList.toggle('ok', ok); n.classList.toggle('ko', !ok)
      n.textContent = !done ? '' : ok ? 'Ya tienes el aprobado, pase lo que pase en lo que falta.' : exam < 4 ? 'Sin un 4 en el examen no hace media.' : 'Aún no llegas al 5.'
    })
    all('pill').forEach(n => {
      n.textContent = !done ? '1 de 2 notas' : ok ? 'Aprobada' : 'No llega'
      n.classList.toggle('ok', ok); n.classList.toggle('bad', done && !ok)
    })
    all('kept').forEach(n => { n.style.display = extra ? '' : 'none' })
    setText('typed', exam === null ? '' : fmt1(exam))
  }

  const updateCalc = () => {
    const v = Number(labs.value), { average, exam } = neededExam(v)
    labsOut.textContent = fmt1(v).replace(',0', '')
    needed.textContent = fmt1(exam)
    explain.textContent = average < 4
      ? `en el examen: con tus prácticas bastaría un ${fmt1(Math.max(average, 0))}, pero la guía pide un 4 en el examen para hacer media.`
      : 'es lo que necesitas en el examen para aprobar.'
  }
  labs.addEventListener('input', updateCalc)
  updateCalc()

  // ---- camera ----
  const LAST = 9
  let W, H, narrow, ps, pc, heroAt, heroSize, endAt
  const ICON = 128
  function layout() {
    W = innerWidth; H = innerHeight; narrow = W < 760
    ps = narrow ? Math.min(W * .76 / 390, H * .56 / 844) : Math.min(H * .88 / 844, W * .42 / 390)
    pc = narrow ? [W / 2, H * .05 + 422 * ps] : [W * .72, H * .5]
    heroAt = narrow ? [W * .5, H * .26] : [W * .76, H * .42]
    heroSize = narrow ? W * .62 : Math.min(W * .34, H * .62)
    endAt = narrow ? [W / 2, H * .3] : [W / 2, H * .36]
  }
  layout()
  addEventListener('resize', layout)

  const place = (n, x, y, s, rot = 0, o = 1) => {
    n.style.transform = `translate(${x}px, ${y}px) rotateY(${rot}deg) scale(${s})`
    n.style.opacity = o
    n.style.visibility = o < .004 ? 'hidden' : ''
  }
  const layer = (n, o, x = 0) => { n.style.opacity = o; n.style.visibility = o < .004 ? 'hidden' : ''; n.style.transform = x ? `translateX(${x}%)` : '' }
  const clipOf = (a, grow, round) => {
    const ix = (390 - a) / 2, iy = (844 - a) / 2
    return `inset(${mid(iy, -13, grow)}px ${mid(ix, -13, grow)}px ${mid(iy, -13, grow)}px ${mid(ix, -13, grow)}px round ${mid(a * .225, 67, grow)}px)`
  }
  const setClip = (n, c) => { n.style.clipPath = c; n.style.webkitClipPath = c }

  const brand = document.querySelector('.brand')
  const track = document.querySelector('.track'), beats = [...document.querySelectorAll('.beat')]
  let s = 0, rs = 0, then = performance.now()

  function frame(now) {
    const dt = Math.max(0, Math.min(.05, (now - then) / 1000)); then = now
    const range = track.offsetHeight - innerHeight
    const raw = clamp01(scrollY / range) * LAST
    const k0 = Math.min(LAST - 1, Math.floor(raw))
    // Each moment holds while its text is read, and what happens inside it follows the scroll.
    const target = k0 + (raw >= LAST ? 1 : smooth(.46, 1, raw - k0))
    const ease = Math.min(1, dt * (reduced ? 40 : 7))
    s += (target - s) * ease; rs += (raw - rs) * ease
    if (Math.abs(target - s) < .0004) s = target
    const k = Math.min(LAST - 1, Math.floor(s)), u = s - k

    mount.style.transform = `translate(${pc[0]}px, ${pc[1]}px)`
    // On a phone the logo would sit on the iPhone: it steps aside while the app is open.
    const brandO = narrow ? Math.max(1 - smooth(.25, .5, s), smooth(8.6, 8.9, s)) : 1
    brand.style.opacity = brandO; brand.style.visibility = brandO < .02 ? 'hidden' : ''
    const v = Number(labs.value)
    // What happens inside each hold.
    const examP = smooth(0, .42, rs - 3)                     // typing the exam grade
    const typedF = smooth(0, .42, rs - 4)                    // typing the formula
    const sitting = smooth(0, .4, rs - 5)                    // ordinary to extraordinary
    const counted = smooth(0, .42, rs - 7)                   // the record adds up

    const exam = s < 2.5 ? null : s >= 5 && sitting > .5 ? null : mid(2, 5.2, examP)
    card(v, exam, s >= 5 && sitting > .5)
    thumb.style.transform = `translateX(${(s >= 5 && s < 8.2 ? sitting : 0) * 100}%)`

    // Who is on screen.
    let side = 0
    if (k === 0) {
      layer(under, 1); layer(over, 0); layer(editL, 0); layer(calL, 0); layer(recL, 0)
      const fly = smooth(.1, .44, u), white = smooth(.4, .54, u), grow = smooth(.6, .98, u), a = ICON / ps
      const size = mid(heroSize, ICON * .62, fly)
      mark.style.transform = `translate(${mid(heroAt[0], pc[0], fly)}px, ${mid(heroAt[1], pc[1], fly)}px) scale(${size / 256})`
      mark.style.opacity = 1 - smooth(.66, .76, u)
      markPath.style.stroke = `rgb(${mid(255, 0, white)},${mid(255, 0, white)},${mid(255, 0, white)})`
      setClip(main, clipOf(a, grow))
      place(main, 0, 0, ps * smooth(.38, .54, u), 0, white > .001 ? 1 : 0)
      splash.style.opacity = 1 - smooth(.7, .92, u)
      scrim.style.opacity = smooth(.8, 1, u)
    } else if (k === 8) {
      // The app closes back into its icon: the page ends on the mark it began with.
      const close = smooth(.08, .62, u), a = ICON / ps, move = smooth(.55, 1, u)
      // No cut from the group shot: the subject fades to the home screen as the phone comes forward.
      layer(under, 1); layer(over, 1 - smooth(.02, .3, u)); setClip(over, 'none'); layer(editL, 0); layer(calL, 0); layer(recL, 0)
      setClip(main, clipOf(a, 1 - close))
      splash.style.opacity = smooth(.2, .5, u)
      const x = mid(0, endAt[0] - pc[0], move), y = mid(0, endAt[1] - pc[1], move)
      place(main, x, y, ps * mid(narrow ? .78 : .74, 1, smooth(0, .3, u)))
      mark.style.transform = `translate(${pc[0] + x}px, ${pc[1] + y}px) scale(${ICON * .62 / 256})`
      mark.style.opacity = smooth(.4, .56, u)
      markPath.style.stroke = '#000'
      side = 1 - smooth(0, .3, u)
      scrim.style.opacity = 1 - smooth(.5, .8, u)
    } else {
      setClip(main, 'none'); splash.style.opacity = 0; mark.style.opacity = 0; scrim.style.opacity = 1
      place(main, 0, 0, ps)
    }
    // tile into subject
    if (k === 1) {
      layer(editL, 0); layer(calL, 0); layer(recL, 0)
      tile.style.transform = `scale(${1 - .035 * smooth(0, .14, u) * (1 - smooth(.14, .26, u))})`
      tile.style.boxShadow = `0 0 0 ${smooth(0, .14, u) * 3}px rgba(0,122,255,${.5 * (1 - smooth(.2, .32, u))})`
      const e = smooth(.2, .86, u), r = tile.getBoundingClientRect(), o = inner.getBoundingClientRect(), f = 390 / o.width
      const t = (r.top - o.top) * f, l = (r.left - o.left) * f, w = r.width * f, h = r.height * f
      setClip(over, `inset(${mid(t, 0, e)}px ${mid(390 - l - w, 0, e)}px ${mid(844 - t - h, 0, e)}px ${mid(l, 0, e)}px round ${mid(22, 56, e)}px)`)
      layer(under, 1 - .35 * e); layer(over, smooth(.18, .34, u))
    } else if (k >= 2 && k <= 7) {
      setClip(over, 'none'); layer(under, 0)
      // sub, sliding away to the editor and back
      const toEdit = k === 3 ? smooth(.2, .86, u) : k === 4 ? 1 - smooth(.1, .8, u) : 0
      layer(over, 1, toEdit ? -28 * toEdit : 0)
      layer(editL, toEdit > 0 ? 1 : 0, (1 - toEdit) * 100)
      // the calendar rises over the subject, the record over the calendar
      const toCal = k === 5 ? smooth(.1, .8, u) : k === 6 ? 1 : 0
      layer(calL, toCal > 0 ? 1 : 0); calL.style.transform = `translateY(${(1 - toCal) * 100}%)`
      const toRec = k === 6 ? smooth(.1, .8, u) : k === 7 ? 1 - smooth(.1, .7, u) : 0
      layer(recL, toRec > 0 ? 1 : 0); recL.style.transform = `translateY(${(1 - toRec) * 100}%)`
    }
    // The popup that takes the exam grade.
    const pop = k === 2 ? smooth(.3, .8, u) : k === 3 ? 1 - smooth(.06, .4, u) : 0
    dim.style.opacity = pop; dim.style.visibility = pop < .01 ? 'hidden' : ''
    popup.style.transform = `translateY(${(pop - 1) * 110}%)`; popup.style.opacity = pop; popup.style.visibility = pop < .01 ? 'hidden' : ''

    // The formula, written as in the guide; each variable answers when its letter appears.
    const n = Math.round(FORMULA.length * typedF), text = FORMULA.slice(0, n)
    setText('formula', text)
    vars.forEach(p => { const on = text.includes(p.dataset.var); p.style.opacity = on ? 1 : .25 })

    // The record adds itself up.
    setText('avg', fmt(AVERAGE * counted)); setText('passed', `${Math.round(ALL.length * counted)}/${ALL.length}`); setText('credits', fmt(Math.round(ALL.length * 6 * counted)))
    rows.forEach((r, i) => { r.style.opacity = smooth(i / rows.length, (i + 1.5) / rows.length, counted) })

    // Everything at once: the calendar and the record come out from behind, with the watch in front.
    if (k === 7) side = smooth(.04, .9, u)
    const sc = narrow ? .78 : .74
    if (k === 7) place(main, 0, 0, ps * mid(1, sc, side))
    else if (k === 8) { /* placed above */ }
    const off = 390 * ps * (narrow ? .78 : .84), sideS = ps * mid(.6, narrow ? .66 : .64, side), shown = k >= 7 ? smooth(.04, .3, side) : 0
    place(calP, -off * side, 0, sideS, 26 * side, shown)
    place(recP, off * side, 0, sideS, -26 * side, shown)
    const w = k === 7 ? smooth(.55, .95, u) : k === 8 ? side : 0
    place(watch, 390 * ps * (narrow ? .36 : .4), mid(760, 330, w) * ps, ps * (narrow ? .78 : .88), 0, w)

    beats.forEach(b => {
      const from = +b.dataset.from, to = +(b.dataset.to || from)
      const d = s < from ? from - s : s > to ? s - to : 0
      const o = 1 - smooth(.05, .18, d)
      b.style.opacity = o
      b.classList.toggle('on', o > .02)
      b.style.transform = reduced ? '' : `translateY(${(s < from ? from - s : s > to ? to - s : 0) * 34}px)`
    })
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
})()
