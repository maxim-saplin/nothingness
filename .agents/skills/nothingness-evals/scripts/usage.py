from __future__ import annotations

from typing import Any


def number(value: Any) -> float | int | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def normalized_usage(usage: dict[str, Any] | None) -> dict[str, Any]:
    usage = usage or {}
    cost = usage.get("cost") if isinstance(usage.get("cost"), dict) else {}
    aliases = {
        "input": ("input", "inputTokens", "input_tokens"),
        "output": ("output", "outputTokens", "output_tokens"),
        "reasoning": ("reasoning", "reasoningTokens", "reasoning_tokens"),
        "cacheRead": ("cacheRead", "cacheReadTokens", "cache_read_tokens"),
        "cacheWrite": ("cacheWrite", "cacheWriteTokens", "cache_write_tokens"),
        "total": ("totalTokens", "total_tokens"),
    }
    tokens = {name: next((value for key in keys if (value := number(usage.get(key))) is not None), 0) for name, keys in aliases.items()}
    if tokens["total"] == 0:
        tokens["total"] = tokens["input"] + tokens["output"] + tokens["cacheRead"] + tokens["cacheWrite"]
    cost_total = number(cost.get("total"))
    if cost_total is None:
        cost_total = number(usage.get("cost.total"))
    breakdown = {key: value for key, raw in cost.items() if (value := number(raw)) is not None}
    breakdown.update({key.removeprefix("cost."): value for key, raw in usage.items() if key.startswith("cost.") and (value := number(raw)) is not None})
    return {"tokens": tokens, "cost_usd": {"total": cost_total, "breakdown": breakdown}, "cost_missing": cost_total is None}