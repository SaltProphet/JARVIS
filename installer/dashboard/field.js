function createLayeredField() {
 const host = document.querySelector('.orb-stage');
 host.innerHTML = '<canvas id="system-field" aria-hidden="true"></canvas><div class="field-nodes">'+['Input','Whisper','Agent','Kokoro'].map((name,i)=>`<button class="field-node" data-layer="${i}">${name}<small>Checking</small></button>`).join('')+'</div>';
 const canvas = document.getElementById('system-field'), ctx = canvas.getContext('2d');
 const reduce = matchMedia('(prefers-reduced-motion: reduce)');
 let width=0,height=0,frame=0,phase=0,last=0;
 const layers=[{id:null,label:'Input'},{id:'whisper',label:'Whisper'},{id:'hermes',label:'Agent'},{id:'kokoro',label:'Kokoro'}];
 host.querySelectorAll('button').forEach((button,i)=>button.addEventListener('click',()=>{
  if(i===2){document.querySelector('[data-view="agents"]').click();return;}
  openDrawer(); document.getElementById(i===0?'input-device':i===3?'output-device':'drawer-services').scrollIntoView({block:'center'});
  if(i===0) document.getElementById('input-device').focus();
 }));
 function size(){const box=host.getBoundingClientRect();width=box.width;height=box.height;const ratio=Math.min(devicePixelRatio||1,2);canvas.width=width*ratio;canvas.height=height*ratio;ctx.setTransform(ratio,0,0,ratio,0,0);draw(0);}
 function draw(time){
  const status=document.getElementById('conversation-status').textContent;
  const active=talk.captureActive?0:status.includes('TRANSCRIB')?1:status.includes('WAITING')?2:status.includes('SPEAKING')?3:-1;
  let level=0;if(meterAnalyser&&talk.captureActive){const data=new Uint8Array(meterAnalyser.fftSize);meterAnalyser.getByteTimeDomainData(data);level=Math.sqrt(data.reduce((sum,n)=>sum+((n-128)/128)**2,0)/data.length);}
  ctx.clearRect(0,0,width,height); const scale=Math.min(width/560,1),cx=width*.47;
  layers.forEach((layer,i)=>{
   const service=serviceCache.find(item=>item.id===layer.id),error=service?.state==='error';
   const color=error?'#bd5146':active===i?'#c46936':'#999d9f';
   const y=54+i*(height-100)/3,rx=(80+i*24)*scale,ry=(20+i*4)*scale;
   ctx.strokeStyle=active===i?'#70412a':'#282b2d';ctx.lineWidth=1;ctx.beginPath();ctx.ellipse(cx,y,rx*(1+(i===0?level*2:0)),ry,0,0,Math.PI*2);ctx.stroke();
   if(i<3){ctx.beginPath();ctx.moveTo(cx,y+ry);ctx.lineTo(cx,y+(height-100)/3-ry);ctx.stroke();}
   for(let n=0;n<18+i*4;n++){const a=n/(18+i*4)*Math.PI*2+phase*(i%2?-1:1);const x=cx+Math.cos(a)*rx,ny=y+Math.sin(a)*ry;ctx.globalAlpha=.45+(Math.sin(a)+1)*.22;ctx.strokeStyle=color;const s=4+(Math.sin(a)+1)*1.4;ctx.strokeRect(x-s/2,ny-s/2,s,s);}
   ctx.globalAlpha=1;ctx.strokeStyle=color;ctx.strokeRect(cx-5,y-5,10,10);
   const button=host.querySelector(`[data-layer="${i}"]`);button.style.top=`${y-18}px`;button.style.left=`${cx+rx+20}px`;
   button.classList.toggle('active',active===i);button.classList.toggle('error',error);
   button.querySelector('small').textContent=i===0?(talk.captureActive?'Listening':'Microphone'):active===i?status.toLowerCase():service?.state||'Unknown';
  });
  if(active>=0&&!reduce.matches){ctx.fillStyle='#c46936';ctx.fillRect(cx-2,50+(time/14%(height-100)),4,4);}
 }
 function loop(time){frame=0;if(document.hidden)return;if(time-last>40){phase=reduce.matches?0:time/26000;draw(time);last=time;}frame=requestAnimationFrame(loop);}
 function resume(){if(frame)cancelAnimationFrame(frame);frame=0;if(!document.hidden)frame=requestAnimationFrame(loop);}
 new ResizeObserver(size).observe(host);document.addEventListener('visibilitychange',resume);reduce.addEventListener('change',()=>draw(0));resume();
}
