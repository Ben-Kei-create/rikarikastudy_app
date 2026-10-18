#!/usr/bin/env python3
"""Append questions written in the plain-text format (see docs/QUESTION_FORMAT.md) to questions_mountain.json.

Append-only: existing IDs/questions are never changed; new questions get the next IDs (zero-padded 5 digits).
Usage: import_questions_txt.py FILE.txt [FILE2.txt ...] [--dry-run] [--out PATH]
"""
import hashlib, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "doparika/Resources/questions_mountain.json")
SUBJECT = {"生物": "biology", "化学": "chemistry", "物理": "physics", "地学": "earth"}
GRADE = {"中1": 1, "中2": 2, "中3": 3}
KEYS = {"分野": "field", "学年": "grade", "難易度": "difficulty", "問題": "question",
        "正解": "correct", "不正解": "wrong", "解説": "explanation", "単元": "unit"}
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

def validate(path, no, b):
    errs = []
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
    out = DEFAULT_OUT
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
        args = [a for a in args if a != out]
    if not args:
        sys.exit(__doc__)
    existing = json.load(open(out, encoding="utf-8"))
    seen = {q["question"] for q in existing}
    next_id = max(int(q["id"]) for q in existing) + 1
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
                "id": "%05d" % next_id, "stage": "mountain",
                "grade": GRADE.get(b.get("grade", "中1"), 1), "subject": SUBJECT[b["field"]],
                "difficulty": int(b["difficulty"]) if b.get("difficulty", "").isdigit() else 1,
                "question": b["question"],
                "choices": [{"id": "A", "text": pair[0]}, {"id": "B", "text": pair[1]}],
                "correctChoiceId": "A" if pair[0] == b["correct"] else "B",
                "explanation": b["explanation"],
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
