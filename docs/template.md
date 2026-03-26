# Documentation Template

Use this when adding or refreshing docs under **`docs/`** or **`docs/COMMANDS/`**.

## Front matter (optional)

- **Title** — H1 matching the command or module name  
- **Last updated** — Date at bottom  

## Sections to include

1. **Purpose** — What the reader will learn.  
2. **Usage** — Exact `ea …` invocations with common flags.  
3. **Workflow** — Diagram (mermaid) or numbered steps.  
4. **Artifacts / state** — Paths under `.engineer-agent/` or `~/.ea/`.  
5. **Routing / dependencies** — Gemini vs Kilo vs Node indexer.  
6. **Edge cases** — Errors, fallbacks, env vars (`EA_SKIP_SEMANTIC`, etc.).  
7. **Related files** — Pointers to `lib/*.sh`, `lib/indexer/`, `prompts/`.

## Related docs

| Topic | File |
|-------|------|
| Architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Context + RAG | [CONTEXT_ENGINE.md](CONTEXT_ENGINE.md), [SEMANTIC_INDEXING.md](SEMANTIC_INDEXING.md) |
| Routing | [ROUTING_MATRIX.md](ROUTING_MATRIX.md) |
| State | [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) |
| Prompts | [PROMPT_ENGINEERING.md](PROMPT_ENGINEERING.md) |

## Example

```bash
ea plan "short requirement"
ea index
ea index search "where is routing defined"
```

---

*Last updated: 2026-03-22*
