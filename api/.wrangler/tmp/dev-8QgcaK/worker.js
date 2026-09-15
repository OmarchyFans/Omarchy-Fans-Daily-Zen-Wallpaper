var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// worker.js
var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
var VIDEO = /^[A-Za-z0-9_-]{11}$/;
var LIMIT = 60;
var json = /* @__PURE__ */ __name((body, status = 200, extra = {}) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra } }), "json");
async function allowed(env, ip) {
  const win = Math.floor(Date.now() / 6e4);
  const row = await env.DB.prepare("SELECT win, n FROM budget WHERE ip = ?").bind(ip).first();
  if (!row || row.win !== win) {
    await env.DB.prepare("INSERT INTO budget (ip, win, n) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET win = excluded.win, n = 1").bind(ip, win).run();
    return true;
  }
  if (row.n >= LIMIT) return false;
  await env.DB.prepare("UPDATE budget SET n = n + 1 WHERE ip = ?").bind(ip).run();
  return true;
}
__name(allowed, "allowed");
async function aggregate(env, videoId) {
  const row = await env.DB.prepare("SELECT AVG(stars) AS avg, COUNT(*) AS count FROM ratings WHERE video_id = ?").bind(videoId).first();
  return { video_id: videoId, avg: row && row.count ? Math.round(row.avg * 100) / 100 : 0, count: row ? row.count : 0 };
}
__name(aggregate, "aggregate");
var worker_default = {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/health") return json({ ok: true });
    if (request.method === "GET" && (url.pathname === "/v1/ratings" || url.pathname === "/v1/stats")) {
      const rated = await env.DB.prepare("SELECT video_id, AVG(stars) AS avg, COUNT(*) AS count FROM ratings GROUP BY video_id").all();
      const played = await env.DB.prepare("SELECT video_id, COUNT(*) AS plays FROM plays GROUP BY video_id").all();
      const out = {};
      for (const r of rated.results || []) out[r.video_id] = { avg: Math.round(r.avg * 100) / 100, count: r.count, plays: 0 };
      for (const p of played.results || []) {
        if (!out[p.video_id]) out[p.video_id] = { avg: 0, count: 0, plays: 0 };
        out[p.video_id].plays = p.plays;
      }
      return json(out, 200, { "cache-control": "public, max-age=60" });
    }
    if (request.method === "POST" && url.pathname === "/v1/play") {
      const len = Number(request.headers.get("content-length") || 0);
      if (len > 512) return json({ error: "body too large" }, 413);
      let body;
      try {
        body = await request.json();
      } catch (e) {
        return json({ error: "bad json" }, 400);
      }
      const installId = String(body.install_id || ""), videoId = String(body.video_id || "");
      if (!UUID.test(installId)) return json({ error: "bad install_id" }, 400);
      if (!VIDEO.test(videoId)) return json({ error: "bad video_id" }, 400);
      const ip = request.headers.get("cf-connecting-ip") || "local";
      if (!await allowed(env, ip)) return json({ error: "slow down" }, 429, { "retry-after": "60" });
      const day = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
      await env.DB.prepare("INSERT OR IGNORE INTO plays (install_id, video_id, day) VALUES (?, ?, ?)").bind(installId, videoId, day).run();
      const row = await env.DB.prepare("SELECT COUNT(*) AS plays FROM plays WHERE video_id = ?").bind(videoId).first();
      return json({ video_id: videoId, plays: row ? row.plays : 0 });
    }
    if (request.method === "POST" && url.pathname === "/v1/rate") {
      const len = Number(request.headers.get("content-length") || 0);
      if (len > 512) return json({ error: "body too large" }, 413);
      let body;
      try {
        body = await request.json();
      } catch (e) {
        return json({ error: "bad json" }, 400);
      }
      const installId = String(body.install_id || ""), videoId = String(body.video_id || ""), stars = Number(body.stars);
      if (!UUID.test(installId)) return json({ error: "bad install_id" }, 400);
      if (!VIDEO.test(videoId)) return json({ error: "bad video_id" }, 400);
      if (!Number.isInteger(stars) || stars < 1 || stars > 5) return json({ error: "stars must be 1..5" }, 400);
      const ip = request.headers.get("cf-connecting-ip") || "local";
      if (!await allowed(env, ip)) return json({ error: "slow down" }, 429, { "retry-after": "60" });
      await env.DB.prepare(
        "INSERT INTO ratings (install_id, video_id, stars, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(install_id, video_id) DO UPDATE SET stars = excluded.stars, updated_at = excluded.updated_at"
      ).bind(installId, videoId, stars, Math.floor(Date.now() / 1e3)).run();
      return json(await aggregate(env, videoId));
    }
    if (request.method === "DELETE" && url.pathname === "/v1/rate") {
      let body;
      try {
        body = await request.json();
      } catch (e) {
        return json({ error: "bad json" }, 400);
      }
      const installId = String(body.install_id || ""), videoId = String(body.video_id || "");
      if (!UUID.test(installId) || !VIDEO.test(videoId)) return json({ error: "bad ids" }, 400);
      await env.DB.prepare("DELETE FROM ratings WHERE install_id = ? AND video_id = ?").bind(installId, videoId).run();
      return json(await aggregate(env, videoId));
    }
    return json({ error: "not found" }, 404);
  }
};

// ../../../.npm/_npx/c943b712072b77c4/node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// ../../../.npm/_npx/c943b712072b77c4/node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    const body = JSON.stringify(error);
    const headers = {
      "Content-Type": "application/json",
      "MF-Experimental-Error-Stack": "true"
    };
    const encoded = encodeURIComponent(body);
    if (encoded.length <= 8192) {
      headers["MF-Experimental-Error-Stack-Payload"] = encoded;
    }
    return new Response(body, { status: 500, headers });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-tklrQl/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = worker_default;

// ../../../.npm/_npx/c943b712072b77c4/node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-tklrQl/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  scheduledTime;
  cron;
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=worker.js.map
