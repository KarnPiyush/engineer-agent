# ADR 002: Structural and Incremental Indexing for Engineer-Agent (EA)

## Status
Proposed

## Context
The current `ea index` implementation relies on a heuristic, chunk-based RAG (Retrieval-Augmented Generation) system implemented in Node.js. While functional for simple search, it lacks the structural depth (relationships between functions, classes, and files) and incremental efficiency required for complex refactoring tasks in large repositories.

## Decision: Hybrid Python-Bash Structural Indexing
We will migrate the indexing engine from the current Node.js chunker to a structural knowledge graph powered by the `code-review-graph` Python engine.

### 1. Chosen approach and why
**Hybrid Python-Bash Structural Indexing with `code-review-graph`**

The recommended solution is to unify the `ea index` command with the `code-review-graph` logic. The Bash CLI will remain the primary entry point to maintain the "zero-overhead" user experience, while the heavy lifting of parsing and graph analysis is delegated to Python.

**Rationale**:
- **Semantic Depth**: Utilizing `tree-sitter` allows for precise extraction of code entities and their relationships, enabling features like "Find callers of X" or "Find tests for Y".
- **Incremental Performance**: By using git-aware change detection and file hashing, the system can update the graph in sub-second time for individual file changes.
- **Advanced Graph Algorithms**: Leverage `NetworkX` for PageRank (finding important code) and community detection (understanding architecture), which are non-trivial to implement in Bash or Node.js.

### 2. Alternative approaches considered

#### Alternative A: Enhanced Node.js Indexer
*   **Description**: Upgrade the existing `lib/indexer` by adding `tree-sitter` Node.js bindings.
*   **Trade-offs**: Keeps the stack simpler (Node + Bash) but requires re-implementing complex graph logic and synchronization patterns already solved in `code-review-graph`. Node.js native modules can also be difficult to distribute across diverse environments.

#### Alternative B: External Graph Database (e.g., Neo4j)
*   **Description**: Require users to run a graph database service.
*   **Trade-offs**: Provides superior query power but violates EA's "local-first, zero-setup" principle. SQLite (used by `code-review-graph`) offers a better balance of power and simplicity for a CLI tool.

### 3. Tech stack recommendations
*   **Runtime**: Python 3.10+ (managed via an internal virtualenv created on first run).
*   **Parsing**: `tree-sitter` with `tree-sitter-language-pack` for multi-language support (Python, JS/TS, Go, Java, etc.).
*   **Graph Engine**: `NetworkX` for in-memory graph operations.
*   **Database**: `SQLite 3` with `FTS5` for text search and `sqlite-vec` for vector similarity.
*   **Embeddings**: Google Gemini API (`text-embedding-004`).
*   **Bridge**: `subprocess` calls from Bash to the `code-review-graph` CLI.

### 4. Folder/module structure
The implementation will integrate the `code-review-graph` subdirectory as the core engine.

```text
engineer-agent/
├── ea                    # Main Bash entry point
├── lib/
│   ├── cmd-index.sh      # Bridges 'ea index' -> 'code-review-graph build/update'
│   ├── context-gatherer.sh # Queries graph for "Impact Radius" and "Related Nodes"
│   └── common.sh         # Handles Python environment / venv setup
├── code-review-graph/    # Core Python indexing engine
│   ├── code_review_graph/
│   │   ├── graph.py      # SQLite storage and Graph abstraction
│   │   ├── parser.py     # Multi-language Tree-sitter parsing
│   │   └── search.py     # Hybrid FTS + Vector + Graph search
└── .engineer-agent/
    └── index.db          # Unified SQLite database
