# Routing Matrix

Backend selection for LLM tasks is implemented in **`lib/model-router.sh`** (`resolve_model`, `map_model_to_backend`, `call_model`, `route_task`). **`ea index`** does **not** use this router for chat models — it runs a **separate Node.js** process that calls the **Gemini Embeddings API** only.

## `call_model`: resolution flowchart

Commands that pass a user model (e.g. **`--model`**) call **`call_model TASK_TYPE PROMPT [USER_MODEL_OVERRIDE]`**. Resolution order:

```mermaid
flowchart TD
  START([call_model]) --> O{User override<br/>non-empty?}
  O -->|yes| R1[Use override as resolved_model]
  O -->|no| P[resolve_model: project .ea-config.json<br/>or .ea.json via jq]
  P -->|model_preferences.task_type| R2[Use project task model]
  P -->|model_preferences.default| R3[Use project default]
  P -->|none| G[read_ea_config global<br/>~/.ea/config.json]
  G -->|model_preferences.task| R4[Use global task model]
  G -->|none| R5[resolved_model = auto]
  R1 --> MAP[map_model_to_backend]
  R2 --> MAP
  R3 --> MAP
  R4 --> MAP
  R5 --> MAP
  MAP --> B{backend?}
  B -->|gemini| CG[call_gemini]
  B -->|kilo| CK[call_kilo]
  B -->|auto| RT[route_task TASK_TYPE PROMPT]
  B -->|unknown| ERR[Error: unknown model]
```

**Note:** **`resolve_model`** reads project config using **`get_project_config "$(pwd)"`** — i.e. **current working directory**, not always an explicit **`--path`**. Prefer running **`ea`** from the project root or **`cd`** there when using **`.ea-config.json`**.

## `route_task`: preferred backend + CLI fallbacks

When **`resolved_model`** is **`auto`** (or routing bypasses **`call_model`** and calls **`route_task`** directly), **`lib/common.sh`** chooses backend by **task type**, then checks **`has_gemini` / `has_kilo`**:

```mermaid
flowchart TD
  T([route_task task_type]) --> PT{task_type}
  PT -->|plan / architect| PG{has_gemini?}
  PG -->|yes| G1[call_gemini]
  PG -->|no| PK1{has_kilo?}
  PK1 -->|yes| K1[call_kilo architect]
  PK1 -->|no| E1[error]
  PT -->|fix| PF{has_kilo?}
  PF -->|yes| K2[call_kilo code]
  PF -->|no| PG2{has_gemini?}
  PG2 -->|yes| G2[call_gemini fallback]
  PG2 -->|no| E2[error]
  PT -->|debug| PF2{has_kilo?}
  PF2 -->|yes| KD[call_kilo_debug]
  PF2 -->|no| PG3{has_gemini?}
  PG3 -->|yes| G3[call_gemini fallback]
  PG3 -->|no| E3[error]
  PT -->|review| RV[diff size + CLI availability]
  RV --> REND[Prefer Kilo or Gemini per route_task]
  PT -->|ship-plan / ship-execute / commit / parallel| MORE[Same pattern: prefer one CLI, fallback to other]
```

**Fallback summary:** If the **preferred** CLI is missing, EA tries the **other** when the task allows it (see **`route_task`** cases in **`lib/common.sh`**). If **neither** exists → error with install hint.

## Embeddings (`ea index`)

- **Not** routed through **`route_task`**.  
- Implemented in **`lib/indexer/`** (TypeScript): **`gemini-embedding-001`** (default; **`EA_EMBEDDING_MODEL`**) via Google Generative Language API.  
- Requires **`GEMINI_API_KEY`** or **`GOOGLE_API_KEY`** in the environment.

## Config extras

- **`.ea-config.json`** / **`.ea.json`** may define **`routing_rules`** (e.g. **`file_size_gt`**) in **`apply_routing_rules`** — today **`call_model`** does **not** invoke **`apply_routing_rules`**; rules are available for extension.  
- **`~/.ea/config.json`** holds global **`model_preferences`** read by **`resolve_model`**.

## Custom routing rules

`~/.ea/config.json` (or project config) may define `routing_rules`. See **`lib/model-router.sh`** for supported rule types.

---

*Last updated: 2026-03-22*
