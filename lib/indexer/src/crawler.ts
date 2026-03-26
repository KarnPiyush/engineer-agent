import fs from "node:fs";
import path from "node:path";
import fg from "fast-glob";

/**
 * Paths we never index: dependency installs, virtualenvs, build caches.
 * Still merged with root `.gitignore` and `--exclude` CLI patterns.
 */
const DEFAULT_IGNORE = [
  "**/.git/**",
  "**/.engineer-agent/**",

  // JS/TS (and common JS package dirs)
  "**/node_modules/**",
  "**/bower_components/**",
  "**/.pnpm-store/**",
  "**/.yarn/cache/**",

  // Python: virtualenvs + site-packages + packaging metadata
  "**/__pycache__/**",
  "**/.venv/**",
  "**/venv/**",
  "**/site-packages/**",
  "**/.tox/**",
  "**/.eggs/**",
  "**/*.egg-info/**",
  "**/pip-wheel-metadata/**",

  // Elixir / Erlang
  "**/deps/**",
  "**/_build/**",

  // Haskell Stack
  "**/.stack-work/**",

  // iOS / CocoaPods
  "**/Pods/**",

  // Generic build output & third-party trees (Ruby bundle, Go modules, Rust)
  "**/dist/**",
  "**/build/**",
  "**/.next/**",
  "**/vendor/**",
  "**/target/**",

  "**/*.min.js",
];

function readGitignorePatterns(root: string): string[] {
  const gitignorePath = path.join(root, ".gitignore");
  if (!fs.existsSync(gitignorePath)) return [];
  const raw = fs.readFileSync(gitignorePath, "utf8");
  return raw
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
}

export async function listSourceFiles(root: string, extraExclude: string[] = []): Promise<string[]> {
  const ignore = [...DEFAULT_IGNORE, ...readGitignorePatterns(root), ...extraExclude];

  const entries = await fg(["**/*"], {
    cwd: root,
    dot: false,
    onlyFiles: true,
    absolute: false,
    followSymbolicLinks: false,
    ignore,
  });

  return entries.map((e) => e.split(path.sep).join("/")).sort();
}

export function isProbablyText(relPath: string): boolean {
  const ext = path.extname(relPath).toLowerCase();
  const ok = new Set([
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
    ".json",
    ".md",
    ".sh",
    ".bash",
    ".py",
    ".go",
    ".rs",
    ".toml",
    ".yaml",
    ".yml",
    ".css",
    ".html",
    ".txt",
  ]);
  if (ok.has(ext)) return true;
  if (!ext && path.basename(relPath) === "Dockerfile") return true;
  return false;
}
