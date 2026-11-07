// VoiceStudio phone helpers. Injected by patch-ui.sh next to vs-mobile.css. Does nothing on wide screens.
// Shares the 767px breakpoint, the app's data-slot hooks and the --vs-* properties with vs-mobile.css: change both together.
// The phone lock (gate.py): when it has locked again, every API call gets a 401 with X-Gate-Locked. The app would
// answer that with its own PIN box ("Share on your network"), which isn't ours, so reload: the gate then serves the
// phone lock (password / Face ID) instead of the app. Runs at every width.
(() => {
  const reload = () => {
    try {
      const last = +sessionStorage.getItem('vs_gate_reload') || 0;
      if (Date.now() - last < 5000) return; // never loop if something else is wrong
      sessionStorage.setItem('vs_gate_reload', String(Date.now()));
    } catch { /* storage blocked: reload anyway */ }
    location.reload();
  };
  const realFetch = window.fetch.bind(window);
  window.fetch = async (...args) => {
    const res = await realFetch(...args);
    if (res.status === 401 && res.headers.get('X-Gate-Locked') === '1') reload();
    return res;
  };
  // In case the app made its first call before this script ran.
  window.addEventListener('ov:auth-required', () => {
    realFetch('/api/gate-ping', { credentials: 'include' })
      .then((r) => { if (r.status === 401 && r.headers.get('X-Gate-Locked') === '1') reload(); })
      .catch(() => {});
  });
})();

(() => {
  const phone = window.matchMedia('(max-width: 767px)');
  const PANE = 'aside[data-slot="secondary-sidebar"]';
  const openPane = () => document.querySelector(PANE + ':not([data-collapsed])');
  const collapseBtn = (pane) =>
    pane && (pane.querySelector('button[aria-label="Collapse pane"]') ||
             pane.querySelector('[data-slot="secondary-sidebar-header"] button[aria-expanded="true"]'));
  const closeDrawer = () => { const btn = collapseBtn(openPane()); if (btn) btn.click(); return !!btn; };

  // Tap on the dimmed area beside the drawer closes it (and doesn't also hit what's under it).
  document.addEventListener('pointerdown', (e) => {
    if (!phone.matches) return;
    const pane = openPane();
    if (!pane || pane.contains(e.target)) return;
    const root = document.getElementById('root');
    // Menus, dialogs and popovers render in portals outside #root; leave those alone.
    if (!root || !root.contains(e.target)) return;
    // The bottom tab bar still works while the drawer is open; it just closes it too.
    if (e.target.closest('aside.brand-sidebar')) { closeDrawer(); return; }
    e.preventDefault();
    e.stopPropagation();
    const swallow = (ev) => { ev.preventDefault(); ev.stopPropagation(); };
    document.addEventListener('click', swallow, { capture: true, once: true });
    setTimeout(() => document.removeEventListener('click', swallow, true), 400); // longer than a tap
    closeDrawer();
  }, true);

  // Picking a row (a saved voice, a past take) closes the drawer so you see the result. Rows are the app's
  // aria-pressed buttons; their play/star/delete actions are data-slot buttons and leave the drawer open.
  document.addEventListener('click', (e) => {
    if (!phone.matches) return;
    const pane = openPane();
    if (!pane) return;
    const row = e.target.closest('[data-slot="secondary-sidebar-content"] button[aria-pressed]:not([data-slot])');
    if (row && pane.contains(row)) setTimeout(closeDrawer, 120); // let the app handle the pick first
  });

  // Keep the header gap equal to the pill's real width (labels differ per workspace).
  const syncHeaderGaps = () => {
    if (!phone.matches) return;
    const pill = document.querySelector(PANE + '[data-collapsed] > [data-slot="secondary-sidebar-expand"]');
    if (pill) document.documentElement.style.setProperty('--vs-pill-w', Math.ceil(pill.getBoundingClientRect().right + 10) + 'px'); // +10: gap after the pill
    const corner = document.querySelector('[data-slot="account-corner"]');
    if (corner) document.documentElement.style.setProperty('--vs-corner-w', Math.ceil(corner.getBoundingClientRect().width) + 'px');
  };

  // Each pane starts shut the first time it shows up: the page content is what you came for.
  // After that the app's own saved open/closed state is left alone.
  const seen = new WeakSet();
  const collapseNewPanes = () => {
    if (phone.matches) {
      for (const pane of document.querySelectorAll(PANE)) {
        if (seen.has(pane)) continue;
        if (!pane.hasAttribute('data-collapsed') && !collapseBtn(pane)) continue; // not rendered yet
        seen.add(pane);
        if (!pane.hasAttribute('data-collapsed')) collapseBtn(pane).click();
      }
    }
    syncHeaderGaps();
  };
  let queued = false;
  const schedule = () => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; collapseNewPanes(); }); } };
  new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['data-collapsed'] });
  window.addEventListener('resize', schedule);
  // Going somewhere else shuts the drawer, and the Settings chip strip scrolls to the current section.
  const showActiveSetting = () => {
    const activeChip = document.querySelector('nav[aria-label="Settings"]')
      ?.querySelector('[aria-current="page"], [data-active], [data-status="active"]');
    if (activeChip) activeChip.scrollIntoView({ block: 'nearest', inline: 'center' });
  };
  // The delays give the app time to render the new route (and, on first load, to finish starting up).
  window.addEventListener('hashchange', () => { if (phone.matches) { closeDrawer(); setTimeout(showActiveSetting, 150); } });
  setTimeout(() => phone.matches && showActiveSetting(), 1500);
})();
