#!/usr/bin/env python3
"""
객관 과제(O1·O2·O3) 정답 대조 채점기 — 심판 없이 ground truth로 채점한다.
입력: bench/raw.json (워크플로 산출물). 출력: stdout 요약 + bench/objective_scores.json

O1 merge_intervals : 생성된 코드를 추출·실행해 숨은 테스트 통과 여부(pass/fail).
O2 mutable default : 줄번호(1) + 원인 키워드(가변/기본값/mutable/default) 동시 충족.
O3 추출            : JSON 파싱 후 name/amount/date 필드 정확 일치(/3).

출처: 전체 자작. 정답·테스트케이스는 본 파일에 하드코딩(재현용).
"""
import json, re, sys, io, contextlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw.json"

# ---------- O1: merge_intervals 숨은 테스트 ----------
O1_CASES = [
    ([], []),
    ([[1, 3], [2, 6], [8, 10], [15, 18]], [[1, 6], [8, 10], [15, 18]]),
    ([[1, 4], [4, 5]], [[1, 5]]),
    ([[1, 4], [0, 4]], [[0, 4]]),
    ([[1, 4], [2, 3]], [[1, 4]]),
    ([[2, 3], [1, 2]], [[1, 3]]),          # 정렬 필요
    ([[1, 4], [5, 6]], [[1, 4], [5, 6]]),  # 인접 비겹침
]

def extract_code(ans: str) -> str:
    m = re.search(r"```(?:python|py)?\s*\n(.*?)```", ans, re.DOTALL)
    if m:
        return m.group(1)
    # 코드블록 없으면 def 부터 끝까지 시도
    m = re.search(r"(def\s+merge_intervals.*)", ans, re.DOTALL)
    return m.group(1) if m else ans

def score_o1(ans: str):
    code = extract_code(ans)
    ns = {}
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            exec(code, ns)
        fn = ns.get("merge_intervals")
        if not callable(fn):
            return {"pass": False, "detail": "merge_intervals 미정의"}
        passed = 0
        for inp, exp in O1_CASES:
            try:
                got = fn([list(x) for x in inp])
                if [list(x) for x in got] == [list(x) for x in exp]:
                    passed += 1
            except Exception as e:
                pass
        return {"pass": passed == len(O1_CASES), "detail": f"{passed}/{len(O1_CASES)} 케이스"}
    except Exception as e:
        return {"pass": False, "detail": f"실행 오류: {type(e).__name__}: {e}"}

# ---------- O2: mutable default argument ----------
O2_CAUSE = ["가변", "기본값", "기본 인자", "디폴트", "mutable", "default", "공유"]
def score_o2(ans: str):
    line_ok = bool(re.search(r"(?<!\d)1(?:\s*번|\s*번째|\s*line|\s*줄|\s*행|$)", ans)) or "1:" in ans or "줄 1" in ans or "line 1" in ans.lower() or "첫" in ans
    cause_ok = any(k.lower() in ans.lower() for k in O2_CAUSE)
    return {"pass": bool(line_ok and cause_ok), "line_ok": bool(line_ok), "cause_ok": bool(cause_ok)}

# ---------- O3: 구조적 추출 ----------
O3_GOLD = {"name": "김민수", "amount": 1250000, "date": "2026-03-15"}
def score_o3(ans: str):
    m = re.search(r"\{.*\}", ans, re.DOTALL)
    if not m:
        return {"fields": 0, "detail": "JSON 없음"}
    try:
        obj = json.loads(m.group(0))
    except Exception:
        return {"fields": 0, "detail": "JSON 파싱 실패"}
    f = 0
    detail = {}
    for k, v in O3_GOLD.items():
        got = obj.get(k)
        if isinstance(v, int):
            try:
                got_n = int(str(got).replace(",", "").replace("원", "").strip())
            except Exception:
                got_n = None
            ok = got_n == v
        else:
            ok = str(got).strip() == v
        detail[k] = {"got": got, "ok": ok}
        f += 1 if ok else 0
    return {"fields": f, "detail": detail}

def main():
    if not RAW.exists():
        print(f"[대기] {RAW} 아직 없음 — 워크플로 완료 후 raw.json 저장하고 재실행", file=sys.stderr)
        sys.exit(1)
    data = json.loads(RAW.read_text())
    gen = data["genResults"]
    out = {"O1": {}, "O2": {}, "O3": {}}
    for g in gen:
        tid, cond, tr, ans = g["taskId"], g["condition"], g["trial"], g["answer"]
        if tid == "O1":
            out["O1"].setdefault(cond, []).append({"trial": tr, **score_o1(ans)})
        elif tid == "O2":
            out["O2"].setdefault(cond, []).append({"trial": tr, **score_o2(ans)})
        elif tid == "O3":
            out["O3"].setdefault(cond, []).append({"trial": tr, **score_o3(ans)})
    (ROOT / "objective_scores.json").write_text(json.dumps(out, ensure_ascii=False, indent=2))
    print("=== 객관 채점 (정답 대조, 심판 없음) ===\n")
    for task in ("O1", "O2", "O3"):
        print(f"[{task}]")
        for cond, rows in out[task].items():
            print(f"  {cond:16s} {rows}")
        print()
    print("저장: bench/objective_scores.json")

if __name__ == "__main__":
    main()
