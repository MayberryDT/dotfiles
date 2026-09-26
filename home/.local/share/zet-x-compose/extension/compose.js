(() => {
  const promoteDialog = () => {
    const dialog =
      document.querySelector('div[role="dialog"]') ||
      document.querySelector('div[aria-modal="true"]');
    if (!dialog) return;
    dialog.style.visibility = "visible";
    dialog.style.pointerEvents = "auto";
    const box = document.querySelector('[data-testid="tweetTextarea_0"]');
    if (box && document.activeElement !== box) {
      try {
        box.focus();
      } catch (_) {
        /* ignore */
      }
    }
  };

  const start = () => {
    promoteDialog();
    const obs = new MutationObserver(promoteDialog);
    obs.observe(document.documentElement, { childList: true, subtree: true });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
