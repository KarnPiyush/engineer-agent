# State Management

EA keeps **global** state under **`~/.ea/`** and **project** state under **`.engineer-agent/`** (at the project root). This directory is the **source of truth** for **loop closure** with Cursor: plans, fixes, and debug briefs land here; the IDE follows **`tasks.md`**, **`last-fix.md`**, **`debug-brief.md`**, and pointer files.

## Global: `~/.ea/`

| File / dir | Purpose |
|-------------|---------|
| `config.json` | Default model preferences, `verbose`, `dry_run`, optional `routing_rules` |
| `quota.json` | Token/call counters (best-effort, updated by `common.sh`) |
| `cache/` | Reserved for caching |
| `last-error.txt` | Optional last captured error text for `ea fix --last-error` |

Permissions: directory should be user-private (e.g. `chmod 700` on first init).

## Project: `.engineer-agent/`

Created under the **detected project root** (git toplevel or `pwd`).

### Timestamped run directories (implementation)

Folder names are created by **`make_ea_output_dir`** in **`lib/common.sh`**:

```bash
ts="$(date +%Y%m%d_%H%M%S)"
dir="$project_root/.engineer-agent/${ts}_${keyword}"
```

So the pattern is exactly:**`YYYYMMDD_HHMMSS_<keyword>`** (local time from **`date`**), e.g. **`20260322_014604_plan`**.

| Path pattern | Purpose |
|--------------|---------|
| `YYYYMMDD_HHMMSS_plan/` | `ea plan`: `spec.md`, `architecture.md`, `plan.md`, `tasks.md`, `cursor-prompt.txt`, … |
| `YYYYMMDD_HHMMSS_ship-plan/` | `ea ship` phase 1 (same style of artifacts) |
| `YYYYMMDD_HHMMSS_fix/` | `ea fix`: `last-fix.md`, … |
| `YYYYMMDD_HHMMSS_debug/` | `ea debug`: debug brief and related outputs |

### Pointer files (loop closure)

| File | Purpose |
|------|---------|
| `latest-plan.txt` | Single line: absolute path to latest **`*_plan/`** directory |
| `latest-ship-plan.txt` | Single line: latest **`*_ship-plan/`** directory |
| `latest-fix.txt` | Single line: latest **`*_fix/`** directory |
| `latest-debug.txt` | Single line: latest **`*_debug/`** directory |

Written by **`write_latest_pointer`** in **`lib/common.sh`** (e.g. **`latest-plan.txt`** from **`cmd-plan.sh`**).

### Convenience copies

| Path | Purpose |
|------|---------|
| `last-fix.md` | Copy of the most recent fix output (see **`cmd-fix.sh`**) |

### Semantic index (optional)

| Path | Purpose |
|------|---------|
| **`index.db`** | SQLite semantic index (from **`ea index`**) |
| **`index.db-wal` / `index.db-shm`** | SQLite WAL mode side files (when indexer is active) |

## Loop closure with Cursor

1. Run **`ea plan`** / **`ea ship`** / **`ea fix`** / **`ea debug`** from the repo (or **`--path`**).  
2. Open the path in **`latest-*.txt`** or the timestamped folder.  
3. In Cursor, instruct the agent to follow **`tasks.md`** (plan) or the generated brief/fix file.  
4. Re-run commands as needed; new runs create **new** timestamped dirs and update **latest** pointers.

## Environment variables (selected)

| Variable | Effect |
|----------|--------|
| `EA_VERBOSE` | Log full prompts/responses when `true` |
| `EA_DRY_RUN` | Skip destructive steps where implemented |
| `EA_SKIP_SEMANTIC` | If `1`, skip semantic RAG block in `get_planning_context` |
| `EA_SEMANTIC_LIMIT` | Max semantic chunks injected (default `5`) |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | Gemini CLI + indexer embeddings |

## What is not stored

- No cloud sync of `.engineer-agent/` by EA itself.
- Secrets should not be committed; keep `.env` out of the index (crawler respects `.gitignore`).

## Navigation (docs)

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — data flow and **`tasks.md`** bridge  
- **[COMMANDS/plan.md](COMMANDS/plan.md)** — plan artifacts  
- **[COMMANDS/fix.md](COMMANDS/fix.md)** — fix outputs  

---

*Last updated: 2026-03-22*
