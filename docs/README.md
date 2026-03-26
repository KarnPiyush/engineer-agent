# Engineer Agent — Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System overview, data flow, Cursor bridge, modules, indexer |
| [CONTEXT_ENGINE.md](CONTEXT_ENGINE.md) | Aggregation, `get_planning_context`, semantic RAG, caps |
| [SEMANTIC_INDEXING.md](SEMANTIC_INDEXING.md) | `ea index`, SQLite, embeddings, limitations |
| [PROMPT_ENGINEERING.md](PROMPT_ENGINEERING.md) | Templates, `FILE_WRITE`, prompt injection |
| [ROUTING_MATRIX.md](ROUTING_MATRIX.md) | `resolve_model`, `route_task`, Gemini vs Kilo vs embeddings |
| [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) | `~/.ea/`, `.engineer-agent/`, loop closure, timestamps |
| [template.md](template.md) | How to write new docs |

## Commands (`docs/COMMANDS/`)

| Document | Command |
|----------|---------|
| [COMMANDS/plan.md](COMMANDS/plan.md) | `ea plan` |
| [COMMANDS/ship.md](COMMANDS/ship.md) | `ea ship` |
| [COMMANDS/fix.md](COMMANDS/fix.md) | `ea fix` |
| [COMMANDS/debug.md](COMMANDS/debug.md) | `ea debug` |
| [COMMANDS/index.md](COMMANDS/index.md) | `ea index` |

**Reading order:** **[ARCHITECTURE.md](ARCHITECTURE.md)** → **[STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)** → command pages as needed.

The main project **[README.md](../README.md)** covers installation, quickstart, and end-to-end usage.

---

*Last updated: 2026-03-22*
