# Ratings API

A Cloudflare Worker over D1 that collects the 1–5 star ratings from every
install of Daily Zen Wallpaper and hands the averages back. `worker.js` is the
whole service; `schema.sql` the two tables.

Deploy: `.github/workflows/deploy-api.yml` runs on every push that touches
`api/`, once the repository has the secrets `CLOUDFLARE_API_TOKEN` (Workers
Scripts + D1 edit) and `CLOUDFLARE_ACCOUNT_ID`. It creates the D1 database on
first run, applies `schema.sql`, fills the database id into `wrangler.jsonc`
for the deploy, and prints the worker URL. Put that URL into `catalog.json` as
`ratings_api` and every install starts sharing ratings within a day.

By hand: `cd api && npx wrangler d1 create omarchy-fans-zen-ratings`, paste the
id, `npx wrangler d1 execute omarchy-fans-zen-ratings --remote --file schema.sql`,
`npx wrangler deploy`.

Local: `npx wrangler dev --local` (an emulated D1; `tests/run.sh api` uses it
when it is running on 127.0.0.1:8787, `OMARCHY_DAILY_ZEN_RATINGS_API` points the
CLI at any instance).
