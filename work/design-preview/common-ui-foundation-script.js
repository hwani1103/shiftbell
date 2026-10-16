
    (()=>{
      const root=document.getElementById('shiftbell-foundation');
      const stage=root.querySelector('.sf-stage');
      const state={palette:'sage',button:'flat',radius:20,padding:20};
      const overlay=root.querySelector('.sf-overlay');
      const title=root.querySelector('#sf-dialog-title');
      const body=root.querySelector('.sf-dialog-body');
      const confirm=root.querySelector('[data-confirm]');
      let mode='name',lastFocus=null;
      const palettes={sage:['#44685a','#b6d5c3','#f3f5ef','#19221d','#eaf1e6','#34463a','#2a3c37','#e8f1ed','#21382c'],blue:['#385fa4','#adc8ff','#f3f6fa','#161e29','#eaf0fb','#293b57','#253449','#edf1f7','#182846'],oat:['#586780','#c1cee5','#f5f1e9','#211e19','#eceef3','#39404c','#3c3b39','#f1ece5','#253044']};
      function render(){const p=palettes[state.palette]||palettes.sage;stage.dataset.button=state.button;stage.style.setProperty('--sf-radius',state.radius+'px');stage.style.setProperty('--sf-pad',state.padding+'px');stage.style.setProperty('--sf-accent','light-dark('+p[0]+','+p[1]+')');stage.style.setProperty('--sf-bg','light-dark('+p[2]+','+p[3]+')');stage.style.setProperty('--sf-soft','light-dark('+p[4]+','+p[5]+')');stage.style.setProperty('--sf-text','light-dark('+p[6]+','+p[7]+')');stage.style.setProperty('--sf-on','light-dark(#ffffff,'+p[8]+')');}
      function close(){overlay.hidden=true;if(lastFocus)lastFocus.focus();}
      function open(next){mode=next;lastFocus=document.activeElement;confirm.classList.toggle('sf-danger',mode==='delete');confirm.classList.toggle('sf-primary',mode!=='delete');if(mode==='name'){title.textContent='근무명 추가';body.innerHTML='<label class="sf-label" for="sf-new-name">새 근무명</label><input id="sf-new-name" class="sf-field" placeholder="예: 오후 근무" maxlength="10"><div class="sf-caption">시안용 입력 · 실제 저장 없음</div>';confirm.textContent='추가';}else if(mode==='delete'){title.textContent='근무명을 삭제할까요?';body.innerHTML='<p>선택한 항목의 삭제를 확인하는 짧은 창입니다.</p>';confirm.textContent='삭제';}else if(mode==='restore'){title.textContent='백업에서 가져오기';body.innerHTML='<p>기존 백업 확인과 복원 절차는 유지합니다.</p>';confirm.textContent='파일 선택';}else{title.textContent='다음 단계';body.innerHTML='<p>다음은 근무 패턴을 정하는 단계입니다.</p>';confirm.textContent='확인';}overlay.hidden=false;const input=body.querySelector('input');(input||root.querySelector('[data-close]')).focus();}
      root.querySelectorAll('[data-open]').forEach(b=>b.addEventListener('click',()=>open(b.dataset.open)));
      root.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',close));
      confirm.addEventListener('click',()=>{const input=body.querySelector('input');if(mode==='name'&&input&&input.value.trim()){const chip=document.createElement('span');chip.className='sf-chip';chip.textContent=input.value.trim();root.querySelector('.sf-card .sf-chips').append(chip);}close();});
      root.querySelectorAll('[data-feedback]').forEach(b=>b.addEventListener('click',()=>root.querySelector('.sf-feedback').textContent=b.dataset.feedback+' · 시안에서만 표시'));
      root.querySelectorAll('.sf-choice').forEach(b=>b.addEventListener('click',()=>{root.querySelectorAll('.sf-choice').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));}));
      root.addEventListener('keydown',e=>{if(overlay.hidden)return;if(e.key==='Escape'){close();return;}if(e.key==='Tab'){const items=[...overlay.querySelectorAll('button,input')];const first=items[0],last=items[items.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}});
      render();
      if(globalThis.Tweak){const tweak=new Tweak({container:stage,onChange:render});tweak.addSelect(state,'palette',{label:'색상 토큰',options:[{label:'세이지',value:'sage'},{label:'블루',value:'blue'},{label:'오트밀',value:'oat'}]});tweak.addSelect(state,'button',{label:'주요 버튼',options:[{label:'단색',value:'flat'},{label:'그라데이션 강조',value:'gradient'}]});tweak.addSlider(state,'radius',{label:'카드·창 모서리',min:12,max:24,unit:'px'});tweak.addSlider(state,'padding',{label:'카드 안 여백',min:16,max:24,unit:'px'});}
    })();
  