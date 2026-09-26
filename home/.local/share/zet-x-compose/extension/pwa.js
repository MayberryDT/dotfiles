(() => {
  if (/^\/compose(\/|$)/.test(location.pathname)) return;

  const CSS = `
    html, body, * { scrollbar-width: none !important; }
    *::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: none !important; }
    html.zet-x-autoscroll, html.zet-x-autoscroll * { cursor: all-scroll !important; }
    #zet-x-autoscroll-mark {
      position: fixed;
      width: 28px;
      height: 28px;
      margin: -14px 0 0 -14px;
      border: 2px solid rgba(29, 155, 240, 0.95);
      border-radius: 50%;
      background: rgba(0, 0, 0, 0.45);
      z-index: 2147483647;
      pointer-events: none;
    }
    #zet-x-autoscroll-mark::after {
      content: "";
      position: absolute;
      inset: 8px;
      border-radius: 50%;
      background: rgba(29, 155, 240, 0.95);
    }
  `;

  function isHdmiX() {
    const standalone = window.matchMedia("(display-mode: standalone)").matches
      || window.matchMedia("(display-mode: minimal-ui)").matches;
    const portraitApp = window.outerWidth <= 1120 && window.outerHeight >= 1400;
    return standalone || portraitApp;
  }

  function injectCss() {
    if (!isHdmiX() || document.getElementById("zet-x-pwa-css")) return;
    const style = document.createElement("style");
    style.id = "zet-x-pwa-css";
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  function scrollRoot(start) {
    let el = start instanceof Element ? start : document.elementFromPoint(0, 0);
    while (el && el !== document.body && el !== document.documentElement) {
      const style = window.getComputedStyle(el);
      const oy = style.overflowY;
      if ((oy === "auto" || oy === "scroll" || oy === "overlay") && el.scrollHeight > el.clientHeight + 8) {
        return el;
      }
      el = el.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  }

  let active = false;
  let originY = 0;
  let velocity = 0;
  let target = null;
  let marker = null;
  let raf = 0;

  function tick() {
    if (!active) return;
    if (target) target.scrollTop += velocity;
    else window.scrollBy(0, velocity);
    raf = requestAnimationFrame(tick);
  }

  function stop() {
    active = false;
    velocity = 0;
    target = null;
    document.documentElement.classList.remove("zet-x-autoscroll");
    if (marker) {
      marker.remove();
      marker = null;
    }
    if (raf) {
      cancelAnimationFrame(raf);
      raf = 0;
    }
  }

  function start(event) {
    active = true;
    originY = event.clientY;
    target = scrollRoot(event.target);
    document.documentElement.classList.add("zet-x-autoscroll");
    marker = document.createElement("div");
    marker.id = "zet-x-autoscroll-mark";
    marker.style.left = `${event.clientX}px`;
    marker.style.top = `${event.clientY}px`;
    document.documentElement.appendChild(marker);
    raf = requestAnimationFrame(tick);
  }

  function onMove(event) {
    if (!active) return;
    const delta = event.clientY - originY;
    const dead = 14;
    if (Math.abs(delta) <= dead) {
      velocity = 0;
      return;
    }
    velocity = Math.max(-48, Math.min(48, (delta - Math.sign(delta) * dead) * 0.12));
  }

  function onMouseDown(event) {
    if (!isHdmiX()) return;
    if (event.button !== 1) {
      if (active) {
        event.preventDefault();
        stop();
      }
      return;
    }
    const link = event.target && event.target.closest && event.target.closest("a[href]");
    const href = link ? String(link.getAttribute("href") || "") : "";
    if (href && href !== "#" && !href.startsWith("javascript:")) return;
    event.preventDefault();
    if (active) stop();
    else start(event);
  }

  function onAuxClick(event) {
    if (!isHdmiX() || event.button !== 1) return;
    if (active) event.preventDefault();
  }

  document.addEventListener("mousedown", onMouseDown, true);
  document.addEventListener("mousemove", onMove, true);
  document.addEventListener("auxclick", onAuxClick, true);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && active) stop();
  }, true);

  const boot = () => {
    if (isHdmiX()) injectCss();
  };
  boot();
  window.addEventListener("resize", boot);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  }
})();
