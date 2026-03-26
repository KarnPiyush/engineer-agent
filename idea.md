# EA — Engineer Agent

### A lean, globally-installable bash CLI that orchestrates Gemini Pro, Kilo Code CLI, and Cursor Pro to multiply your development velocity

> **Stack reality:** Gemini Pro CLI (full access) + Kilo Code CLI (free gateway models) + Cursor Pro — zero additional monthly cost, no Node.js runtime, no local LLM requirement.

---

## Table of Contents

1. [Vision & Philosophy](#1-vision--philosophy)
2. [Your Actual Stack](#2-your-actual-stack)
3. [Architecture Overview](#3-architecture-overview)
4. [Model Routing Strategy](#4-model-routing-strategy)
5. [Core Commands](#5-core-commands)
6. [Smart Cursor Debug Workflow](#6-smart-cursor-debug-workflow)
7. [Parallel Agents via Kilo](#7-parallel-agents-via-kilo)
8. [Pre-Push Review Pipeline](#8-pre-push-review-pipeline)
9. [Prompt Library](#9-prompt-library)
10. [Project Structure](#10-project-structure)

---

## 1. Vision & Philosophy

**EA** (Engineer Agent) is a lightweight bash CLI that routes engineering tasks to the right AI tool:

- **Gemini Pro CLI** for planning, architecture, and large-context analysis (1M token window)
- **Kilo Code CLI** for agentic coding, debugging, reviews, and parallel multi-agent work (free models)
- **Cursor Pro** for in-editor debugging and surgical fixes (via EA-generated debug briefs)

The guiding principle: **use the right tool for the task, not the most powerful one.** Gemini Pro handles what needs a massive context window. Kilo free models handle agentic coding and reviews. Cursor handles inline editing where it excels. EA is the orchestrator that makes this seamless.

### What This Is NOT

- Not a Node.js application — it is plain bash scripts, installable in seconds
- Not a local LLM runner — Ollama is optional, not required
- Not a framework — it is a thin routing layer over tools you already have
- Not overengineered — every line of code earns its place

---

## 2. Your Actual Stack

| Tool | Access | Daily Limit | Best For |
|------|--------|-------------|----------|
| **Gemini Pro CLI** | `gemini` command, Pro tier | ~1000 req/day (Flash), ~10-15 (Pro) | Architecture, planning, full-codebase analysis (1M ctx) |
| **Kilo Code CLI** | `kilo-code` command, free models | Generous (model-dependent) | Agentic coding, file edits, debug analysis, code review, parallel agents |
| **Cursor Pro** | In-editor AI agent | Pro subscription limits | Inline fixes, agent-mode debugging, autocomplete |

### Best Free Kilo Models by Task

| Task Type | Kilo Model | Why This Model |
|-----------|-----------|----------------|
| Quick fixes, single-file edits | **Qwen3 Coder** (free) | Optimized for code generation and tool use |
| Code review, reasoning | **DeepSeek R1** (free) | Strongest reasoning capability among free models |
| Multi-step feature building | **Qwen3 Coder** (free) | Best at agentic multi-file workflows |
| Debug analysis | **DeepSeek R1** (free) | Hypothesis-driven root cause analysis |
| Commit messages | **Kimi K2** (free) | Fast, structured output |
| Parallel agent tasks | **Qwen3 Coder** (free) | Reliable for autonomous branch work |

> **Note:** Free models on Kilo rotate over time. Run `kilo-code` then `/model list` to see current free options. Models marked `(free)` are available at zero cost through the Kilo Gateway.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   ea CLI (bash)                      │
│              Global: `ea <command>`                   │
└────────────────────────┬────────────────────────────┘
                         │
          ┌──────────────▼──────────────┐
          │        Task Router           │
          │  route_task() in common.sh   │
          │                              │
          │  plan/architect  → Gemini    │
          │  fix/ship/review → Kilo      │
          │  debug           → Kilo+Cursor│
          │  commit          → Kilo      │
          │  parallel        → Kilo      │
          └──────┬────────────┬─────────┘
                 │            │
    ┌────────────▼──┐  ┌─────▼──────────────┐
    │  Gemini Pro   │  │  Kilo Code CLI     │
    │  CLI          │  │  (free models)     │
    │               │  │                    │
    │  • Planning   │  │  • Code mode       │
    │  • Architect  │  │  • Debug mode      │
    │  • Large ctx  │  │  • Parallel agents │
    └───────┬───────┘  └────────┬───────────┘
            │                   │
    ┌───────▼───────────────────▼───────────┐
    │        .engineer-agent/ artifacts      │
    │                                        │
    │  spec.md, architecture.md, plan.md,    │
    │  tasks.md, debug-brief.md              │
    │                                        │
    │  debug-brief.md → feed to Cursor       │
    │  agent mode for surgical fixes         │
    └────────────────────────────────────────┘
```

### The Cursor Debug Bridge

The key architectural insight: EA does not try to compete with Cursor's editor integration. Instead, EA generates a **debug brief** — a structured analysis file — that you feed to Cursor's agent mode. This gives Cursor:

1. EA's codebase-wide error analysis (from Kilo DeepSeek R1)
2. Relevant file paths and line numbers
3. Git diff context showing recent changes
4. A hypothesis about root cause
5. Suggested fix locations

Cursor then applies its full editor context (open files, LSP, type info) to make the actual fix. Best of both worlds.

---

## 4. Model Routing Strategy

EA routes every command to the cheapest tool that can handle it well:

```
ROUTING MATRIX

              │ Gemini Pro CLI      │ Kilo Code CLI         │ Cursor Pro
──────────────┼─────────────────────┼───────────────────────┼──────────────
ea plan       │ PRIMARY (1M ctx)    │ —                     │ reads tasks.md
ea review     │ fallback (>500 loc) │ PRIMARY (DeepSeek R1) │ —
ea fix        │ —                   │ PRIMARY (Qwen3 Coder) │ fallback
ea debug      │ —                   │ ANALYZE (DeepSeek R1) │ FIX (agent mode)
ea ship       │ PLAN phase          │ EXECUTE (Qwen3 Coder) │ —
ea commit     │ —                   │ PRIMARY (Kimi K2)     │ —
ea parallel   │ —                   │ PRIMARY (Qwen3 Coder) │ —
ea hook       │ fallback            │ PRIMARY (fast scan)   │ —
```

### Escalation Rules

1. Kilo is the default for all agentic work (free, capable)
2. Gemini Pro is invoked only when context exceeds Kilo's effective range (>5k lines) or for planning/architecture tasks
3. Cursor is the target for debug fixes — EA generates the brief, Cursor applies it
4. If Kilo is unavailable, EA falls back to Gemini for everything

---

## 5. Core Commands

### 5.1 Plan (`ea plan`)
```bash
ea plan "add JWT auth to the API"
ea plan --req "add RBAC" --path /path/to/project
```
Uses Gemini Pro (1M context window) to generate:
- `.engineer-agent/spec.md` — engineering specification
- `.engineer-agent/architecture.md` — ADR
- `.engineer-agent/plan.md` — implementation plan
- `.engineer-agent/tasks.md` — Cursor-ready task file

### 5.2 Fix (`ea fix`)
```bash
ea fix src/auth/login.ts               # Fix specific file
ea fix "null pointer in checkout"       # Fix by description
ea fix --last-error                     # Fix based on last terminal error
```
Sends file + error context to Kilo Code CLI (Qwen3 Coder, code mode). Shows diff, applies on confirmation.

### 5.3 Review (`ea review`)
```bash
ea review                               # Review last commit
ea review --diff-args "main..feature"   # Review branch diff
ea review --backend gemini              # Force Gemini for large diffs
```
Uses Kilo (DeepSeek R1) for diffs under 500 lines. Escalates to Gemini Pro for larger diffs. Output: structured BLOCKER / WARNING / SUGGESTION report.

### 5.4 Debug (`ea debug`)
```bash
ea debug "TypeError: Cannot read property 'id' of undefined"
ea debug --file error.log
ea debug --last-error
```
Two-phase workflow:
1. **Analyze** — Kilo (DeepSeek R1, debug mode) generates `.engineer-agent/debug-brief.md`
2. **Fix** — Open Cursor, paste: `Follow the debug brief in .engineer-agent/debug-brief.md`

The debug brief contains: error analysis, root cause hypothesis, relevant file paths, git diff context, and a ready-to-paste Cursor prompt.

### 5.5 Ship (`ea ship`)
```bash
ea ship "add rate limiting to API endpoints"
ea ship "implement dark mode" --breakdown    # Plan only
```
Two-phase workflow:
1. **Plan** — Gemini Pro generates feature plan
2. **Execute** — Kilo parallel agents implement file-by-file on a feature branch

### 5.6 Commit (`ea commit`)
```bash
ea commit                    # Generate from staged diff
ea commit --conventional     # Enforce conventional commits format
```
Uses Kilo (Kimi K2, fastest free model) to generate commit message from `git diff --staged`. Near-instant.

### 5.7 Parallel (`ea parallel`)
```bash
ea parallel "fix CSS layout" "add color picker" "write auth tests"
```
Spawns N Kilo Code CLI parallel agents. Each agent:
- Creates its own git branch
- Works autonomously on its task
- Commits changes to the branch
- Runs in background, reports when done

### 5.8 Hook (`ea hook`)
```bash
ea hook install               # Install pre-push review hook
ea hook uninstall             # Remove hook
```

---

## 6. Smart Cursor Debug Workflow

This is the key innovation in EA. Instead of building a debugger in the terminal, EA leverages Cursor's agent mode as the "last mile" for fixes.

### The Flow

```
Error occurs → ea debug "error message"
                    │
                    ▼
         Kilo CLI (DeepSeek R1, debug mode)
         Analyzes error + codebase context
                    │
                    ▼
         .engineer-agent/debug-brief.md
         ┌──────────────────────────────┐
         │ ## Error Analysis             │
         │ What happened and why         │
         │                               │
         │ ## Root Cause                  │
         │ The actual underlying issue    │
         │                               │
         │ ## Relevant Files              │
         │ - src/auth.ts:47              │
         │ - src/middleware.ts:12         │
         │                               │
         │ ## Recent Changes (git diff)   │
         │ Changes that may have caused   │
         │                               │
         │ ## Suggested Fix               │
         │ What to change and where       │
         │                               │
         │ ## Cursor Prompt               │
         │ Ready-to-paste prompt for      │
         │ Cursor agent mode              │
         └──────────────────────────────┘
                    │
                    ▼
         Open Cursor → Agent Mode → Paste prompt
         Cursor has: editor context + EA analysis = surgical fix
```

### Why This Works Better Than Terminal-Only Debugging

| Approach | Context Available | Edit Capability |
|----------|------------------|-----------------|
| Terminal debugger | Error + file content | None (must copy-paste) |
| Cursor alone | Open files + LSP | Full editor |
| **EA + Cursor** | **Codebase-wide analysis + git diff + error trace** | **Full editor** |

EA gives Cursor the broad analysis it cannot do alone. Cursor gives EA the editor integration it cannot do from a terminal.

---

## 7. Parallel Agents via Kilo

Kilo Code CLI supports spawning parallel agents that each work on separate git branches. EA exposes this as `ea parallel`.

### How It Works

```bash
ea parallel "task 1" "task 2" "task 3"
```

Each task:
1. Gets its own `kilo-code` process
2. Creates a branch: `ea/parallel/<sanitized-task-name>`
3. Runs in autonomous mode (no approval needed)
4. Commits completed work to its branch
5. Reports completion in the terminal

### Use Cases

- **Feature decomposition**: Break a feature into parallel subtasks
- **Test generation**: Generate tests for multiple modules simultaneously
- **Bug fixes**: Fix multiple independent bugs at the same time
- **Refactoring**: Rename/restructure across independent modules

---

## 8. Pre-Push Review Pipeline

`ea hook install` sets up a git pre-push hook that runs `ea review` automatically before every push.

- Uses Kilo (fast, free) for the review
- Falls back to Gemini for large diffs
- Saves review to `.code-review/<timestamp>_review.md`
- Does not block push (warns only) — override with config

---

## 9. Prompt Library

All prompts live in `prompts/` as markdown files:

| Prompt | Used By | Purpose |
|--------|---------|---------|
| `rephrase.md` | `ea plan` | Rewrite raw requirement as engineering spec |
| `architect.md` | `ea plan` | Generate Architecture Decision Record |
| `senior-swe.md` | `ea plan` | Generate implementation plan |
| `review.md` | `ea review` | Structured code review |
| `debug-brief.md` | `ea debug` | Generate debug analysis + Cursor prompt |
| `cursor-debug.md` | `ea debug` | Template for Cursor agent mode prompt |

---

## 10. Project Structure

```
engineer-agent/
├── ea                          # CLI entry point (bash)
├── setup.sh                    # Global install script
├── lib/
│   ├── common.sh               # Shared helpers: call_gemini, call_kilo, route_task
│   ├── cmd-plan.sh             # ea plan (Gemini Pro)
│   ├── cmd-review.sh           # ea review (Kilo or Gemini)
│   ├── cmd-fix.sh              # ea fix (Kilo Qwen3 Coder)
│   ├── cmd-debug.sh            # ea debug (Kilo + Cursor bridge)
│   ├── cmd-ship.sh             # ea ship (Gemini plan + Kilo execute)
│   ├── cmd-commit.sh           # ea commit (Kilo Kimi K2)
│   ├── cmd-parallel.sh         # ea parallel (Kilo parallel agents)
│   └── cmd-hook.sh             # ea hook install/uninstall
├── prompts/
│   ├── rephrase.md
│   ├── architect.md
│   ├── senior-swe.md
│   ├── review.md
│   ├── debug-brief.md
│   └── cursor-debug.md
└── README.md
```

---

**License:** MIT  
**Built with:** Gemini Pro CLI + Kilo Code CLI (free models) + Cursor Pro
