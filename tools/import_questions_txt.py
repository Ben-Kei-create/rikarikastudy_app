#!/usr/bin/env python3
"""Append questions written in the plain-text format (see docs/QUESTION_FORMAT.md) to a stage's JSON file.

Append-only: existing IDs/questions are never changed; new questions get the next IDs (zero-padded 5 digits).
IDs are unique across ALL stages (the next ID continues after the highest ID in any stage file).
Usage: import_questions_txt.py FILE.txt [FILE2.txt ...] [--stage mountain|sky|sea] [--dry-run] [--out PATH]
  --stage defaults to mountain (地球). sky = 宇宙, sea = 深海. The file is questions_<stage>.json under Resources.
"""
import hashlib, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "doparika/Resources")
STAGES = ("mountain", "sky", "sea")
SUBJECT = {"生物": "biology", "化学": "chemistry", "物理": "physics", "地学": "earth"}
GRADE = {"中1": 1, "中2": 2, "中3": 3}
KEYS = {"図表": "figure", "分野": "field", "学年": "grade", "難易度": "difficulty", "問題": "question",
        "正解": "correct", "不正解": "wrong", "解説": "explanation", "単元": "unit"}
DIAGRAMS = {"ocean_zones", "trench", "ridge", "food_chain", "water_pressure", "moon_phases", "earth_orbit"}
LIMITS = {"question": 90, "correct": 24, "wrong": 24, "explanation": 140}

def h(s):
    return int(hashlib.sha256(s.encode()).hexdigest(), 16)

def parse(path):
    """Yield (start_line, dict) for each block; blocks are separated by a line of '---' or blank lines."""
    blocks, cur, start, last_key = [], {}, 0, None
    def flush():
        nonlocal cur, start, last_key
        if cur:
            blocks.append((start, cur))
        cur, start, last_key = {}, 0, None
    for no, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if line.startswith("#"):
            continue
        if line == "---" or line == "":
            if line == "---" or not cur or "explanation" in cur:
                flush()
            elif line == "":
                last_key = None            # blank line inside a block is tolerated until the next key
            continue
        m = re.match(r"^([^:：]+)[:：]\s*(.*)$", line)
        if m and m.group(1).strip() in KEYS:
            key = KEYS[m.group(1).strip()]
            if key in cur and key != "question":
                flush()
            if not cur:
                start = no
            cur[key] = m.group(2).strip()
            last_key = key
        elif last_key:                      # continuation line of a long value
            cur[last_key] += line
        else:
            raise ValueError(f"{path}:{no}: 認識できない行: {line[:30]}")
    flush()
    return blocks

def check_figure(raw):
    """Return (figure_dict, error). Same rules as Figure.isValid in the app."""
    try:
        f = json.loads(raw)
    except ValueError as e:
        return None, f"図表のJSONが読めません: {e}"
    kind = f.get("kind")
    if kind == "table":
        h, r = f.get("headers"), f.get("rows")
        if not h or not r or len(h) > 5 or any(len(x) != len(h) for x in r):
            return None, "表の headers / rows が正しくありません(列数をそろえ、列は5つまで)"
    elif kind == "chart":
        t = f.get("chartType")
        if t == "line":
            xs, ys = f.get("xs"), f.get("ys")
            if not xs or not ys or len(xs) != len(ys) or len(xs) < 2:
                return None, "折れ線グラフの xs / ys が正しくありません"
        elif t == "bar":
            c, v = f.get("categories"), f.get("values")
            if not c or not v or len(c) != len(v) or len(c) < 2:
                return None, "棒グラフの categories / values が正しくありません"
        else:
            return None, "chartType は line か bar"
    elif kind == "diagram":
        if f.get("name") not in DIAGRAMS:
            return None, "diagram の name は " + " / ".join(sorted(DIAGRAMS))
    else:
        return None, "kind は table / chart / diagram"
    return f, None

def validate(path, no, b):
    errs = []
    if b.get("figure"):
        _, fe = check_figure(b["figure"])
        if fe:
            errs.append(fe)
    for k in ("field", "question", "correct", "wrong", "explanation"):
        if not b.get(k):
            errs.append(f"{k} がありません")
    if b.get("field") and b["field"] not in SUBJECT:
        errs.append(f"分野は {'/'.join(SUBJECT)} のどれか: {b['field']}")
    if b.get("grade") and b["grade"] not in GRADE:
        errs.append(f"学年は 中1/中2/中3: {b['grade']}")
    if b.get("correct") and b.get("wrong") and b["correct"] == b["wrong"]:
        errs.append("正解と不正解が同じです")
    for k, lim in LIMITS.items():
        if b.get(k) and len(b[k]) > lim:
            errs.append(f"{k} が長すぎます({len(b[k])}字 > {lim}字)")
    return [f"{path}:{no}: {e}" for e in errs]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    stage = "mountain"
    if "--stage" in sys.argv:
        stage = sys.argv[sys.argv.index("--stage") + 1]
        args = [a for a in args if a != stage]
        if stage not in STAGES:
            sys.exit("--stage は " + "/".join(STAGES) + " のどれか")
    out = os.path.join(RES, f"questions_{stage}.json")
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
        args = [a for a in args if a != out]
    if not args:
        sys.exit(__doc__)
    existing = json.load(open(out, encoding="utf-8")) if os.path.exists(out) else []
    everything = []
    for st in STAGES:
        f = os.path.join(RES, f"questions_{st}.json")
        if os.path.exists(f):
            everything += json.load(open(f, encoding="utf-8"))
    seen = {q["question"] for q in everything}
    next_id = max([int(q["id"]) for q in everything] or [0]) + 1
    added, errors, dups = [], [], 0
    for path in args:
        try:
            blocks = parse(path)
        except ValueError as e:
            errors.append(str(e)); continue
        for no, b in blocks:
            errs = validate(path, no, b)
            if errs:
                errors += errs; continue
            if b["question"] in seen:
                dups += 1; continue
            seen.add(b["question"])
            pair = [b["correct"], b["wrong"]]
            if b["correct"] not in ("○", "×") and h(b["question"] + "swap") % 2:
                pair.reverse()               # spread the correct answer over A and B
            added.append({
                "id": "%05d" % next_id, "stage": stage,
                "grade": GRADE.get(b.get("grade", "中1"), 1), "subject": SUBJECT[b["field"]],
                "difficulty": int(b["difficulty"]) if b.get("difficulty", "").isdigit() else 1,
                "question": b["question"],
                "choices": [{"id": "A", "text": pair[0]}, {"id": "B", "text": pair[1]}],
                "correctChoiceId": "A" if pair[0] == b["correct"] else "B",
                "explanation": b["explanation"],
                **({"figure": check_figure(b["figure"])[0]} if b.get("figure") else {}),
            })
            next_id += 1
    for e in errors:
        print("ERROR", e)
    print(f"追加できる問題: {len(added)} / 重複スキップ: {dups} / エラー: {len(errors)}")
    if errors:
        sys.exit("エラーを直してから再実行してください(何も書き込んでいません)")
    if "--dry-run" in sys.argv:
        return
    json.dump(existing + added, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"書き込みました: {out} (合計 {len(existing) + len(added)} 問)")

main()
