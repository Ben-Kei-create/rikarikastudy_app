#!/usr/bin/env python3
"""Append questions from the rikarikastudy Supabase DB to questions_mountain.json (append-only).

Reads SUPABASE_URL / SUPABASE_KEY (publishable key) from the environment or a gitignored `.env`.
Existing IDs and questions are never changed; new 2-choice questions get the next IDs (00282...).
Image questions are skipped (release 1 has none).  Usage: fetch_supabase.py [--dry-run]
"""
import hashlib, json, os, sys, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "doparika/Resources/questions_mountain.json")
SUBJECT = {"生物": "biology", "化学": "chemistry", "物理": "physics", "地学": "earth"}
GRADE = {"中1": 1, "中2": 2, "中3": 3}

def load_env():
    p = os.path.join(ROOT, ".env")
    if os.path.exists(p):
        for line in open(p):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

def h(s):
    return int(hashlib.sha256(s.encode()).hexdigest(), 16)

def fetch_all(url, key):
    rows, start = [], 0
    while True:
        q = urllib.parse.urlencode({"select": "*", "order": "created_at.asc,id.asc"})
        req = urllib.request.Request(f"{url}/rest/v1/questions?{q}", headers={
            "apikey": key, "Authorization": f"Bearer {key}",
            "Range-Unit": "items", "Range": f"{start}-{start + 999}"})
        with urllib.request.urlopen(req, timeout=30) as r:
            batch = json.load(r)
        rows += batch
        if len(batch) < 1000:
            return rows
        start += 1000

def to_two_choice(r):
    """Return (pair, answer) or None if the row can't be a clean 2-choice question."""
    if r.get("image_url") or not r.get("question") or not r.get("answer"):
        return None
    t, ans, ch = r.get("type"), r["answer"], r.get("choices") or []
    if t == "true_false":
        pair = ["○", "×"] if ans in ("○", "×") else ["正しい", "誤り"] if ans in ("正しい", "誤り") else None
        return (pair, ans) if pair else None
    if t in ("choice", "choice4", "fill_choice") and ans in ch and len(ch) >= 2:
        wrong = sorted((c for c in ch if c != ans), key=lambda c: h(r["question"] + c))
        return [ans, wrong[0]], ans
    return None

def main():
    load_env()
    url, key = os.environ.get("SUPABASE_URL", "").rstrip("/"), os.environ.get("SUPABASE_KEY", "")
    if not url or not key or "xxxxx" in url + key:
        sys.exit("Set real SUPABASE_URL / SUPABASE_KEY (env or .env). Placeholder values won't work.")
    existing = json.load(open(OUT))
    seen = {q["question"] for q in existing}
    next_id = max(int(q["id"]) for q in existing) + 1
    rows = fetch_all(url, key)
    kinds, added, skipped = {}, [], 0
    for r in rows:
        kinds[r.get("type")] = kinds.get(r.get("type"), 0) + 1
        subj, conv = SUBJECT.get(r.get("field")), to_two_choice(r)
        if not subj or not conv or r["question"] in seen:
            skipped += 1
            continue
        pair, ans = conv
        if h(r["question"] + "swap") % 2 and r.get("type") != "true_false":
            pair = pair[::-1]
        seen.add(r["question"])
        added.append({
            "id": "%05d" % next_id, "stage": "mountain",
            "grade": GRADE.get(r.get("grade"), 1), "subject": subj, "difficulty": 1,
            "question": r["question"],
            "choices": [{"id": "A", "text": pair[0]}, {"id": "B", "text": pair[1]}],
            "correctChoiceId": "A" if pair[0] == ans else "B",
            "explanation": r.get("explanation") or "",
        })
        next_id += 1
    print(f"fetched {len(rows)} rows, types {kinds}")
    print(f"new 2-choice questions: {len(added)}, skipped (unsupported/duplicate): {skipped}")
    if "--dry-run" in sys.argv:
        return
    json.dump(existing + added, open(OUT, "w"), ensure_ascii=False, indent=2)
    print("wrote", OUT, "total", len(existing) + len(added))

main()
