# GPT-5.4 Nano

Provider: `azure-openai-responses`  
Thinking level: `medium`  
Cohort: `linux-isolated-baseline`

Evaluation is in progress. One of three required valid T1 reliability trials is complete, so no consolidated score or stability label is assigned yet. The seven-task sequential campaign (`t1-t7-gpt-5.4-nano-medium`) has not been scored.

| Task | Trial scores | Progress | Result |
| --- | --- | --- | --- |
| T1 Linux playback smoke | `[0]` | `1/3` | [Trial 1](t1-playback-smoke-linux/trial-1/result.json) |

Trial 1 is a valid candidate failure. The independently verified environment was healthy, but the candidate did not launch the app or execute any required playback action after one correction. Candidate usage was 535,839 tokens and $0.02421999; admission brought the combined cost to $0.02561524.
