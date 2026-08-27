(function () {
  const digits = Array.from(document.querySelectorAll('.stack-digit'));
  const dateEl = document.getElementById('small-date');
  function pad(value) { return String(value).padStart(2, '0'); }
  function updateClock() {
    const now = new Date();
    const value = pad(now.getHours()) + ':' + pad(now.getMinutes());
    const days = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    digits.forEach((element) => { element.textContent = value; });
    if (dateEl) dateEl.textContent = days[now.getDay()] + ' ' + pad(now.getDate()) + ' ' + months[now.getMonth()];
  }
  updateClock();
  setInterval(updateClock, 1000);
})();
