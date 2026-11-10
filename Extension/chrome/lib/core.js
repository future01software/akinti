// Akıntı eklentisinin karar veren saf fonksiyonları (tarayıcıdan bağımsız; Node ile test edilir).

export const HOST = "com.akinti.bridge";

export const DEFAULTS = Object.freeze({
  capture: true,
  extensions: "zip rar 7z tar gz tgz bz2 xz zst iso dmg pkg exe msi deb rpm appimage apk " +
    "mp4 mkv avi mov webm m4v mp3 flac wav m4a aac ogg pdf epub torrent",
  minSizeMB: 1,
  excludedSites: "",
  notify: true,
});

/** Akıntı uygulamasındaki listeyle aynı: bu sitelerdeki sayfalar video sayfası olarak gönderilir. */
export const VIDEO_HOSTS = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv", "x.com", "twitter.com",
  "instagram.com", "tiktok.com", "facebook.com", "fb.watch", "reddit.com", "soundcloud.com", "bilibili.com",
  "streamable.com", "rumble.com", "ted.com", "bandcamp.com", "mixcloud.com"];

const MIME_EXTENSIONS = {
  "application/zip": "zip", "application/x-zip-compressed": "zip", "application/x-7z-compressed": "7z",
  "application/vnd.rar": "rar", "application/x-rar-compressed": "rar", "application/gzip": "gz",
  "application/x-apple-diskimage": "dmg", "application/x-iso9660-image": "iso", "application/pdf": "pdf",
  "application/x-bittorrent": "torrent", "application/vnd.android.package-archive": "apk",
  "video/mp4": "mp4", "video/webm": "webm", "video/x-matroska": "mkv", "video/quicktime": "mov",
  "audio/mpeg": "mp3", "audio/flac": "flac", "audio/wav": "wav", "audio/mp4": "m4a",
};

export function parseList(text) {
  return String(text || "").toLowerCase().split(/[\s,;]+/).map(s => s.replace(/^\./, "").trim()).filter(Boolean);
}

export function isWebURL(url) {
  try { const u = new URL(url); return u.protocol === "http:" || u.protocol === "https:"; } catch { return false; }
}

export function isMagnet(url) { return /^magnet:\?/i.test(String(url || "")); }

export function hostOf(url) {
  try { return new URL(url).hostname.toLowerCase().replace(/^www\./, ""); } catch { return ""; }
}

function matchesHost(host, pattern) {
  pattern = pattern.replace(/^\*\./, "").replace(/^www\./, "");
  return host === pattern || host.endsWith("." + pattern);
}

export function isVideoPage(url) {
  const host = hostOf(url);
  return isWebURL(url) && VIDEO_HOSTS.some(h => matchesHost(host, h));
}

export function isExcluded(url, excludedSites) {
  const host = hostOf(url);
  return host !== "" && parseList(excludedSites).some(p => matchesHost(host, p));
}

/** Dosya adından, URL yolundan ya da MIME türünden uzantı. */
export function extensionOf(item) {
  const fromName = n => { const m = /\.([a-z0-9]{1,10})$/i.exec(String(n || "").split(/[?#]/)[0]); return m ? m[1].toLowerCase() : ""; };
  let ext = fromName(item.filename);
  if (!ext) { try { ext = fromName(decodeURIComponent(new URL(item.finalUrl || item.url).pathname)); } catch { /* geçersiz URL */ } }
  if (!ext && item.mime) ext = MIME_EXTENSIONS[String(item.mime).split(";")[0].trim().toLowerCase()] || "";
  return ext;
}

/**
 * Chrome'un başlattığı bir indirme Akıntı'ya devredilsin mi?
 * item: chrome.downloads.DownloadItem; bypass: Akıntı'ya ulaşılamayınca Chrome'a geri verilen adresler.
 */
export function shouldCapture(item, settings, bypass = new Set()) {
  const s = { ...DEFAULTS, ...settings };
  const url = item.finalUrl || item.url;
  if (!s.capture || !isWebURL(url) || item.byExtensionId || bypass.has(url) || bypass.has(item.url)) return false;
  if (item.state && item.state !== "in_progress") return false;
  if (isExcluded(url, s.excludedSites) || (item.referrer && isExcluded(item.referrer, s.excludedSites))) return false;
  if (!parseList(s.extensions).includes(extensionOf(item))) return false;
  const size = Math.max(item.totalBytes || 0, item.fileSize || 0);
  if (size > 0 && size < s.minSizeMB * 1024 * 1024) return false;
  return true;
}

/** Bir metindeki http(s) ve magnet bağlantıları. */
export function linksIn(text) {
  const found = String(text || "").match(/\b(?:https?:\/\/|magnet:\?)[^\s<>"']+/gi) || [];
  return [...new Set(found.map(s => s.replace(/[),.;]+$/, "")))].filter(u => isWebURL(u) || isMagnet(u));
}

/** Sağ tık menüsünden gelen bilgiye göre Akıntı'ya gönderilecek mesaj (gönderilecek bir şey yoksa null). */
export function messageForContext(info, tab, userAgent) {
  const page = info.pageUrl || (tab && tab.url) || "";
  let urls = [], mode;
  if (info.linkUrl && (isWebURL(info.linkUrl) || isMagnet(info.linkUrl))) {
    urls = [info.linkUrl];
    if (isVideoPage(info.linkUrl)) mode = "video";
  } else if ((info.mediaType === "video" || info.mediaType === "audio") ) {
    // YouTube gibi sitelerde video kaynağı "blob:" olur; o zaman sayfanın kendisi gönderilir.
    if (isWebURL(info.srcUrl) && !isVideoPage(page)) urls = [info.srcUrl];
    else if (isWebURL(page)) { urls = [page]; mode = "video"; }
  } else if (info.selectionText) {
    urls = linksIn(info.selectionText);
  } else if (isWebURL(page)) {
    urls = [page];
    if (isVideoPage(page)) mode = "video";
  }
  if (!urls.length) return null;
  return addMessage(urls, isWebURL(page) ? page : undefined, userAgent, mode);
}

export function addMessage(urls, referrer, userAgent, mode) {
  const msg = { type: "add", urls };
  if (referrer) msg.referrer = referrer;
  if (userAgent) msg.userAgent = userAgent;
  if (mode) msg.mode = mode;
  return msg;
}
