# ADR 001: EA System Documentation & Visualization Strategy

## Status
Accepted

## Context
The Engineer Agent (EA) has evolved into a multi-layered orchestration tool involving Bash, Node.js, and external LLM CLIs. The lack of structured architectural documentation hinders onboarding and makes debugging the complex "Cursor Loop" difficult. We need a system that captures high-level orchestration, command-specific logic, and data flows.

## Chosen Approach
**Markdown-first Documentation with Embedded Mermaid.js Diagrams.**

We will implement a hierarchical documentation structure in the `/docs` directory. Every major command and core component will have a corresponding Markdown file containing both explanatory text and Mermaid diagrams.

### Rationale
- **Version Control**: Docs live in the same repo as code, allowing architectural changes to be reviewed in PRs.
- **Developer-Centric**: Engineers can update diagrams as text without leaving their IDE.
- **Native Rendering**: GitHub, VS Code, and Cursor natively render Mermaid, providing a "Live Preview" experience without extra tools.
- **No Documentation Drift**: By making diagrams easy to edit, we lower the friction for keeping them up to date.

## Alternative Approaches Considered

### 1. Static Site Generator (Docusaurus/MkDocs)
- **Trade-offs**: Offers superior search and a polished UI.
- **Why Rejected**: Adds significant build-time dependencies (Node.js/Python) and maintenance overhead. The primary consumers are developers reading docs directly in the IDE or on GitHub.

### 2. Proprietary Design Tools (LucidChart/Figma)
- **Trade-offs**: High visual fidelity and easier for non-technical stakeholders.
- **Why Rejected**: Poor Git integration. Leads to "Documentation Drift" because updating a diagram requires an external account and manual export/import cycles.

## Tech Stack Recommendations
- **Content**: CommonMark Markdown (standardized formatting).
- **Diagrams**: Mermaid.js (v10+) for sequence, flow, and component diagrams.
- **Environment**: VS Code with "Markdown Preview Mermaid Support" or Cursor Pro.
- **Validation**: CI/CD check (e.g., `markdownlint`) to ensure syntax correctness.

## Folder/Module Structure
The `/docs` directory will be organized as follows:

```text
docs/
├── README.md                # Entry point and navigation map
├── ARCHITECTURE.md          # Global System Map (Hub-and-Spoke)
├── ROUTING_MATRIX.md        # Logic for Model/Backend selection
├── CONTEXT_ENGINE.md        # State aggregation & Semantic RAG details
├── STATE_MANAGEMENT.md      # .engineer-agent/ persistence layer
└── COMMANDS/                # Deep-dives into subcommand lifecycles
    ├── plan.md              # 4-step artifact generation flow
    ├── fix.md               # Quick-fix & error capture logic
    ├── index.md             # Semantic indexing (Node/SQLite) flow
    ├── ship.md              # Gemini-to-Kilo handoff visualization
    └── debug.md             # Terminal capture -> Cursor context
