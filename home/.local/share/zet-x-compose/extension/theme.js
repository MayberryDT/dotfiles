(() => {
  const id = "zet-omarchy-x-theme";
  let last = "";

  function markStockControls() {
    const blue = new Set(["rgb(29, 155, 240)", "rgb(29, 161, 242)"]);
    for (const item of document.querySelectorAll("a, button, [role='button'], [data-testid='icon-verified']")) {
      if (blue.has(getComputedStyle(item).color)) item.dataset.zetXLink = "";

      // X renders the Grok and chat launchers outside the themed columns.
      const rect = item.getBoundingClientRect();
      if (rect.right < innerWidth - 100 || rect.bottom < innerHeight - 200 ||
          rect.width < 36 || rect.width > 90 || rect.height < 36 || rect.height > 90) continue;
      for (const node of [item, item.parentElement]) {
        if (!node) continue;
        const box = node.getBoundingClientRect();
        if (box.width <= 96 && box.height <= 96) node.dataset.zetXFloating = "";
      }
    }
  }

  async function refresh() {
    try {
      const url = chrome.runtime.getURL("palette.css") + "?t=" + Date.now();
      const response = await fetch(url, { cache: "no-store" });
      if (!response.ok) return;
      const css = await response.text();
      if (!css) return;
      if (css === last) {
        markStockControls();
        return;
      }
      last = css;
      let style = document.getElementById(id);
      if (!style) {
        style = document.createElement("style");
        style.id = id;
        (document.head || document.documentElement).appendChild(style);
      }
      style.textContent = css;
      markStockControls();
    } catch (_) {
      // Keep the last working palette if the extension is being reloaded.
    }
  }

  refresh();
  setInterval(refresh, 4000);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) refresh();
  });
})();
