// Daily Zen Wallpaper ratings API: a Cloudflare Worker over D1.
//
//   GET  /v1/health            {ok: true}
//   GET  /v1/ratings           {"<video_id>": {avg, count}, ...}   (every rated video; cached 60 s)
//   POST /v1/rate              {install_id, video_id, stars}  ->  {video_id, avg, count}
//
// The install id is a random uuid the plugin makes on first use; there is no
// account, no name, no IP stored (the IP is only counted for 60 seconds to cap
// writes at 60 a minute). See ../README.md "What leaves your machine".
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const VIDEO = /^[A-Za-z0-9_-]{11}$/;
const LIMIT = 60;

const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra } });

async function allowed(env, ip) {
  const win = Math.floor(Date.now() / 60000);
  const row = await env.DB.prepare("SELECT win, n FROM budget WHERE ip = ?").bind(ip).first();
  if (!row || row.win !== win) {
    await env.DB.prepare("INSERT INTO budget (ip, win, n) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET win = excluded.win, n = 1").bind(ip, win).run();
    return true;
  }
  if (row.n >= LIMIT) return false;
  await env.DB.prepare("UPDATE budget SET n = n + 1 WHERE ip = ?").bind(ip).run();
  return true;
}

async function aggregate(env, videoId) {
  const row = await env.DB.prepare("SELECT AVG(stars) AS avg, COUNT(*) AS count FROM ratings WHERE video_id = ?").bind(videoId).first();
  return { video_id: videoId, avg: row && row.count ? Math.round(row.avg * 100) / 100 : 0, count: row ? row.count : 0 };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/health") return json({ ok: true });
    if (request.method === "GET" && url.pathname === "/v1/ratings") {
      const { results } = await env.DB.prepare("SELECT video_id, AVG(stars) AS avg, COUNT(*) AS count FROM ratings GROUP BY video_id").all();
      const out = {};
      for (const r of results || []) out[r.video_id] = { avg: Math.round(r.avg * 100) / 100, count: r.count };
      return json(out, 200, { "cache-control": "public, max-age=60" });
    }
    if (request.method === "POST" && url.pathname === "/v1/rate") {
      const len = Number(request.headers.get("content-length") || 0);
      if (len > 512) return json({ error: "body too large" }, 413);
      let body;
      try { body = await request.json(); } catch (e) { return json({ error: "bad json" }, 400); }
      const installId = String(body.install_id || ""), videoId = String(body.video_id || ""), stars = Number(body.stars);
      if (!UUID.test(installId)) return json({ error: "bad install_id" }, 400);
      if (!VIDEO.test(videoId)) return json({ error: "bad video_id" }, 400);
      if (!Number.isInteger(stars) || stars < 1 || stars > 5) return json({ error: "stars must be 1..5" }, 400);
      const ip = request.headers.get("cf-connecting-ip") || "local";
      if (!(await allowed(env, ip))) return json({ error: "slow down" }, 429, { "retry-after": "60" });
      await env.DB.prepare(
        "INSERT INTO ratings (install_id, video_id, stars, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(install_id, video_id) DO UPDATE SET stars = excluded.stars, updated_at = excluded.updated_at"
      ).bind(installId, videoId, stars, Math.floor(Date.now() / 1000)).run();
      return json(await aggregate(env, videoId));
    }
    if (request.method === "DELETE" && url.pathname === "/v1/rate") {
      let body;
      try { body = await request.json(); } catch (e) { return json({ error: "bad json" }, 400); }
      const installId = String(body.install_id || ""), videoId = String(body.video_id || "");
      if (!UUID.test(installId) || !VIDEO.test(videoId)) return json({ error: "bad ids" }, 400);
      await env.DB.prepare("DELETE FROM ratings WHERE install_id = ? AND video_id = ?").bind(installId, videoId).run();
      return json(await aggregate(env, videoId));
    }
    return json({ error: "not found" }, 404);
  },
};
