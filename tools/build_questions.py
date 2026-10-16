#!/usr/bin/env python3
"""Convert rikarikastudy `choice4` examples into Doparika 2-choice JSON.

Usage: build_questions.py <rikarikastudy/examples dir> <out.json> [count]
IDs are assigned once (zero-padded 5 digits) and must never be renumbered after
release: re-running appends nothing and keeps the existing file's IDs if present.
"""
import glob, hashlib, json, os, sys

SUBJECT = {"生物": "biology", "化学": "chemistry", "物理": "physics", "地学": "earth"}
GRADE = {"中1": 1, "中2": 2, "中3": 3}

def h(s):
    return int(hashlib.sha256(s.encode()).hexdigest(), 16)

src, out = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 300

seen, pool = set(), {k: [] for k in SUBJECT.values()}
for f in sorted(glob.glob(os.path.join(src, "*.json"))):
    try:
        data = json.load(open(f))
    except Exception:
        continue
    if isinstance(data, dict):
        data = data.get("questions", [])
    for q in data:
        if not isinstance(q, dict) or q.get("type") != "choice4":
            continue
        subj = SUBJECT.get(q.get("field"))
        choices, ans, text = q.get("choices") or [], q.get("answer"), q.get("question")
        if not subj or ans not in choices or not text or len(choices) < 2 or text in seen:
            continue
        seen.add(text)
        pool[subj].append(q)

existing = {}
if os.path.exists(out):
    for q in json.load(open(out)):
        existing[q["question"]] = q["id"]
if existing:
    sys.exit("refusing to regenerate: %s already exists (IDs are immutable)" % out)

for v in pool.values():
    v.sort(key=lambda q: h(q["question"]))
order, i = [], 0
subjects = ["chemistry", "earth", "biology", "physics"]
while len(order) < limit and any(pool.values()):
    s = subjects[i % 4]; i += 1
    if pool[s]:
        order.append((s, pool[s].pop(0)))

result = []
for n, (subj, q) in enumerate(order, 1):
    wrong = [c for c in q["choices"] if c != q["answer"]]
    wrong.sort(key=lambda c: h(q["question"] + c))
    pair = [q["answer"], wrong[0]]
    if h(q["question"] + "swap") % 2:
        pair.reverse()
    ids = ["A", "B"]
    result.append({
        "id": "%05d" % n,
        "stage": "mountain",
        "grade": GRADE.get(q.get("grade"), 1),
        "subject": subj,
        "difficulty": 1,
        "question": q["question"],
        "choices": [{"id": ids[k], "text": pair[k]} for k in range(2)],
        "correctChoiceId": ids[pair.index(q["answer"])],
        "explanation": q.get("explanation") or "",
    })
json.dump(result, open(out, "w"), ensure_ascii=False, indent=2)
print(len(result), "questions")
