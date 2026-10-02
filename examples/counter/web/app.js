// Minimal bridge client. Talks to Zig via window.webkit.messageHandlers.zview.
(async function () {
  const $ = (id) => document.getElementById(id);
  const log = (msg) => { $('log').textContent = msg; };
  const setCount = (v) => { $('count').textContent = String(v); };
  const setMethod = (m) => { $('method').textContent = m; };
  const setRss = (kb) => { $('rss').textContent = `RSS ${kb} kB`; };

  const call = window.__zview.call;
  const safe = async (label, method, args = []) => {
    setMethod(`→ ${method}`);
    try {
      const v = await call(method, args);
      setMethod(`← ${method}`);
      return v;
    } catch (e) {
      setMethod(`× ${method}: ${e}`);
      throw e;
    }
  };

  $('inc').onclick = async () => {
    const v = await safe('increment', 'increment');
    setCount(v);
  };
  $('dec').onclick = async () => {
    const v = await safe('decrement', 'decrement');
    setCount(v);
  };
  $('reset').onclick = async () => {
    const v = await safe('reset', 'reset');
    setCount(v);
  };
  $('ping').onclick = async () => {
    const v = await safe('version', 'version');
    log(`zview ${v} · zig 0.15.2 · WKWebView · JSON bridge`);
  };

  // Initial pull + RSS ticker
  setCount(await safe('get', 'get'));
  setRss(await safe('rss_kb', 'rss_kb'));
  setInterval(async () => {
    try { setRss(await safe('rss_kb', 'rss_kb')); } catch (_) {}
  }, 1000);
})();
