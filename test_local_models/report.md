# Local & Small Models as Coding Agents — Field Test

## Environment

- **Hardware:** RTX 4090 (24GB), Core i5-13600K, 64GB RAM
- **Local runtime:** LM Studio 0.4.16 (b2) · llama.cpp CUDA 12 (Windows) v2.21.0
- **Hosted:** Google AI Studio (Gemma) · Azure (GPT)
- **Agent harness:** pi coding agent (except code-5.3-medium, run via GitHub Copilot)
- **Target:** live [Flutter app, ~15k LOC Dart](https://github.com/maxim-saplin/nothingness) — drive the real macOS build, validate at runtime, produce screenshot evidence, keep tests green
- **Method:** single run per cell (qualitative field test, not a benchmark); manual verification of every result; human nudges allowed and noted

![alt text](image-7.png)

## Tasks

| Task | What it asks | Difficulty |
|---|---|---|
| **T1 — Drive** | Drive macOS app; smoke test play/pause, skip, fast-forward | low |
| **T2 — Settings** | Show *variants* under *cassette*; validate live + screenshot. Variation: rename *variant*→*color scheme* | medium |
| **T3 — Swipe-seek** | Replace centered seek overlay with bottom line + progress bar; validate live + screenshot | high |

## Results

Score 0–3 (FAIL / BAD / AVG / GOOD) · `(s)` skill-prompted · `2→3(s)` plain then skill · `—` not run · `DNF` infra failure · `✅` clean pass

| # | Model (host) | T1 · T2 · T3 | Comment |
|---|---|---|---|
| 1 | **code-5.3-medium** (cloud) | — · — · ✅ | Reference, run via GitHub Copilot. Only model to nail the hardest task cleanly; even improved the harness to do it. T3 only. |
| 2 | **gpt-5.4-mini-medium** (cloud) | 3 · 3 · DNF | Broadest clean record; 3s wherever it ran. Lost T3 to Azure throttling, not capability. |
| 3 | **qwen3.6-35b-a3b q4** (local) | 2 · 2→3(s) · 1 | The step-change. Best local; only SLM to finish Settings well. 24GB @ ~100 tok/s, full 256k ctx. Needs nudging; T3 shipped but buggy. |
| 4 | **gemma-4-31b-it** (Google API) | 3 · 2(s) · 0 | Best Gemma. Clean T1; failed T3 ×3. Leans on skill + nudges. Occasional server glitches (`MALFORMED_RESPONSE`, 500s). |
| 5 | **gemma-4-26b-a4b-it** (Google API) | 1 · 0(s) · — | Launches apps but loops, invents bugs, edits random files; no evidence produced. Occasional 500s. |
| 6 | **gemma-4-12b-qat q4** (local) | 1(s) · — · — | Hard-crashes mid-run (matches chess/arithmetic benches). Partial smoke test at best. |
| 7 | **gemma-4-26b-a4b-qat q4** (local) | 0 · 0(s) · — | Failed all incl. hard crash; huge token burn (1.5M+ in). Worst despite fitting fully in VRAM. |

**Tiers:** cloud SOTA (1–2) → viable local (3, Qwen) → hosted Gemma, glitchy but usable (4–5) → local Gemma, hard-crashes (6–7).

## Takeaways

- **Qwen3.6-35B-A3B is genuinely usable** for hands-on coding on a 24GB consumer GPU — a real shift from "local = toy." Needs nudging, so not for long-horizon autonomy.
- **Runtime stack matters as much as the weights:** local llama.cpp Gemma *hard-crashed*; the same family on Google's API only *glitched* (recoverable). Neither was crash-free.
- **SLM failure mode:** disproportionately hard requests trigger 10k+ token reasoning loops (reproduced across chess/arithmetic benches).
- **Self-reports are unreliable** — models declared success while their own screenshots disproved it (T3).
- **Small models are capable but jagged:** lots of human-in-the-loop. Useful for hands-on work, not autonomous swarms.
