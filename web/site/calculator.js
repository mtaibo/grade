// Física: prácticas 40 %, examen 60 % con un 4 como mínimo, se aprueba con un 5.
const labs = document.getElementById("labs");
const labsOut = document.getElementById("labs-out");
const needed = document.getElementById("needed");
const explain = document.getElementById("explain");
const mark = document.getElementById("mark");
const format = (value) => value.toLocaleString("es-ES", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function update() {
  const practicas = Number(labs.value);
  // Rounded up to the tenth, so the grade shown always passes.
  const average = Math.ceil(((5 - 0.4 * practicas) / 0.6) * 10 - 1e-9) / 10;
  const exam = Math.max(average, 4);
  labsOut.textContent = format(practicas).replace(",0", "");
  needed.textContent = format(exam);
  mark.style.left = `${exam * 10}%`;
  explain.textContent = average < 4
    ? `en el examen: con tus prácticas bastaría un ${format(Math.max(average, 0))}, pero la guía pide un 4 en el examen para hacer media.`
    : "es lo que necesitas en el examen para aprobar.";
}

labs.addEventListener("input", update);
update();
