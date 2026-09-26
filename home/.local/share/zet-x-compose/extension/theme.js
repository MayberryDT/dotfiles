(() => {
  const id = "zet-omarchy-x-theme";
  let last = "";

  async function refresh() {
    try {
      const url = chrome.runtime.getURL("palette.css") + "?t=" + Date.now();
      const response = await fetch(url, { cache: "no-store" });
      if (!response.ok) return;
      const css = await response.text();
      if (!css || css === last) return;
      last = css;
      let style = document.getElementById(id);
      if (!style) {
        style = document.createElement("style");
        style.id = id;
        (document.head || document.documentElement).appendChild(style);
      }
      style.textContent = css;
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
