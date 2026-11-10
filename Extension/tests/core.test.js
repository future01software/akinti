import { test } from "node:test";
import assert from "node:assert/strict";
import { shouldCapture, extensionOf, messageForContext, linksIn, isExcluded, isVideoPage, parseList, DEFAULTS } from "../chrome/lib/core.js";

const item = (o) => ({ id: 1, url: "https://cdn.example.org/files/ubuntu.iso", finalUrl: "", filename: "", mime: "", totalBytes: 0,
  fileSize: 0, state: "in_progress", referrer: "https://example.org/indir", ...o });

test("uzantı: dosya adı, URL yolu ve MIME", () => {
  assert.equal(extensionOf(item({ filename: "/Users/x/Downloads/Kurulum.DMG" })), "dmg");
  assert.equal(extensionOf(item({})), "iso");
  assert.equal(extensionOf(item({ url: "https://x.org/get?id=5", mime: "application/zip" })), "zip");
  assert.equal(extensionOf(item({ url: "https://x.org/a%20b.tar.gz?token=1" })), "gz");
});

test("listedeki türler yakalanır, küçük ve listede olmayanlar yakalanmaz", () => {
  assert.equal(shouldCapture(item({}), DEFAULTS), true);
  assert.equal(shouldCapture(item({ url: "https://x.org/belge.docx" }), DEFAULTS), false);
  assert.equal(shouldCapture(item({ totalBytes: 200 * 1024 }), DEFAULTS), false); // 1 MB altı
  assert.equal(shouldCapture(item({ totalBytes: 5 * 1024 * 1024 }), DEFAULTS), true);
  assert.equal(shouldCapture(item({}), { ...DEFAULTS, minSizeMB: 0, extensions: "pdf" }), false);
});

test("yakalanmaması gerekenler", () => {
  assert.equal(shouldCapture(item({}), { ...DEFAULTS, capture: false }), false);
  assert.equal(shouldCapture(item({ url: "blob:https://x.org/abc" }), DEFAULTS), false);
  assert.equal(shouldCapture(item({ url: "data:application/zip;base64,AA" }), DEFAULTS), false);
  assert.equal(shouldCapture(item({ byExtensionId: "abc" }), DEFAULTS), false);
  assert.equal(shouldCapture(item({ state: "complete" }), DEFAULTS), false);
  const bypass = new Set(["https://cdn.example.org/files/ubuntu.iso"]);
  assert.equal(shouldCapture(item({}), DEFAULTS, bypass), false); // Akıntı'ya ulaşılamadı, Chrome'a geri verildi
});

test("hariç tutulan siteler (indirme adresi veya başlatan sayfa)", () => {
  const s = { ...DEFAULTS, excludedSites: "mail.google.com\n*.example.org" };
  assert.equal(shouldCapture(item({}), s), false);
  assert.equal(shouldCapture(item({ url: "https://other.net/a.zip", referrer: "https://mail.google.com/x" }), s), false);
  assert.equal(shouldCapture(item({ url: "https://other.net/a.zip", referrer: "" }), s), true);
  assert.equal(isExcluded("https://www.example.org/x", "example.org"), true);
  assert.equal(isExcluded("https://notexample.org/x", "example.org"), false);
});

test("sağ tık menüsü mesajları", () => {
  const ua = "Mozilla/5.0 Test";
  assert.deepEqual(messageForContext({ linkUrl: "https://x.org/a.zip", pageUrl: "https://x.org/" }, null, ua),
    { type: "add", urls: ["https://x.org/a.zip"], referrer: "https://x.org/", userAgent: ua });
  // YouTube videosu: kaynak blob: olur, sayfa video olarak gönderilir
  assert.deepEqual(messageForContext({ mediaType: "video", srcUrl: "blob:https://www.youtube.com/1", pageUrl: "https://www.youtube.com/watch?v=abc" }, null, ua),
    { type: "add", urls: ["https://www.youtube.com/watch?v=abc"], referrer: "https://www.youtube.com/watch?v=abc", userAgent: ua, mode: "video" });
  // Doğrudan video dosyası
  assert.deepEqual(messageForContext({ mediaType: "video", srcUrl: "https://cdn.x.org/v.mp4", pageUrl: "https://x.org/p" }, null, ua).urls, ["https://cdn.x.org/v.mp4"]);
  // Seçili metindeki bağlantılar (magnet dahil)
  const sel = messageForContext({ selectionText: "şuna bak https://a.org/1.zip, ve magnet:?xt=urn:btih:abc&dn=x ok", pageUrl: "https://a.org" }, null, ua);
  assert.deepEqual(sel.urls, ["https://a.org/1.zip", "magnet:?xt=urn:btih:abc&dn=x"]);
  // Sayfa: video sitesiyse video kipi
  assert.equal(messageForContext({ pageUrl: "https://vimeo.com/123" }, null, ua).mode, "video");
  assert.equal(messageForContext({ pageUrl: "https://example.org/" }, null, ua).mode, undefined);
  // Gönderilecek bir şey yok
  assert.equal(messageForContext({ pageUrl: "chrome://settings" }, null, ua), null);
  assert.equal(messageForContext({ linkUrl: "javascript:alert(1)", pageUrl: "chrome://x" }, null, ua), null);
});

test("yardımcılar", () => {
  assert.deepEqual(parseList(".ZIP, dmg;  .iso\nmp4"), ["zip", "dmg", "iso", "mp4"]);
  assert.equal(isVideoPage("https://m.youtube.com/watch?v=1"), true);
  assert.equal(isVideoPage("https://notyoutube.com/"), false);
  assert.deepEqual(linksIn("yok"), []);
});
