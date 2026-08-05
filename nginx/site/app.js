const tabs = [...document.querySelectorAll('[role="tab"]')];
const toast = document.querySelector('#toast');
let toastTimer;

function selectTab(selected) {
  tabs.forEach((tab) => {
    const active = tab === selected;
    tab.setAttribute('aria-selected', String(active));
    const panel = document.getElementById(tab.dataset.tab);
    panel.hidden = !active;
    panel.classList.toggle('active', active);
  });
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const offset = event.key === 'ArrowRight' ? 1 : -1;
    const next = tabs[(index + offset + tabs.length) % tabs.length];
    selectTab(next);
    next.focus();
  });
});

async function copyText(value, button) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
    } else {
      const input = document.createElement('textarea');
      input.value = value;
      input.setAttribute('readonly', '');
      input.style.position = 'fixed';
      input.style.opacity = '0';
      document.body.appendChild(input);
      input.select();
      const copied = document.execCommand('copy');
      input.remove();
      if (!copied) throw new Error('Copy failed');
    }
    const previous = button.textContent;
    button.textContent = 'Zkopírováno';
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toast.classList.remove('show');
      button.textContent = previous;
    }, 1800);
  } catch (_) {
    button.textContent = 'Označte a zkopírujte';
  }
}

document.querySelectorAll('[data-copy]').forEach((button) => {
  button.addEventListener('click', () => copyText(button.dataset.copy, button));
});

document.querySelectorAll('[data-copy-target]').forEach((button) => {
  button.addEventListener('click', () => {
    const target = document.getElementById(button.dataset.copyTarget);
    copyText(target.innerText, button);
  });
});
