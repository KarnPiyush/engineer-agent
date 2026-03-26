# EA — Engineer Agent

A lean bash CLI that orchestrates **Gemini Pro**, **Kilo Code CLI** (free models), and **Cursor Pro** to multiply your development velocity.

Zero additional monthly cost. No Node.js runtime. No local LLM requirement. Just bash scripts routing tasks to the right AI tool.

---

## Prerequisites

| Tool | Required | Install |
|------|----------|---------|
| macOS/Linux shell (bash/zsh) | Yes | Built-in |
| `git` | Yes | Built-in or `brew install git` |
| **Gemini CLI** (`gemini`) | Yes | [Install guide](https://github.com/google-gemini/gemini-cli) |
| **Kilo Code CLI** (`kilo`) | Recommended | `npm install -g @kilocode/cli` |
| **Cursor Pro** | Recommended | [cursor.com](https://cursor.com) |

EA works with just Gemini CLI installed. Kilo Code CLI unlocks free-model routing, parallel agents, and debug mode. Cursor Pro unlocks the smart debug workflow.

### Configure Gemini API Key

```bash
export GEMINI_API_KEY="YOUR_GEMINI_API_KEY"
```

Add this to `~/.zshrc` or `~/.bashrc`, then `source ~/.zshrc`.

### Configure Kilo Code CLI

Run `kilo` once to complete initial setup (select provider, enter API key). Free models are available through the Kilo Gateway at zero cost.

---

## Install

```bash
cd /path/to/engineer-agent
chmod +x setup.sh
./setup.sh
```

This creates a symlink at `~/.local/bin/ea`. Add to your shell profile if needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify:

```bash
ea help
```

---

## Your Free Stack

EA routes every task to the cheapest tool that can handle it well:

| Tool | What It Handles | Cost |
|------|----------------|------|
| **Gemini Pro CLI** | Planning, architecture, large-context analysis (1M token window) | Free tier (~1000 req/day Flash, ~10-15 Pro) |
| **Kilo Code CLI** | Agentic coding, file edits, reviews, debugging, parallel agents | Free (Kilo Gateway models) |
| **Cursor Pro** | In-editor debugging and surgical fixes (via EA-generated debug briefs) | Pro subscription (you already have it) |

### Best Free Kilo Models by Task

| Task | Best Free Model | Why |
|------|----------------|-----|
| Quick fixes, single-file edits | **Qwen3 Coder** | Optimized for code generation |
| Code review, reasoning | **DeepSeek R1** | Strongest free reasoning model |
| Multi-step features | **Qwen3 Coder** | Best at agentic multi-file work |
| Debug analysis | **DeepSeek R1** | Hypothesis-driven root cause analysis |
| Commit messages | **Kimi K2** | Fast, structured output |
| Parallel agents | **Qwen3 Coder** | Reliable for autonomous branch work |

> Free models on Kilo rotate over time. Run `kilo` then `/model list` to see current options. Models marked `(free)` are zero cost.

---

## Routing Matrix

```
              Gemini Pro CLI        Kilo Code CLI          Cursor Pro
─────────────────────────────────────────────────────────────────────
ea plan       PRIMARY (1M ctx)      fallback               reads tasks.md
ea review     fallback (>500 loc)   PRIMARY (DeepSeek R1)  —
ea fix        fallback              PRIMARY (Qwen3 Coder)  fallback
ea debug      fallback              ANALYZE (DeepSeek R1)  FIX (agent mode)
ea ship       PLAN phase            EXECUTE (Qwen3 Coder)  —
ea commit     fallback              PRIMARY (Kimi K2)      —
ea parallel   —                     PRIMARY (Qwen3 Coder)  —
ea hook       fallback              PRIMARY (fast scan)    —
ea index      — (Node + Gemini)     —                      —
```

If Kilo is not installed, EA falls back to Gemini for everything. If Gemini is unavailable, EA tries Kilo for everything. At least one must be installed.

**Cursor** is not a backend EA invokes — it has no API or CLI for EA to call. For `ea plan` and `ea debug`, EA produces files (`tasks.md`, `debug-brief.md`) that you open in Cursor and run there. So you don’t “route through Cursor”; you use Cursor to consume EA’s output.

### Routing examples

| What you want | Command | What happens |
|---------------|---------|--------------|
| Plan a feature (default) | `ea plan "add auth"` | Gemini generates spec → ADR → plan → tasks.md (no override). |
| Review last commit (default) | `ea review` | Small diff → Kilo (DeepSeek R1). Large diff (≥500 lines) → Gemini. |
| Force review with Gemini | `ea review --backend gemini` | Gemini runs the review regardless of diff size. |
| Force review with Kilo | `ea review --backend kilo` | Kilo runs the review regardless of diff size. |
| Quick fix (default) | `ea fix src/auth.ts` | Kilo (Qwen3 Coder) generates the fix; fallback to Gemini if Kilo missing. |
| Force fix with Gemini | `ea fix src/auth.ts --backend gemini` | Gemini generates the fix. |
| Debug (default) | `ea debug "TypeError: ..."` | Kilo (DeepSeek R1, debug mode) writes `.engineer-agent/debug-brief.md`; you then use Cursor to apply it. |
| Force debug with Gemini | `ea debug "TypeError: ..." --backend gemini` | Gemini writes the debug brief instead of Kilo. |
| Commit message (default) | `ea commit` | Kilo (Kimi K2) generates the message; fallback to Gemini if Kilo missing. |
| Force commit with Gemini | `ea commit --backend gemini` | Gemini generates the commit message. |

### Force-routing: which commands support `--backend`?

You can **force Gemini or Kilo** only on commands that accept `--backend`:

| Command | Supports `--backend`? | Notes |
|---------|------------------------|--------|
| `ea fix` | Yes | `--backend gemini` \| `kilo` |
| `ea review` | Yes | `--backend gemini` \| `kilo` |
| `ea commit` | Yes | `--backend gemini` \| `kilo` |
| `ea debug` | Yes | `--backend gemini` \| `kilo` |
| `ea plan` | No | Always uses Gemini (1M context). |
| `ea ship` | No | Always Gemini for plan phase, then Kilo for execute. |
| `ea parallel` | No | Kilo only (parallel agents). |
| `ea hook` | No | Runs `ea review` with default routing. |

You **cannot** force routing “through Cursor” — Cursor is the place you use EA’s outputs (e.g. “Follow .engineer-agent/tasks.md” or “Follow .engineer-agent/debug-brief.md”), not a backend EA calls.

---

## Commands

### `ea plan` — Generate Implementation Artifacts

Uses Gemini Pro (1M context window) for planning. **Planning context** is built from multiple sources (not just README): README if present, repo structure, language/entrypoint hints, recent git history, and your requirement. This works even when README is missing or incomplete.

```bash
ea plan "add JWT auth to the API"
ea plan --req "add RBAC" --path /path/to/project
```

Generates four artifacts in a **timestamped folder** under `.engineer-agent/` (e.g. `.engineer-agent/20260319_154512_plan/`):
- `spec.md` — Engineering specification
- `architecture.md` — Architecture Decision Record
- `plan.md` — Step-by-step implementation plan
- `tasks.md` — Cursor-ready task file

The path to the latest plan run is saved in `.engineer-agent/latest-plan.txt`. Use the path printed at the end of the command, or open Cursor and tell it: *"Follow the instructions in [path from output]/tasks.md exactly."*

**Semantic context (optional RAG):** Run `ea index` once (requires Node.js + `GEMINI_API_KEY` / `GOOGLE_API_KEY`) to build `.engineer-agent/index.db`. After that, `ea plan` / `ea ship` prepend **Relevant Code Context (semantic retrieval)** to the planning prompt when `jq` is available.

---

### `ea index` — Local semantic index (RAG)

Builds or updates a **SQLite** index under `.engineer-agent/index.db` using **Gemini `gemini-embedding-001`** (override with `EA_EMBEDDING_MODEL`). Chunking is heuristic (language-aware boundaries + sliding windows). Search is local cosine similarity over stored vectors.

```bash
export GEMINI_API_KEY=...   # or GOOGLE_API_KEY
ea index                    # first run installs/builds lib/indexer via npm
ea index --force            # re-embed all files
ea index --exclude 'custom-vendor/**'   # extra ignore (built-ins already skip node_modules, venv, site-packages, …)
ea index search "where is cmd-plan defined" --limit 5
```

Set `EA_SKIP_SEMANTIC=1` to disable injection into planning context. Set `EA_SEMANTIC_LIMIT` (default `5`) for how many chunks to inject.

---

### `ea fix` — Quick-Fix a File or Error

Uses Kilo Code CLI (Qwen3 Coder, code mode).

```bash
ea fix src/auth/login.ts                # Fix a specific file
ea fix "null pointer in checkout flow"  # Fix by description
ea fix --last-error                     # Fix based on last terminal error
ea fix --backend gemini                 # Force Gemini instead of Kilo
```

Reads the file or error context, generates a surgical fix, and saves it to a timestamped folder (e.g. `.engineer-agent/20260319_155030_fix/last-fix.md`). The latest fix is also copied to `.engineer-agent/last-fix.md` for convenience.

---

### `ea review` — AI Code Review

Uses Kilo (DeepSeek R1) for diffs under 500 lines, Gemini Pro for larger diffs.

```bash
ea review                                  # Review last commit
ea review --diff-args "main..feature"      # Review branch diff
ea review --backend gemini                 # Force Gemini for all diffs
ea review --backend kilo                   # Force Kilo for all diffs
```

Saves a structured review (BLOCKER / WARNING / SUGGESTION) to `.code-review/<timestamp>_review.md`.

---

### `ea debug` — Smart Debug with Cursor Bridge

This is the key innovation. Uses Kilo (DeepSeek R1, debug mode) for analysis, then generates a brief for Cursor's agent mode to apply the fix.

```bash
ea debug "TypeError: Cannot read property 'id' of undefined"
ea debug --file /tmp/error.log
ea debug --last-error
```

#### The Debug Workflow (3 Steps)

**Step 1:** Run `ea debug` with the error:

```bash
ea debug "TypeError: Cannot read property 'id' of undefined"
```

EA analyzes the error using Kilo's debug mode (DeepSeek R1) with full codebase context — git diff, relevant files, stack trace parsing. It generates a timestamped folder (e.g. `.engineer-agent/20260319_160000_debug/`) with `debug-brief.md`; the latest is also copied to `.engineer-agent/debug-brief.md`.

**Step 2:** Open your project in Cursor:

```bash
cursor .
```

**Step 3:** Open Cursor's Agent Mode (Cmd+L) and paste:

```
Follow the debug brief in .engineer-agent/debug-brief.md to fix this bug.
```

Cursor reads the brief, navigates to the files, and applies the fix using its full editor context (LSP, types, open files).

#### Why This Works Better

| Approach | Codebase Context | Editor Integration | Cost |
|----------|-----------------|-------------------|------|
| Manual debugging | None | Manual | Free (your time) |
| Cursor alone | Open files + LSP | Full editor | Cursor Pro |
| Kilo alone | Full codebase | Terminal only | Free |
| **EA debug + Cursor** | **Full codebase analysis** | **Full editor** | **Free + Cursor Pro** |

EA gives Cursor the broad analysis it cannot do alone. Cursor gives EA the editor integration it cannot do from a terminal.

---

### `ea ship` — Plan + Execute a Feature

Gemini Pro plans the feature, Kilo Code CLI executes it.

```bash
ea ship "add rate limiting to API endpoints"
ea ship "implement dark mode" --breakdown    # Plan only, don't execute
```

**Workflow:**
1. Gemini Pro generates spec, architecture, and implementation plan
2. Plan is displayed for your review
3. Confirm to proceed → Kilo executes the plan step-by-step
4. Review with `ea review`, commit with `ea commit`

---

### `ea commit` — Generate Commit Message

Uses Kilo (Kimi K2, fastest free model) for near-instant commit messages.

```bash
git add .
ea commit                    # Generate from staged diff
ea commit --verbose          # Include body paragraph
ea commit --backend gemini   # Use Gemini instead
```

Generates a Conventional Commits formatted message, shows it for approval, then commits. You can edit before confirming.

---

### `ea parallel` — Spawn Parallel Agents

Uses Kilo Code CLI's parallel agent capability. Each agent works on a separate git branch.

```bash
ea parallel "fix CSS layout on desktop" "add color picker to notes" "write auth tests"
```

Each task:
1. Creates a branch: `ea/parallel/<sanitized-task-name>`
2. Runs an autonomous Kilo agent
3. Commits changes to its branch
4. Reports completion

**Use cases:**
- Break a feature into parallel subtasks
- Generate tests for multiple modules simultaneously
- Fix multiple independent bugs at once
- Refactor across independent modules

After completion, review and merge branches:

```bash
git diff main..ea/parallel/fix-css-layout-on-desktop
git merge ea/parallel/fix-css-layout-on-desktop
```

---

### `ea hook` — Pre-Push Review Hook

```bash
ea hook install                # Install pre-push review hook
ea hook uninstall              # Remove hook
ea hook install --path /other/repo
```

Automatically runs `ea review` before every `git push`. Reviews are saved to `.code-review/`.

---

## The Cursor Debug Workflow (Detailed)

This is a detailed walkthrough of the EA + Cursor debug integration.

### Scenario

You see this error in your terminal:

```
TypeError: Cannot read properties of undefined (reading 'id')
    at processOrder (/src/orders/checkout.ts:47:23)
    at handleCheckout (/src/routes/checkout.ts:15:10)
```

### Step 1: Capture and Analyze

```bash
ea debug "TypeError: Cannot read properties of undefined (reading 'id') at processOrder checkout.ts:47"
```

EA will:
- Parse file paths from the error (`checkout.ts:47`)
- Read those files from your project
- Get the git diff of recent changes
- Send everything to Kilo's debug mode (DeepSeek R1)
- Write the analysis to `.engineer-agent/debug-brief.md`

### Step 2: Review the Brief (Optional)

```bash
cat .engineer-agent/debug-brief.md
```

The brief contains:
- **Error Analysis** — what the error says vs. what it means
- **Root Cause** — the actual underlying issue
- **Relevant Files** — every file in the bug chain with line numbers
- **Recent Changes** — which git changes likely caused it
- **Suggested Fix** — exact code changes needed
- **Cursor Prompt** — ready-to-paste prompt for Cursor

### Step 3: Feed to Cursor

Open Cursor, start Agent Mode (Cmd+L or Ctrl+L), and paste:

```
Follow the debug brief in .engineer-agent/debug-brief.md to fix this bug.
```

Cursor will:
1. Read the brief
2. Navigate to the relevant files
3. Apply the suggested fix using its editor context (LSP, type checking)
4. Verify there are no new errors

### Why Not Just Use Cursor Directly?

Cursor's agent mode is excellent at applying fixes when it knows what to fix. But it lacks:
- **Codebase-wide analysis**: Cursor sees open files; EA analyzes git history, diffs, and file relationships
- **Error trace parsing**: EA extracts and reads every file mentioned in a stack trace
- **Git context**: EA knows what changed recently and correlates it with the error

By generating the debug brief first, you give Cursor a head start with expert analysis.

---

## Configuration

### Global Config

EA stores state in `~/.ea/`:
- `~/.ea/last-error.txt` — last captured terminal error (used by `--last-error`)
- `~/.ea/quota.json` — token usage tracking (future)

### Per-Project Artifacts

EA generates artifacts in each project:
- **`.engineer-agent/`** — timestamped subfolders per operation (**exact pattern** from **`make_ea_output_dir`** in **`lib/common.sh`**: `$(date +%Y%m%d_%H%M%S)_<keyword>`, e.g. `20260322_014604_plan/`). Each folder holds that run’s spec, plan, **`tasks.md`** (for Cursor loop closure), debug brief, or fix output. **Pointer files** (one line = absolute path): `latest-plan.txt`, `latest-ship-plan.txt`, `latest-fix.txt`, `latest-debug.txt`. **Convenience copies**: `last-fix.md`, `debug-brief.md`. Optional **`index.db`** from **`ea index`**. Full reference: **[docs/STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md)**.
- **`.code-review/`** — timestamped review reports

Add these to `.gitignore`:

```gitignore
.engineer-agent/
.code-review/
```

(`ea hook install` does this automatically.)

**History layout example:**

```
.engineer-agent/
├── 20260319_154512_plan/       # ea plan run
│   ├── spec.md
│   ├── architecture.md
│   ├── plan.md
│   ├── tasks.md
│   └── cursor-prompt.txt
├── 20260319_155030_fix/       # ea fix run
│   └── last-fix.md
├── 20260319_160000_debug/
│   ├── debug-brief.md
│   └── cursor-prompt.txt
├── latest-plan.txt            # path to latest plan dir
├── latest-ship-plan.txt       # path to latest ship plan dir
├── latest-fix.txt             # path to latest fix dir
├── latest-debug.txt           # path to latest debug dir
├── last-fix.md                # copy of latest fix (convenience)
├── debug-brief.md             # copy of latest debug brief (convenience)
└── index.db                   # optional: semantic index (ea index)
```

### Using EA with Projects in Other Locations

You do not need to copy EA into every repository. Use `--path`:

```bash
ea plan --req "add RBAC" --path /path/to/other-project
ea review --path /path/to/other-project
ea debug --last-error --path /path/to/other-project
```

### Forcing a Specific Backend (Gemini or Kilo)

The commands **fix**, **review**, **commit**, and **debug** support `--backend gemini` or `--backend kilo` to override automatic routing. See [Routing Matrix](#routing-matrix) and the [force-routing table](#force-routing-which-commands-support---backend) for which commands support this.

```bash
ea fix src/auth.ts --backend gemini    # Force Gemini
ea review --backend kilo               # Force Kilo
ea commit --backend gemini             # Force Gemini
ea debug "error message" --backend kilo # Force Kilo for debug analysis
```

You cannot force routing through Cursor — EA does not invoke Cursor; you use Cursor to run the instructions in `tasks.md` or `debug-brief.md`.

---

## Project Structure

```
engineer-agent/
├── ea                          # CLI entry point (bash)
├── setup.sh                    # Global install script
├── lib/
│   ├── common.sh               # Shared: call_gemini, call_kilo, route_task, make_ea_output_dir
│   ├── context-gatherer.sh     # get_planning_context, get_git_context, get_import_context
│   ├── cmd-plan.sh             # ea plan (Gemini Pro)
│   ├── cmd-review.sh           # ea review (Kilo or Gemini, auto-routed)
│   ├── cmd-fix.sh              # ea fix (Kilo Qwen3 Coder)
│   ├── cmd-debug.sh            # ea debug (Kilo analysis + Cursor bridge)
│   ├── cmd-ship.sh             # ea ship (Gemini plan + Kilo execute)
│   ├── cmd-commit.sh           # ea commit (Kilo Kimi K2)
│   ├── cmd-parallel.sh         # ea parallel (Kilo parallel agents)
│   └── cmd-hook.sh             # ea hook install/uninstall
├── prompts/
│   ├── rephrase.md             # Requirement → engineering spec
│   ├── architect.md            # Spec → Architecture Decision Record
│   ├── senior-swe.md           # Spec + ADR → implementation plan
│   ├── review.md               # Structured code review
│   ├── debug-brief.md          # Error → debug analysis for Cursor
│   └── cursor-debug.md         # Template for Cursor agent mode
├── schema/
│   └── tools.json              # Reference: typical Gemini CLI tools (not injected verbatim)
├── idea.md                     # Design document
└── README.md                   # This file
```

### Validation (E2E)

To verify tool integration, noise suppression, and sensible backend tool usage:

1. **Run plan on this repo**  
   From the engineer-agent root:  
   `ea plan "list the files in lib and summarize what each does"`  
   - Stderr should not show `keytar.node` or module-resolution noise.  
   - Context should include README (if present), repo structure, and recent git summary.  
   - Output should appear in a new timestamped folder `.engineer-agent/YYYYMMDD_HHMMSS_plan/` with `spec.md`, `plan.md`, and `tasks.md`. The model should use tools that exist in the active CLI (Gemini/Kilo), not invented names.

2. **Check prompt injection**  
   The prompt sent to Gemini/Kilo includes a short “backend-native” tool section (use your CLI’s real tools) plus **`FILE_WRITE`** block instructions for artifacts. `schema/tools.json` documents typical Gemini CLI tool names for humans; it is not pasted into the prompt as a fixed allowlist.

3. **FILE_WRITE and fix flow**  
   For `ea fix` or `ea ship` (execute phase), if the model outputs a fenced block:  
   ` ```FILE_WRITE:path/to/file `  
   followed by contents and a closing ` ``` `,  
   that file is written under the project root and a “Wrote: …” line is logged. Remaining output goes to the terminal and to the run's timestamped folder (and for fix, also to `.engineer-agent/last-fix.md`).

---

## Troubleshooting

- **`ea: command not found`** — Ensure `~/.local/bin` is in `PATH`, then restart terminal.
- **`Required command not found: gemini`** — Install Gemini CLI and confirm `gemini --help` works.
- **Kilo CLI not found** — Install: `npm install -g @kilocode/cli`. The binary is `kilo`. EA will fall back to Gemini if Kilo is missing.
- **`Not a git repository`** — Run from a git repo or pass a valid repo path with `--path`.
- **Kilo free model changed** — Run `kilo` then `/model list` to see current free models. Select with `/model select <name>`.
- **Debug brief is empty or unhelpful** — Try `ea debug --backend gemini` to use Gemini Pro instead of Kilo for the analysis.
- **Parallel agents conflict** — Each agent runs on its own branch. If branches fail to create, check for existing branches with `git branch -a | grep ea/parallel`.

---

## Quick Reference

```bash
# Planning (Gemini Pro)
ea plan "add JWT auth to the API"

# Quick fix (Kilo)
ea fix src/auth.ts
ea fix --last-error

# Debug (Kilo analysis → Cursor fix)
ea debug "TypeError: Cannot read property 'id'"
# Then in Cursor: "Follow .engineer-agent/debug-brief.md"

# Code review (Kilo or Gemini, auto-routed)
ea review
ea review --diff-args "main..feature"

# Feature shipping (Gemini plan + Kilo execute)
ea ship "add rate limiting"

# Commit message (Kilo)
ea commit

# Parallel agents (Kilo)
ea parallel "task 1" "task 2" "task 3"

# Git hook
ea hook install
```

---

**License:** MIT
