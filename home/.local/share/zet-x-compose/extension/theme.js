(() => {
  const id = "zet-omarchy-x-theme";
  const stockId = `${id}-stock`;
  let last = "";
  const blue = new Set(["29,155,240", "29,161,242", "0,153,255"]);
  const backgrounds = new Map([
    ["255,255,255", "bg"], ["0,0,0", "bg"], ["21,32,43", "bg"],
    ["247,249,249", "surface"], ["239,243,244", "surface"],
    ["32,35,39", "surface"], ["22,24,28", "surface"],
    ["230,236,240", "hover"], ["239,239,239", "hover"], ["26,26,26", "hover"],
  ]);
  const text = new Map([
    ["15,20,25", "fg"], ["231,233,234", "fg"], ["217,217,217", "fg"],
    ["83,100,113", "muted"], ["113,118,123", "muted"], ["139,152,165", "muted"],
  ]);
  const borders = new Set(["239,243,244", "207,217,222", "47,51,54", "56,68,77"]);

  function mapped(property, value) {
    const match = value.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/);
    if (!match) return null;
    const rgb = match.slice(1, 4).join(",");
    const alpha = match[4] === undefined ? 1 : Number(match[4]);
    if (!alpha) return null;
    let token;
    if (rgb === "249,24,128" || rgb === "224,36,94") token = "like";
    else if (blue.has(rgb)) token = property === "background-color" ? "accent" : "link";
    else if (property === "background-color") token = backgrounds.get(rgb);
    else if (property === "color") token = text.get(rgb);
    else if (property.startsWith("border-") && borders.has(rgb)) token = "border";
    if (!token) return null;
    const color = `var(--zet-x-${token})`;
    return alpha === 1 ? color : `color-mix(in srgb, ${color} ${alpha * 100}%, transparent)`;
  }

  // Read X's actual atomic CSS rules, including hover/media rules. Translate only
  // known palette colors: no geometry guesses, descendant painting or media filters.
  function translate(rules) {
    let result = "";
    for (const rule of rules) {
      if (rule.type === CSSRule.STYLE_RULE) {
        const declarations = [];
        for (const property of ["color", "background-color", "border-top-color", "border-right-color", "border-bottom-color", "border-left-color", "fill", "stroke"]) {
          const value = mapped(property, rule.style.getPropertyValue(property));
          if (value) declarations.push(`${property}:${value} !important;`);
        }
        if (declarations.length) {
          result += `${rule.selectorText}{${declarations.join("")}}\n`;
        }
      } else if (rule.cssRules && (rule.type === CSSRule.MEDIA_RULE || rule.type === CSSRule.SUPPORTS_RULE)) {
        result += `${rule.cssText.slice(0, rule.cssText.indexOf("{"))}{${translate(rule.cssRules)}}\n`;
      }
    }
    return result;
  }

  function refreshStockRules(style) {
    let css = "";
    for (const sheet of document.styleSheets) {
      if (sheet.ownerNode?.id?.startsWith(id) || sheet.disabled) continue;
      try {
        const translated = translate(sheet.cssRules);
        css += sheet.media.mediaText ? `@media ${sheet.media.mediaText}{${translated}}` : translated;
      } catch (_) { /* Cross-origin sheets cannot be read; inline/fallback CSS remains. */ }
    }
    let stock = document.getElementById(stockId);
    if (!stock) {
      stock = document.createElement("style");
      stock.id = stockId;
      style.before(stock);
    }
    if (stock.textContent !== css) stock.textContent = css;
  }

  async function refresh() {
    try {
      const response = await fetch(chrome.runtime.getURL("palette.css") + "?t=" + Date.now(), { cache: "no-store" });
      if (!response.ok) return;
      const css = await response.text();
      if (!css) return;
      let style = document.getElementById(id);
      if (!style) {
        style = document.createElement("style");
        style.id = id;
        (document.head || document.documentElement).appendChild(style);
      }
      if (css !== last) { style.textContent = css; last = css; }
      refreshStockRules(style);
    } catch (_) { /* Preserve the last palette during extension reload. */ }
  }

  refresh();
  setInterval(refresh, 4000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
})();
