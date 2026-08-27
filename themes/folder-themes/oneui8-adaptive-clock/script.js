(function () {
  'use strict';
  var clock = document.getElementById('clock');
  function pad(value) { return value < 10 ? '0' + value : String(value); }
  function update() {
    var now = new Date();
    var hours = now.getHours() % 12 || 12;
    clock.innerHTML = '<span class="hour">' + pad(hours) + '</span><span class="minute">' + pad(now.getMinutes()) + '</span>';
  }
  update();
  setInterval(update, 1000);
}());
