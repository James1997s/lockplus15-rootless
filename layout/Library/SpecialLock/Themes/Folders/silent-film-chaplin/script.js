(function(){
  var clock=document.getElementById('clock');
  var date=document.getElementById('date');
  var weather=document.getElementById('weather');
  var battery=document.getElementById('battery');
  var days=['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'];
  var months=['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];
  function pad(n){return String(n).padStart(2,'0');}
  function update(){
    var now=new Date();
    clock.textContent=pad(now.getHours())+':'+pad(now.getMinutes());
    date.textContent=days[now.getDay()]+' · '+pad(now.getDate())+' '+months[now.getMonth()]+' '+now.getFullYear();
    if(weather) weather.textContent='WALSALL · LIVE WEATHER';
    if(navigator.getBattery){navigator.getBattery().then(function(b){battery.textContent='BATTERY '+Math.round(b.level*100)+'%';});}
  }
  update();setInterval(update,1000);
})();
