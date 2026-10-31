/* Loads only the scripts needed for this page. Local demo does not require Supabase. */
(async function(){
  const savedTheme=localStorage.getItem('hunt-theme')||'classic';
  document.body.dataset.theme=savedTheme;
  function setupThemes(){
    document.querySelectorAll('[data-theme-choice]').forEach(btn=>{
      const selected=btn.dataset.themeChoice===(localStorage.getItem('hunt-theme')||'classic');
      btn.setAttribute('aria-checked',String(selected));btn.setAttribute('role','radio');
      btn.onclick=()=>{const theme=btn.dataset.themeChoice;localStorage.setItem('hunt-theme',theme);document.body.dataset.theme=theme;document.querySelectorAll('[data-theme-choice]').forEach(b=>b.setAttribute('aria-checked',String(b===btn)));const status=document.getElementById('themeStatus');if(status)status.textContent='Background saved! This theme will be used across The Hunt on this device.';};
    });
  }
  setupThemes();
  // Lightweight synthesized UI sounds: no external audio files required.
  const VOLUME_KEY='hunt-sound-volume';
  function getVolume(){const raw=localStorage.getItem(VOLUME_KEY);if(raw===null)return 7;const n=Number(raw);return Number.isFinite(n)?Math.max(0,Math.min(10,n)):7;}
  function setVolume(n){const value=Math.max(0,Math.min(10,Number(n)||0));localStorage.setItem(VOLUME_KEY,String(value));return value;}
  let audioContext=null;
  function playUiSound(){const level=getVolume();if(level<=0)return;try{const Ctx=window.AudioContext||window.webkitAudioContext;if(!Ctx)return;audioContext=audioContext||new Ctx();if(audioContext.state==='suspended')audioContext.resume();const now=audioContext.currentTime;const osc=audioContext.createOscillator();const gain=audioContext.createGain();const filter=audioContext.createBiquadFilter();osc.type='sine';osc.frequency.setValueAtTime(620,now);osc.frequency.exponentialRampToValueAtTime(420,now+0.055);filter.type='lowpass';filter.frequency.value=1800;gain.gain.setValueAtTime(Math.min(.11,level/10*.11),now);gain.gain.exponentialRampToValueAtTime(.0001,now+.075);osc.connect(filter);filter.connect(gain);gain.connect(audioContext.destination);osc.start(now);osc.stop(now+.08);}catch(e){/* Audio is optional; never interrupt navigation. */}}
  function setupSound(){const slider=document.getElementById('soundVolume');const value=document.getElementById('soundVolumeValue');const test=document.getElementById('testSoundBtn');const status=document.getElementById('soundStatus');if(slider){slider.value=String(getVolume());if(value)value.textContent=slider.value;slider.addEventListener('input',()=>{const v=setVolume(slider.value);if(value)value.textContent=String(v);if(status)status.textContent=v===0?'Sounds are off.':'Volume saved.';});}if(test)test.addEventListener('click',()=>{if(getVolume()===0){if(status)status.textContent='Sound is off. Raise the volume above 0 to hear the test.';return;}playUiSound();if(status)status.textContent='Test sound played.';});document.addEventListener('click',event=>{const target=event.target instanceof Element?event.target.closest('button,.button,[role="button"]'):null;if(!target||target.disabled||target.id==='testSoundBtn'||target.matches('input,select,textarea'))return;playUiSound();},true);}
  setupSound();
  // The Hunt Radio: procedurally composed instrumental lounge-jazz tracks.
  // Each arrangement changes at random after 2:30–5:00; no external audio or vocals.
  const MUSIC_VOL_KEY='hunt-music-volume', MUSIC_ON_KEY='hunt-music-enabled';
  let musicTimer=null, trackTimer=null, musicStep=0, musicGain=null, musicStarted=false, musicMuted=false, currentTrack=-1, trackName='', trackStartedAt=0, trackDuration=0, radioUiTimer=null;
  const radioTracks=[
    {name:'Velvet Afterglow',tempo:690,chords:[[174.61,220,261.63,329.63,392],[130.81,164.81,196,246.94,293.66],[146.83,185,220,277.18,329.63],[164.81,207.65,246.94,311.13,369.99]],melody:[392,440,523.25,493.88,440,392,349.23,392,440,523.25,587.33,523.25,440,392,329.63,349.23]},
    {name:'The Green Room',tempo:760,chords:[[196,246.94,293.66,369.99,440],[164.81,207.65,246.94,311.13,369.99],[146.83,185,220,277.18,329.63],[174.61,220,261.63,329.63,392]],melody:[440,493.88,587.33,523.25,440,392,440,493.88,523.25,587.33,659.25,587.33,523.25,493.88,440,392]},
    {name:'Rosewood Waltz',tempo:820,chords:[[155.56,196,233.08,293.66,349.23],[207.65,261.63,311.13,392,466.16],[174.61,220,261.63,329.63,392],[196,246.94,293.66,369.99,440]],melody:[349.23,392,466.16,440,392,349.23,311.13,349.23,392,466.16,523.25,466.16,440,392,349.23,311.13]},
    {name:'Midnight at the Conservatory',tempo:720,chords:[[207.65,261.63,311.13,392,466.16],[174.61,220,261.63,329.63,392],[196,246.94,293.66,369.99,440],[164.81,207.65,246.94,311.13,369.99]],melody:[466.16,523.25,622.25,587.33,523.25,466.16,415.3,466.16,523.25,622.25,698.46,622.25,587.33,523.25,466.16,415.3]},
    {name:'Champagne & Brass',tempo:650,chords:[[185,233.08,277.18,349.23,415.3],[164.81,207.65,246.94,311.13,369.99],[196,246.94,293.66,369.99,440],[174.61,220,261.63,329.63,392]],melody:[415.3,466.16,554.37,523.25,466.16,415.3,369.99,415.3,466.16,554.37,622.25,554.37,523.25,466.16,415.3,369.99]}
  ];
  function migrateMusicVolume(){const raw=localStorage.getItem(MUSIC_VOL_KEY);if(raw===null)return 75;let n=Number(raw);if(!Number.isFinite(n))n=75;else if(n>0&&n<=10)n*=10;return Math.max(0,Math.min(100,Math.round(n/5)*5));}
  function getMusicVolume(){return migrateMusicVolume();}
  function musicContext(){const Ctx=window.AudioContext||window.webkitAudioContext;if(!Ctx)return null;audioContext=audioContext||new Ctx();return audioContext;}
  function jazzNote(freq,when,duration,level,wave='sine'){
    const ctx=musicContext();if(!ctx||!musicGain)return;const osc=ctx.createOscillator(),gain=ctx.createGain(),filter=ctx.createBiquadFilter();
    osc.type=wave;osc.frequency.setValueAtTime(freq,when);filter.type='lowpass';filter.frequency.value=wave==='triangle'?1900:1100;filter.Q.value=.35;
    gain.gain.setValueAtTime(.0001,when);gain.gain.linearRampToValueAtTime(level,when+.04);gain.gain.setTargetAtTime(level*.68,when+.05,.12);gain.gain.exponentialRampToValueAtTime(.0001,when+duration);
    osc.connect(filter);filter.connect(gain);gain.connect(musicGain);osc.start(when);osc.stop(when+duration+.04);
  }
  function pickTrack(){let idx=Math.floor(Math.random()*radioTracks.length);if(radioTracks.length>1&&idx===currentTrack)idx=(idx+1+Math.floor(Math.random()*(radioTracks.length-1)))%radioTracks.length;currentTrack=idx;return radioTracks[idx];}
  function scheduleJazzBar(){const ctx=musicContext(),track=radioTracks[currentTrack];if(!ctx||!track||!musicGain)return;const vol=getMusicVolume()/100;musicGain.gain.setTargetAtTime(musicMuted?0:vol*.78,ctx.currentTime,.3);const now=ctx.currentTime+.04,bar=Math.floor(musicStep/4)%track.chords.length,chord=track.chords[bar];
    if(musicStep%4===0){chord.forEach((f,i)=>jazzNote(f,now+i*.012,1.65,.025,'triangle'));jazzNote(chord[0]/2,now,1.45,.12,'sine');jazzNote(chord[0]/2*1.5,now+.48,.42,.045,'sine');jazzNote(chord[1]*1.5,now+.82,.34,.026,'triangle');if(Math.random()>.5)jazzNote(chord[3]*2,now+1.15,.2,.012,'sine');}
    const melody=track.melody[(musicStep+Math.floor(Math.random()*3))%track.melody.length];if(musicStep%2===0){const note=melody*(Math.random()>.86?2:1);jazzNote(note,now+.12,.52,.047,Math.random()>.68?'sine':'triangle');if(Math.random()>.78)jazzNote(note*.75,now+.43,.25,.014,'sine');}
    jazzNote(chord[2]*2,now+.42,.16,.018,'sine');musicStep++;
  }
  function beginRadioTrack(forceIndex=null){if(!musicStarted)return;const ctx=musicContext();if(!ctx)return;const track=forceIndex===null?pickTrack():(currentTrack=forceIndex,radioTracks[currentTrack]);trackName=track.name;musicStep=Math.floor(Math.random()*8);if(musicTimer)clearInterval(musicTimer);if(musicGain&&audioContext)musicGain.gain.setTargetAtTime(0,audioContext.currentTime,.18);setTimeout(()=>{if(musicStarted)scheduleJazzBar();},180);musicTimer=setInterval(scheduleJazzBar,track.tempo);if(trackTimer)clearTimeout(trackTimer);trackDuration=150000+Math.random()*150000;trackStartedAt=Date.now();trackTimer=setTimeout(beginRadioTrack,trackDuration);const status=document.getElementById('musicStatus');if(status)status.textContent='The Hunt Radio · Now playing: '+trackName+'.';updateRadioPanel();}
  function startMusic(){const ctx=musicContext();if(!ctx||getMusicVolume()===0)return false;try{if(ctx.state==='suspended')ctx.resume();if(musicTimer)clearInterval(musicTimer);if(trackTimer)clearTimeout(trackTimer);if(musicGain){try{musicGain.disconnect();}catch(e){}}musicGain=ctx.createGain();musicGain.gain.value=0;musicGain.connect(ctx.destination);musicStarted=true;localStorage.setItem(MUSIC_ON_KEY,'1');beginRadioTrack();return true;}catch(e){return false;}}
  function stopMusic(){if(musicTimer)clearInterval(musicTimer);if(trackTimer)clearTimeout(trackTimer);musicTimer=null;trackTimer=null;musicStarted=false;localStorage.setItem(MUSIC_ON_KEY,'0');if(musicGain&&audioContext){try{musicGain.gain.setTargetAtTime(0,audioContext.currentTime,.12);}catch(e){}}}
  function formatRadioTime(ms){const sec=Math.max(0,Math.floor(ms/1000));return Math.floor(sec/60)+':'+String(sec%60).padStart(2,'0');}
  function updateRadioPanel(){const current=document.getElementById('radioCurrentTrack'),time=document.getElementById('radioTrackTime'),progress=document.getElementById('radioProgress'),list=document.getElementById('radioTrackList');if(current)current.textContent=musicStarted?(trackName||'Starting radio…')+(musicMuted?' · MUTED':''):'Radio is stopped';if(time)time.textContent=musicStarted?formatRadioTime(Date.now()-trackStartedAt)+' / '+formatRadioTime(trackDuration):'0:00 / —';if(progress)progress.value=musicStarted&&trackDuration?Math.min(100,(Date.now()-trackStartedAt)/trackDuration*100):0;if(list){list.innerHTML='';radioTracks.forEach((t,i)=>{const li=document.createElement('li');li.className=i===currentTrack&&musicStarted?'radio-track active':'radio-track';const name=document.createElement('span');name.textContent=(i===currentTrack&&musicStarted?'♫ ':'')+t.name;const duration=document.createElement('small');duration.textContent=i===currentTrack&&musicStarted?formatRadioTime(trackDuration):'2:30–5:00';li.append(name,duration);list.appendChild(li);});}}
  function setupRadioWidget(){if(document.getElementById('huntRadioFab'))return;const style=document.createElement('style');style.textContent='.hunt-radio-fab{position:fixed;right:16px;bottom:86px;z-index:30;border:1px solid var(--green);border-radius:999px;background:#102116;color:#eff8f0;padding:12px 16px;font-weight:800;box-shadow:0 8px 28px #0009;cursor:pointer}.hunt-radio-modal{position:fixed;inset:0;z-index:40;background:#000b;display:none;align-items:flex-end;justify-content:flex-end;padding:16px}.hunt-radio-modal.open{display:flex}.hunt-radio-card{width:min(420px,100%);max-height:82vh;overflow:auto;background:#0b140e;color:#eff8f0;border:1px solid var(--green);border-radius:18px;padding:18px;box-shadow:0 18px 60px #000c}.hunt-radio-card h2{margin:0 0 6px}.hunt-radio-current{border:1px solid var(--line);border-radius:12px;padding:12px;margin:12px 0}.hunt-radio-current strong{display:block;color:var(--green);margin-bottom:6px}.hunt-radio-current progress{width:100%;accent-color:var(--green)}.radio-track-list{list-style:none;padding:0;margin:12px 0}.radio-track{display:flex;justify-content:space-between;gap:12px;padding:11px 8px;border-bottom:1px solid #ffffff18}.radio-track.active{color:var(--green);background:#65f28b12;border-radius:8px}.radio-track small{white-space:nowrap;color:#9bb39f}.hunt-radio-actions{display:flex;gap:8px;flex-wrap:wrap}.hunt-radio-actions button{flex:1}.hunt-radio-close{float:right} @media(max-width:560px){.hunt-radio-fab{right:12px;bottom:92px}.hunt-radio-modal{padding:8px}.hunt-radio-card{max-height:85vh}}';document.head.appendChild(style);const fab=document.createElement('button');fab.id='huntRadioFab';fab.className='hunt-radio-fab';fab.type='button';fab.textContent='♫ Radio';fab.setAttribute('aria-label','Open The Hunt Radio song list');const modal=document.createElement('div');modal.id='huntRadioModal';modal.className='hunt-radio-modal';modal.innerHTML='<section class="hunt-radio-card" role="dialog" aria-modal="true" aria-labelledby="radioTitle"><button type="button" class="secondary hunt-radio-close" id="radioClose">Close ✕</button><h2 id="radioTitle">The Hunt Radio</h2><p class="muted">Original synthesized instrumental jazz · 5 tracks · randomized variations</p><div class="hunt-radio-current"><strong id="radioCurrentTrack">Radio is stopped</strong><span id="radioTrackTime">0:00 / —</span><progress id="radioProgress" max=100 value=0></progress></div><ol class="radio-track-list" id="radioTrackList"></ol><div class="hunt-radio-actions"><button type="button" id="radioPlay">Play / Restart</button><button type="button" class="secondary" id="radioMute">Mute</button><button type="button" class="secondary" id="radioNext">Next song</button><button type="button" class="secondary" id="radioStop">Stop</button><button type="button" class="secondary" id="radioSettings">Music settings</button></div><p class="muted">Each play lasts a random 2:30–5:00. The timer shows the current track elapsed and total time.</p></section>';document.body.append(fab,modal);const open=()=>{modal.classList.add('open');updateRadioPanel();};const close=()=>modal.classList.remove('open');fab.addEventListener('click',open);document.getElementById('radioClose').addEventListener('click',close);modal.addEventListener('click',e=>{if(e.target===modal)close();});document.getElementById('radioPlay').addEventListener('click',()=>{if(getMusicVolume()===0){localStorage.setItem(MUSIC_VOL_KEY,'75');const slider=document.getElementById('musicVolume');if(slider)slider.value='75';const value=document.getElementById('musicVolumeValue');if(value)value.textContent='75';}startMusic();updateRadioPanel();});document.getElementById('radioMute').addEventListener('click',()=>{musicMuted=!musicMuted;const b=document.getElementById('radioMute');b.textContent=musicMuted?'Unmute':'Mute';if(musicGain&&audioContext)musicGain.gain.setTargetAtTime(musicMuted?0:getMusicVolume()/100*.78,audioContext.currentTime,.12);updateRadioPanel();});document.getElementById('radioNext').addEventListener('click',()=>{if(!musicStarted){if(!startMusic())return; }else beginRadioTrack();updateRadioPanel();});document.getElementById('radioStop').addEventListener('click',()=>{stopMusic();updateRadioPanel();});document.getElementById('radioSettings').addEventListener('click',()=>{window.location.href='settings.html#musicSettings';});if(radioUiTimer)clearInterval(radioUiTimer);radioUiTimer=setInterval(updateRadioPanel,1000);updateRadioPanel();}
  function setupMusic(){const slider=document.getElementById('musicVolume'),value=document.getElementById('musicVolumeValue'),toggle=document.getElementById('musicToggleBtn'),stop=document.getElementById('musicStopBtn'),status=document.getElementById('musicStatus');
    localStorage.setItem(MUSIC_VOL_KEY,String(getMusicVolume()));
    if(slider){slider.min='0';slider.max='100';slider.step='5';slider.value=String(getMusicVolume());if(value)value.textContent=slider.value;slider.addEventListener('input',()=>{const v=Math.max(0,Math.min(100,Math.round(Number(slider.value)/5)*5));localStorage.setItem(MUSIC_VOL_KEY,String(v));if(value)value.textContent=String(v);if(musicGain&&audioContext)musicGain.gain.setTargetAtTime(v/100*.78,audioContext.currentTime,.12);if(v===0)stopMusic();if(status)status.textContent=v===0?'Music is off.':'Radio volume saved: '+v+'%.';});}
    if(toggle)toggle.addEventListener('click',()=>{if(getMusicVolume()===0){if(status)status.textContent='Raise music volume above 0 first.';return;}if(startMusic()){toggle.textContent='Restart radio';}});
    if(stop)stop.addEventListener('click',()=>{stopMusic();if(status)status.textContent='Radio stopped.';if(toggle)toggle.textContent='Play radio';});
    if(!slider&&localStorage.getItem(MUSIC_ON_KEY)==='1'&&getMusicVolume()>0){const resume=()=>{if(!musicStarted)startMusic();document.removeEventListener('pointerdown',resume);document.removeEventListener('keydown',resume);};document.addEventListener('pointerdown',resume,{once:true});document.addEventListener('keydown',resume,{once:true});}
  }
  setupMusic();
  setupRadioWidget();
  const BOUNDARY_SHAPE_KEY='hunt-boundary-default-shape', BOUNDARY_SIZE_KEY='hunt-boundary-default-size';
  function setupBoundaryDefaults(){
    const shape=document.getElementById('settingsBoundaryShape'), size=document.getElementById('settingsBoundarySize'), save=document.getElementById('saveBoundaryDefaults'), status=document.getElementById('settingsBoundaryStatus');
    if(shape)shape.value=localStorage.getItem(BOUNDARY_SHAPE_KEY)||'square';
    if(size)size.value=String(Math.max(50,Math.min(10000,Number(localStorage.getItem(BOUNDARY_SIZE_KEY)||500))));
    if(save)save.addEventListener('click',()=>{const sh=shape?.value||'square',sz=Math.max(50,Math.min(10000,Number(size?.value)||500));localStorage.setItem(BOUNDARY_SHAPE_KEY,sh);localStorage.setItem(BOUNDARY_SIZE_KEY,String(sz));if(status)status.textContent='Boundary defaults saved. The live map will use '+sh+' at '+sz+' metres.';});
    const mapShape=document.getElementById('mapBoundaryShape'),mapSize=document.getElementById('mapBoundarySize');
    if(mapShape)mapShape.value=localStorage.getItem(BOUNDARY_SHAPE_KEY)||'square';
    if(mapSize)mapSize.value=String(Math.max(50,Math.min(10000,Number(localStorage.getItem(BOUNDARY_SIZE_KEY)||500))));
  }
  setupBoundaryDefaults();
  const cfg=window.HUNT_CONFIG||{};
  const rawUrl=typeof cfg.supabaseUrl==='string'?cfg.supabaseUrl.trim():'';
  const rawKey=typeof cfg.supabaseAnonKey==='string'?cfg.supabaseAnonKey.trim():'';
  let configured=false, configProblem='';
  const looksPlaceholder=/(PASTE_|YOUR_REAL_|YOUR_SUPABASE_|YOUR_PROJECT)/i.test(rawUrl+' '+rawKey);
  if(rawUrl && rawKey && !looksPlaceholder){
    try{
      const parsedUrl=new URL(rawUrl);
      // Supabase client expects the project base URL, not /auth/v1/signup or another API path.
      if(parsedUrl.protocol!=='https:' || !parsedUrl.hostname.endsWith('.supabase.co') || parsedUrl.hostname==='supabase.co' || parsedUrl.username || parsedUrl.password){
        configProblem='The Supabase URL must be your Project URL, for example https://abcdefgh.supabase.co (not the dashboard URL or an API endpoint).';
      } else {
        cfg.supabaseUrl=parsedUrl.origin; // Strip pasted /auth/v1, /rest/v1, and trailing paths from a valid project URL.
        cfg.supabaseAnonKey=rawKey;
        configured=true;
      }
    }catch(_){ configProblem='The Supabase Project URL is not a valid URL. Check config.js.'; }
  }
  const online=configured;
  const initName=document.body.dataset.init;
  const needsMap=!!document.getElementById('map')||!!document.getElementById('boundaryMap');
  function load(src){return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.onload=resolve;s.onerror=()=>reject(new Error('Could not load '+src));document.body.appendChild(s);});}
  try{
    await load('i18n.js');
    if(needsMap){const css=document.createElement('link');css.rel='stylesheet';css.href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';document.head.appendChild(css);await load('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js');}
    if(online){await load('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2');await load('app-online.js');}
    else {
      await load('app-local.js');
      if(configProblem){
        const n=document.createElement('p');n.className='notice';
        n.textContent='ONLINE SETUP ERROR: '+configProblem+' The app has not connected to Supabase; local demo mode is active. Fix config.js, redeploy, then hard-refresh (Ctrl+Shift+R).';
        document.querySelector('main')?.prepend(n);
      }
    }
    if(typeof window[initName]==='function')await window[initName]();
    if(typeof window.applyHuntLanguage==='function')window.applyHuntLanguage();
  }catch(err){console.error(err);const n=document.createElement('p');n.className='notice';n.textContent='The page could not load a required script. Check your internet connection and Supabase setup, then refresh.';document.querySelector('main')?.prepend(n);}
})();
