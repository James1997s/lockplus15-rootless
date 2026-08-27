(function () {
  'use strict';
  var clock = document.getElementById('clock');
  var weekday = document.getElementById('weekday');
  var date = document.getElementById('date');
  var weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  var months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  function pad(n) { return n < 10 ? '0' + n : String(n); }
  function update() {
    var now = new Date();
    var hours = now.getHours() % 12 || 12;
    clock.innerHTML = '<span>' + pad(hours) + '</span><span>' + pad(now.getMinutes()) + '</span>';
    weekday.textContent = weekdays[now.getDay()];
    date.textContent = months[now.getMonth()] + ' ' + now.getDate();
  }
  update();
  setInterval(update, 1000);
}());
