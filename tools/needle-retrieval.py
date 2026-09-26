#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
"""Does the model still see the middle of a long prompt?

Speculative prefill trades context for speed: a small draft model scores the
prompt and low-scoring chunks never reach the big one. A stopwatch cannot see
what that costs, because a dropped chunk produces a confident answer, not an
error.

This plants distinctive values at known depths, asks for them back, and counts.
Run it against every filtering ratio you are considering, on your own hardware,
before trusting one. Always run the unfiltered control first: if it does not
score full marks, the harness or the model is the problem, not the filter.

    ./needle-retrieval.py --url http://127.0.0.1:8080 --tokens 32000

Observed on a Ryzen AI MAX+ 395 laptop (27B Q4, 32k):
    control / p=0.30 -> 5/5      p=0.15 -> 3/5, losing both middle needles.
"""
import argparse, json, random, sys, time, urllib.request

# Coding-shaped, arbitrary values: nothing here can be inferred from context.
NEEDLES = [
    (0.08, "The calibration constant for sensor array KX-7 is 84931.",  "84931"),
    (0.27, "def reconcile_ledger(entries, tolerance_minor=1470):",      "1470"),
    (0.51, "Pinned dependency: libspendline==3.14.9-rc2",               "3.14.9-rc2"),
    (0.74, "On overflow the adapter raises error code E-2287.",         "E-2287"),
    (0.93, "The default retry window is 6300 milliseconds.",            "6300"),
]
QUESTIONS = [
    "What is the calibration constant for sensor array KX-7?",
    "What is the tolerance_minor default in reconcile_ledger?",
    "What exact version is libspendline pinned to?",
    "What error code does the adapter raise on overflow?",
    "What is the default retry window in milliseconds?",
]

def filler(n_chars):
    """Varied, non-repetitive text. Repetitive filler inflates speculative
    acceptance and measures the wrong thing entirely."""
    import pathlib
    parts = []
    for root in (pathlib.Path.home()/".kinn_setup", pathlib.Path("/usr/share/doc")):
        if not root.exists():
            continue
        for f in sorted(root.rglob("*.md"))[:400]:
            try: parts.append(f.read_text(errors="ignore"))
            except Exception: pass
        if sum(len(p) for p in parts) > n_chars: break
    if not parts:
        sys.exit("no corpus found; pass --corpus FILE")
    out = "\n\n".join(parts)
    while len(out) < n_chars: out += "\n\n" + out
    return out[:n_chars]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--model", default=None)
    ap.add_argument("--tokens", type=int, default=32000, help="approx prompt tokens")
    ap.add_argument("--label", default="run")
    ap.add_argument("--corpus", default=None)
    a = ap.parse_args()

    body = (open(a.corpus).read() if a.corpus else filler(a.tokens * 35 // 10))
    for depth, sentence, _ in sorted(NEEDLES, key=lambda x: -x[0]):
        i = int(len(body) * depth)
        body = body[:i] + f"\n\n{sentence}\n\n" + body[i:]
    body = f"<!-- {a.label} {random.randint(10**9, 10**10)} -->\n" + body   # defeat prompt cache
    q = ("\n\nAnswer these using ONLY the document above. "
         "Reply as numbered lines, 'N: value', nothing else.\n"
         + "".join(f"{i+1}: {t}\n" for i, t in enumerate(QUESTIONS)))

    req = {"messages": [{"role": "user", "content": body + q}],
           "temperature": 0, "max_tokens": 400, "reasoning_effort": "low"}
    if a.model: req["model"] = a.model
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        a.url.rstrip("/") + "/v1/chat/completions",
        json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=3600).read())
    wall = time.time() - t0
    m = r["choices"][0]["message"]
    ans = ((m.get("content") or "") + " " + (m.get("reasoning_content") or "")).lower()

    hits = [v.lower() in ans for (_, _, v) in NEEDLES]
    detail = " ".join(f"d{int(d*100):02d}:{'HIT' if h else 'MISS'}"
                      for (d, _, _), h in zip(NEEDLES, hits))
    print(f"{a.label}: {sum(hits)}/{len(NEEDLES)} | {detail} | "
          f"in {r.get('usage',{}).get('prompt_tokens','?')} | wall {wall:.1f}s")
    sys.exit(0 if all(hits) else 1)

if __name__ == "__main__":
    main()
