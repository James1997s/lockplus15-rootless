(()=>{
  const words=['TWELVE','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN'];
  const ordinal=n=>{const last=n%100; if(last>=11&&last<=13)return `${n}TH`; return `${n}${({1:'ST',2:'ND',3:'RD'}[n%10]||'TH')}`};
  const wordMinute=m=>m===0?"O'CLOCK":words[Math.round(m/5)%12];
  function render(){
    const d=new Date(), h=d.getHours(), m=d.getMinutes();
    const month=d.toLocaleDateString(undefined,{month:'long'}).toUpperCase();
    const word=document.getElementById('word-time');
    const numeric=document.getElementById('clock-time');
    const weekday=document.getElementById('weekday');
    const monthDay=document.getElementById('month-day');
    const numericDate=document.getElementById('numeric-date');
    if(word) word.textContent=`${words[h%12]} ${wordMinute(m)}`;
    if(numeric) numeric.textContent=`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
    if(weekday) weekday.textContent=d.toLocaleDateString(undefined,{weekday:'long'}).toUpperCase();
    if(monthDay) monthDay.textContent=`${month} THE ${ordinal(d.getDate())}`;
    if(numericDate) numericDate.textContent=d.toLocaleDateString(undefined,{month:'short',day:'numeric'}).toUpperCase();
  }
  render();
  setInterval(render,1000);
})();
