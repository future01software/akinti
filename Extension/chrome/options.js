import { DEFAULTS } from "./lib/core.js";

const t = (key, subs) => chrome.i18n.getMessage(key, subs) || key;
const $ = id => document.getElementById(id);
for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = t(el.dataset.i18n);

chrome.runtime.sendMessage({ cmd: "ping" }, reply => {
  const ok = reply && reply.ok;
  $("status").classList.toggle("ok", !!ok);
  $("status").classList.toggle("bad", !ok);
  $("statusText").textContent = ok ? t("popupConnected", [reply.version || ""]) : t("popupNotConnected");
});

const fields = { capture: "checked", extensions: "value", minSizeMB: "value", excludedSites: "value", notify: "checked" };

async function load() {
  const values = await chrome.storage.sync.get(DEFAULTS);
  for (const [key, prop] of Object.entries(fields)) $(key)[prop] = values[key];
}

let timer;
function save() {
  clearTimeout(timer);
  timer = setTimeout(async () => {
    const values = {};
    for (const [key, prop] of Object.entries(fields)) values[key] = $(key)[prop];
    values.minSizeMB = Math.max(0, Number(values.minSizeMB) || 0);
    await chrome.storage.sync.set(values);
    $("saved").hidden = false; setTimeout(() => ($("saved").hidden = true), 1500);
  }, 300);
}

for (const key of Object.keys(fields)) { $(key).addEventListener("input", save); $(key).addEventListener("change", save); }
$("reset").addEventListener("click", async () => { await chrome.storage.sync.set({ ...DEFAULTS }); await load(); save(); });
load();
