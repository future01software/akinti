// Akıntı eklentisinin arka plan hizmeti (Manifest V3 service worker).
import { HOST, DEFAULTS, shouldCapture, messageForContext, addMessage, isWebURL, isVideoPage } from "./lib/core.js";

const t = (key, subs) => chrome.i18n.getMessage(key, subs) || key;
/** Akıntı'ya ulaşılamayınca Chrome'a geri verilen indirmeler (tekrar yakalanmasın). */
const bypass = new Set();

async function settings() {
  return { ...DEFAULTS, ...(await chrome.storage.sync.get(Object.keys(DEFAULTS))) };
}

/** Köprü üzerinden Akıntı'ya mesaj gönderir. Akıntı kurulu değilse { ok:false, error:"not-installed" }. */
export async function sendToAkinti(message) {
  try {
    const reply = await chrome.runtime.sendNativeMessage(HOST, message);
    return reply || { ok: false, error: "no-reply" };
  } catch (e) {
    return { ok: false, error: /not found|not installed|Specified native messaging host/i.test(String(e && e.message)) ? "not-installed" : String(e && e.message) };
  }
}

async function notify(titleKey, messageKey, subs) {
  if (!(await settings()).notify) return;
  chrome.notifications.create({ type: "basic", iconUrl: "icons/icon-128.png", title: t(titleKey), message: t(messageKey, subs), priority: 0 });
}

async function flashBadge(ok) {
  await chrome.action.setBadgeBackgroundColor({ color: ok ? "#1f6feb" : "#d1242f" });
  await chrome.action.setBadgeText({ text: ok ? "↓" : "!" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}

async function deliver(message) {
  const reply = await sendToAkinti(message);
  await flashBadge(reply.ok);
  if (!reply.ok) await notify("notInstalledTitle", reply.error === "not-installed" ? "notInstalledBody" : "sendFailedBody", [reply.error || ""]);
  return reply;
}

// --- Sağ tık menüsü
function createMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "akinti-link", title: t("menuLink"), contexts: ["link"] });
    chrome.contextMenus.create({ id: "akinti-media", title: t("menuMedia"), contexts: ["video", "audio"] });
    chrome.contextMenus.create({ id: "akinti-selection", title: t("menuSelection"), contexts: ["selection"] });
    chrome.contextMenus.create({ id: "akinti-page", title: t("menuPage"), contexts: ["page"] });
  });
}
chrome.runtime.onInstalled.addListener(createMenus);
chrome.runtime.onStartup.addListener(createMenus);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const message = messageForContext(info, tab, navigator.userAgent);
  if (message) await deliver(message);
});

// --- Chrome indirmelerini yakalama (IDM gibi)
chrome.downloads.onCreated.addListener(async (item) => {
  const s = await settings();
  if (!shouldCapture(item, s, bypass)) return;
  const url = item.finalUrl || item.url;
  try { await chrome.downloads.cancel(item.id); await chrome.downloads.erase({ id: item.id }); } catch { return; }
  const reply = await deliver(addMessage([url], item.referrer || undefined, navigator.userAgent));
  if (!reply.ok) {
    // Akıntı'ya ulaşılamadı: indirmeyi Chrome'a geri ver.
    bypass.add(url); bypass.add(item.url);
    chrome.downloads.download({ url });
  }
});

// --- Açılır panel ve ayarlar sayfasıyla iletişim
chrome.runtime.onMessage.addListener((request, _sender, respond) => {
  (async () => {
    switch (request && request.cmd) {
      case "ping": respond(await sendToAkinti({ type: "ping" })); break;
      case "sendPage": {
        const url = request.url;
        if (!isWebURL(url)) { respond({ ok: false, error: "not-web" }); break; }
        respond(await deliver(addMessage([url], undefined, navigator.userAgent, isVideoPage(url) ? "video" : undefined)));
        break;
      }
      default: respond({ ok: false, error: "unknown" });
    }
  })();
  return true; // yanıt eşzamansız
});
