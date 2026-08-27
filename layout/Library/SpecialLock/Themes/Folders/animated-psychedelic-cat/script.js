function updateClock() {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');

    document.getElementById('time-display').textContent = `${hours}:${minutes}`;
    document.getElementById('status-time').textContent = `${hours}:${minutes}`;

    const options = { weekday: 'long', month: 'short', day: 'numeric' };
    document.getElementById('date-display').textContent = now.toLocaleDateString('en-US', options);
}

setInterval(updateClock, 1000);
updateClock();
