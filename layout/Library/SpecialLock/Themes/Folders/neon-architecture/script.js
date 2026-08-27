(() => {
  const words = ['TWELVE', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN', 'ELEVEN'];
  const pad = n => String(n).padStart(2, '0');
  const ord = n => {
    const endings = ['TH', 'ST', 'ND', 'RD'];
    const value = n % 100;
    return `${n}${endings[(value - 20) % 10] || endings[value] || endings[0]}`;
  };
  function tick() {
    const date = new Date();
    const hour = date.getHours();
    const minute = date.getMinutes();
    document.getElementById('clock').textContent = `${pad(hour)}:${pad(minute)}`;
    document.getElementById('word').textContent = `${words[hour % 12]} ${words[Math.floor(minute / 5) % 12]}`;
    document.getElementById('date').textContent = date.toLocaleDateString('en-GB', { weekday: 'long', month: 'long' }).toUpperCase() + ` THE ${ord(date.getDate())}`;
    document.getElementById('weather').textContent = 'WALSALL · LOCAL THEME';
  }
  tick();
  setInterval(tick, 1000);
})();
