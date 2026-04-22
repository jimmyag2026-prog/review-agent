#!/usr/bin/env python3
"""_model.py — shared helper to resolve what LLM the review-agent should use.

Follows whatever hermes' main agent is configured to use (reads
~/.hermes/config.yaml → model.default) and maps the id to OpenRouter's
naming convention (since review-agent scripts call OpenRouter for stable,
uniform billing + multi-provider model access).

Order of precedence:
  1. REVIEW_AGENT_MODEL env var           (hard override, for testing)
  2. ~/.hermes/config.yaml model.default  (follow the main agent)
  3. hard fallback: anthropic/claude-sonnet-4.6
"""
import os
import re
from pathlib import Path


FALLBACK_MODEL = "anthropic/claude-sonnet-4.6"


def _hermes_to_openrouter(model: str, provider: str = "anthropic") -> str:
    """Convert hermes' model id format to OpenRouter's.

    Examples:
      'claude-sonnet-4-6'            → 'anthropic/claude-sonnet-4.6'
      'claude-sonnet-4-5-20250929'   → 'anthropic/claude-sonnet-4.5'    (strip date)
      'claude-opus-4-7'              → 'anthropic/claude-opus-4.7'
      'anthropic/claude-sonnet-4.6'  → 'anthropic/claude-sonnet-4.6'    (already OpenRouter)
      'gpt-5-mini'                   → 'openai/gpt-5-mini'              (other provider)
    """
    if not model:
        return FALLBACK_MODEL

    # Already OpenRouter-style (has provider/ prefix)?
    if "/" in model:
        return model

    # Strip Anthropic version-date suffix (YYYYMMDD)
    model = re.sub(r"-(\d{8})$", "", model)

    # Convert last -N-N to -N.N (claude-sonnet-4-6 → claude-sonnet-4.6)
    m = re.match(r"^(.*)-(\d+)-(\d+)$", model)
    if m:
        model = f"{m.group(1)}-{m.group(2)}.{m.group(3)}"

    # Provider prefix
    if provider in ("anthropic",):
        return f"anthropic/{model}"
    if provider == "openrouter":
        return model   # already an OpenRouter id
    # Unknown provider — just prefix with provider name
    return f"{provider}/{model}"


def get_main_agent_model() -> str:
    """Return the LLM model id (OpenRouter format) to use for LLM calls."""
    # 1. Env override
    env_model = os.environ.get("REVIEW_AGENT_MODEL", "").strip()
    if env_model:
        return env_model

    # 2. hermes config.yaml
    config_path = Path.home() / ".hermes" / "config.yaml"
    if config_path.exists():
        try:
            import yaml
            cfg = yaml.safe_load(config_path.read_text()) or {}
            model_block = cfg.get("model", {}) or {}
            model_id = model_block.get("default", "") or ""
            provider = model_block.get("provider", "anthropic") or "anthropic"
            if model_id:
                return _hermes_to_openrouter(model_id, provider)
        except Exception:
            pass   # fall through to default

    return FALLBACK_MODEL


# Self-test
if __name__ == "__main__":
    import sys
    tests = [
        # (input_model, input_provider, expected)
        ("claude-sonnet-4-6", "anthropic", "anthropic/claude-sonnet-4.6"),
        ("claude-sonnet-4-5-20250929", "anthropic", "anthropic/claude-sonnet-4.5"),
        ("claude-opus-4-7", "anthropic", "anthropic/claude-opus-4.7"),
        ("anthropic/claude-sonnet-4.6", "anthropic", "anthropic/claude-sonnet-4.6"),
        ("gpt-5-mini", "openai", "openai/gpt-5-mini"),
        ("", "anthropic", FALLBACK_MODEL),
    ]
    failed = 0
    for inp, prov, expected in tests:
        got = _hermes_to_openrouter(inp, prov)
        ok = got == expected
        print(f"{'✓' if ok else '✗'} '{inp}' (provider={prov}) → '{got}'  expected '{expected}'")
        if not ok: failed += 1
    print(f"\nresolved current hermes model: {get_main_agent_model()}")
    sys.exit(1 if failed else 0)
