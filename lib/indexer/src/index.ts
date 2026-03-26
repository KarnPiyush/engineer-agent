#!/usr/bin/env node
import { Command } from "commander";
import path from "node:path";
import fs from "node:fs";
import { runIndex, runSearch } from "./index-engine.js";

const program = new Command();
program.name("ea-indexer").description("Local semantic index for engineer-agent").version("0.1.0");

program
  .command("index")
  .description("Build or update the semantic index")
  .requiredOption("--root <dir>", "Project root (absolute)")
  .option("--db <path>", "SQLite database path", "")
  .option("--force", "Re-embed all files", false)
  .option("--quiet", "No progress on stderr (JSON stdout only)", false)
  .option("--exclude <pattern>", "Extra glob to exclude (repeatable)", collect, [] as string[])
  .action(async (opts: { root: string; db: string; force: boolean; exclude: string[]; quiet: boolean }) => {
    if (opts.quiet) {
      process.env.EA_INDEX_QUIET = "1";
    }
    const rootAbs = path.resolve(opts.root);
    const dbPath =
      opts.db && opts.db.length > 0
        ? path.resolve(opts.db)
        : path.join(rootAbs, ".engineer-agent", "index.db");
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    const r = await runIndex(rootAbs, dbPath, opts.force, opts.exclude);
    console.log(JSON.stringify({ ok: true, ...r }, null, 2));
    if (r.errors.length) {
      process.exitCode = 1;
    }
  });

program
  .command("search")
  .description("Semantic search (JSON hits to stdout)")
  .requiredOption("--root <dir>", "Project root")
  .argument("<query>", "Natural language query")
  .option("--db <path>", "SQLite database path", "")
  .option("--limit <n>", "Top K", "8")
  .action(async (query: string, opts: { root: string; db: string; limit: string }) => {
    const rootAbs = path.resolve(opts.root);
    const dbPath =
      opts.db && opts.db.length > 0
        ? path.resolve(opts.db)
        : path.join(rootAbs, ".engineer-agent", "index.db");
    const k = Math.max(1, parseInt(opts.limit, 10) || 8);
    const hits = await runSearch(rootAbs, dbPath, query, k);
    console.log(JSON.stringify({ hits }));
  });

function collect(v: string, prev: string[]): string[] {
  prev.push(v);
  return prev;
}

program.parse();
