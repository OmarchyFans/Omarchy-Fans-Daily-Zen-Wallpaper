#!/bin/bash
# Builds catalog.json: the ten most popular long streams per category, from
# yt-dlp searches. Run it now and then and commit the result; installs fetch
# catalog.json from the main branch once a day.
#
#   tools/build-catalog.sh [OUT]      default: catalog.json next to this repo
#
# Ranking: per category, several searches are merged and deduplicated; entries
# shorter than an hour are dropped unless live; live streams rank by current
# viewers, videos by total views; the list is the top 5 live + top 5 videos
# (the "streams" category is 10 live), at most 3 per channel so one creator
# cannot fill a list. Search noise is possible: read the result before committing.
set -euo pipefail
export PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/catalog.json}"
N="${YTSEARCH_N:-30}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

declare -A NAMES=(
  [lofi]="Lofi" [work]="Work" [study]="Study" [focus]="Focus" [zen]="Zen" [ambient]="Ambient & nature"
  [jazz]="Jazz" [sleep]="Sleep" [classical]="Classical" [synthwave]="Synthwave" [streams]="24/7 streams"
)
ORDER=(lofi work study focus zen ambient jazz sleep classical synthwave streams)
declare -A QUERIES=(
  [lofi]="lofi hip hop radio|lofi beats to relax study|lofi chill mix hours"
  [work]="music for work productivity|deep focus work music|work from home music playlist"
  [study]="study music concentration|study with me lofi music|music for studying long"
  [focus]="focus music deep concentration|flow state music|binaural beats focus music"
  [zen]="zen music meditation|japanese zen music|zen garden music relaxing"
  [ambient]="ambient music long|nature sounds relaxing hours|space ambient music"
  [jazz]="jazz music relaxing|coffee shop jazz|smooth jazz playlist hours"
  [sleep]="sleep music deep|rain sounds for sleeping|deep sleep music hours"
  [classical]="classical music for studying|classical music relaxing|piano classical playlist"
  [synthwave]="synthwave mix|synthwave radio live|chillwave retrowave mix"
  [streams]="24/7 live radio music|lofi radio live 24/7|ambient radio live 24/7|jazz radio live 24/7"
)

for cat in "${ORDER[@]}"; do
  IFS='|' read -r -a qs <<<"${QUERIES[$cat]}"
  for q in "${qs[@]}"; do
    echo "  $cat: $q" >&2
    yt-dlp --no-warnings --flat-playlist -j -- "ytsearch$N:$q" 2>/dev/null >>"$TMP/$cat.jsonl" || true
  done
done

python3 - "$TMP" "$OUT" "${ORDER[@]}" <<'PY'
import json, sys, os, datetime
tmp, out, *order = sys.argv[1:]
names = {"lofi":"Lofi","work":"Work","study":"Study","focus":"Focus","zen":"Zen","ambient":"Ambient & nature",
         "jazz":"Jazz","sleep":"Sleep","classical":"Classical","synthwave":"Synthwave","streams":"24/7 streams"}
prev = {}
if os.path.exists(out):
    try: prev = json.load(open(out))
    except Exception: prev = {}
cats = []
def entry(e):
    live = e.get("live_status") == "is_live"
    return {"id": e["id"], "title": (e.get("title") or "").strip(), "channel": e.get("channel") or e.get("uploader") or "",
            "channel_url": e.get("channel_url") or e.get("uploader_url") or "",
            "url": "https://www.youtube.com/watch?v=" + e["id"], "live": live,
            "duration": int(e.get("duration") or 0), "views": int(e.get("view_count") or 0),
            "viewers": int(e.get("concurrent_view_count") or 0)}
for cat in order:
    seen, items = set(), []
    p = os.path.join(tmp, cat + ".jsonl")
    if os.path.exists(p):
        for line in open(p):
            line = line.strip()
            if not line: continue
            try: e = json.loads(line)
            except Exception: continue
            if not e.get("id") or e["id"] in seen: continue
            if e.get("live_status") == "is_upcoming": continue
            x = entry(e)
            if not x["live"] and x["duration"] < 3600: continue
            seen.add(e["id"]); items.append(x)
    live = sorted([i for i in items if i["live"]], key=lambda i: -i["viewers"])
    vod = sorted([i for i in items if not i["live"]], key=lambda i: -i["views"])
    def take(lst, n):
        per, outl = {}, []
        for i in lst:
            c = i["channel"]
            if per.get(c, 0) >= 3: continue
            per[c] = per.get(c, 0) + 1; outl.append(i)
            if len(outl) >= n: break
        return outl
    if cat == "streams": chosen = take(live, 10)
    else:
        chosen = take(live, 5) + take(vod, 5)
        if len(chosen) < 10: chosen += [i for i in take(vod, 10) if i not in chosen][:10 - len(chosen)]
    if cat == "zen":
        # the default stream, Aether Journey's bear path, stays first
        pinned = next((e for e in (prev.get("categories") or []) if e["id"] == "zen"), {"entries": []})["entries"][:1] if prev else []
        pinned = [e for e in pinned if e.get("pinned")]
        chosen = pinned + [i for i in chosen if not pinned or i["id"] != pinned[0]["id"]][:10 - len(pinned)]
    cats.append({"id": cat, "name": names.get(cat, cat), "entries": chosen})
prev = {}
if os.path.exists(out):
    try: prev = json.load(open(out))
    except Exception: prev = {}
doc = {"schema": 1, "generated": datetime.date.today().isoformat(),
       "ratings_api": prev.get("ratings_api", ""), "source": prev.get("source", "tools/build-catalog.sh (yt-dlp searches)"),
       "channels": prev.get("channels") or [{"id": "AetherJourneyMusic", "name": "Aether Journey", "url": "https://www.youtube.com/@AetherJourneyMusic", "note": "Japanese zen music along the bear's path: the default stream"}],
       "categories": cats}
json.dump(doc, open(out, "w"), indent=1, ensure_ascii=False)
print(out, sum(len(c["entries"]) for c in cats), "entries")
PY
