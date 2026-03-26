# Prompt Engineering

EA uses markdown templates under **`prompts/`**, combined with dynamic context via **`render_prompt()`** in **`lib/common.sh`**. Every Gemini/Kilo call also prepends **`get_tools_prompt_section()`** (backend-native tools + **`FILE_WRITE`** instructions).

## Prompt templates

| File | Purpose | Consumed by |
|------|---------|-------------|
| `rephrase.md` | Requirement → engineering spec | `ea plan`, `ea ship` (phase 1) |
| `architect.md` | Spec → ADR | `ea plan`, `ea ship` |
| `senior-swe.md` | Plan / tasks generation | `ea plan`, `ea ship` |
| `review.md` | Code review from git diff | `ea review` |
| `debug-brief.md` | Debug analysis | `ea debug` |
| `cursor-debug.md` | Legacy Cursor-oriented debug | Rarely used |

## Prompt rendering

```bash
render_prompt TEMPLATE_FILE [LABEL CONTENT_FILE] ...
```

Example (`lib/cmd-plan.sh`):

```bash
step1_prompt="$(render_prompt "$prompts_dir/rephrase.md" "Raw Requirement" "$req_file")"
```

`req_file` is produced by **`get_planning_context`** and includes README, optional **semantic RAG** section, structure, language hints, git summary, and **## New Requirement**.

## Injected sections for `ea plan` / `ea ship` (planning)

1. **Raw requirement file** — multi-source project context + requirement (see **[CONTEXT_ENGINE.md](CONTEXT_ENGINE.md)**).  
2. **Engineering specification** — prior step output.  
3. **Architecture Decision Record** — prior step output.  
4. **Implementation plan** — prior step output (for tasks step).

## Backend-native tool preamble

`get_tools_prompt_section()` does **not** inject a fixed tool allowlist (Gemini vs Kilo names differ). It instructs the model to use **only tools the active CLI exposes**, and documents the **`FILE_WRITE`** protocol for artifacts EA applies on disk.

## FILE_WRITE protocol

Fenced blocks:

````markdown
```FILE_WRITE:path/to/file
contents
```
````

Parsed by **`parse_and_apply_file_writes()`** in **`lib/common.sh`** (used in `ea plan`, `ea ship`, `ea fix`, etc.).

## Edge cases

| Scenario | Handling |
|----------|----------|
| Missing template | Fails at `cat` / clear error |
| Empty injected file | Section present but empty |
| Malformed `FILE_WRITE` | Skipped; other text still echoed |
| Semantic index missing | Planning works without RAG block |

---

*Last updated: 2026-03-22*
