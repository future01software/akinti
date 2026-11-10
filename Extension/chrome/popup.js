import { DEFAULTS, isWebURL, isVideoPage, hostOf } from "./lib/core.js";

const t = (key, subs) => chrome.i18n.getMessage(key, subs) || key;
const $ = id => document.getElementById(id);

for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = t(el.dataset.i18n);
$("version").textContent = "v" + chrome.runtime.getManifest().version;

// Bağlantı durumu
chrome.runtime.sendMessage({ cmd: "ping" }, reply => {
  const ok = reply && reply.ok;
  $("status").classList.toggle("ok", !!ok);
  $("status").classList.toggle("bad", !ok);
  $("statusText").textContent = ok ? t("popupConnected", [reply.version || ""]) : t("popupNotConnected");
  $("missing").hidden = !!ok;
});

// Bu sayfa / video
const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
const url = tab && tab.url;
if (isWebURL(url)) {
  $("send").disabled = false;
  $("sendLabel").textContent = t(isVideoPage(url) ? "popupSendVideo" : "popupSendPage");
  $("pageHost").textContent = hostOf(url);
}
$("send").addEventListener("click", () => {
  $("send").disabled = true;
  chrome.runtime.sendMessage({ cmd: "sendPage", url }, reply => {
    $("sendLabel").textContent = reply && reply.ok ? t("popupSent") : t("popupSendFailed");
    if (reply && reply.ok) setTimeout(() => window.close(), 900); else $("send").disabled = false;
  });
});

// İndirmeleri yakala anahtarı
const { capture } = await chrome.storage.sync.get({ capture: DEFAULTS.capture });
$("capture").checked = capture;
$("capture").addEventListener("change", e => chrome.storage.sync.set({ capture: e.target.checked }));

$("options").addEventListener("click", e => { e.preventDefault(); chrome.runtime.openOptionsPage(); });
