import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  closeDatabase,
  deleteChunksForFile,
  insertChunk,
  listAllChunksWithEmbeddings,
  openDatabase,
  upsertFile,
} from "./database.js";
import { chunkSource } from "./chunker.js";
import { embedQuery, embedTexts, getApiKey, isIndexQuiet } from "./embeddings.js";
import { isProbablyText, listSourceFiles } from "./crawler.js";
import { searchTopK, type SearchHit } from "./search.js";

/** Skip very large files to avoid multi-minute single-file embeds */
const MAX_FILE_BYTES = 512 * 1024;

function logProgress(msg: string): void {
  if (!isIndexQuiet()) {
    console.error(msg);
  }
}

export async function runIndex(
  rootAbs: string,
  dbPath: string,
  force: boolean,
  extraExclude: string[] = []
): Promise<{ indexed: number; skipped: number; errors: string[] }> {
  if (!getApiKey()) {
    throw new Error("Set GEMINI_API_KEY or GOOGLE_API_KEY for embeddings");
  }

  const db = openDatabase(dbPath);
  const errors: string[] = [];
  const files = await listSourceFiles(rootAbs, extraExclude);

  logProgress(
    `[ea-index] Scanned ${files.length} file path(s). Embedding changed files (first full index can take many minutes).`
  );
  logProgress(`[ea-index] Tip: progress lines are on stderr; set EA_INDEX_QUIET=1 to hide them.`);

  const hashStmt = db.prepare("SELECT hash FROM files WHERE path = ?");
  let indexed = 0;
  let skipped = 0;

  for (const rel of files) {
    if (!isProbablyText(rel)) {
      skipped++;
      continue;
    }
    const full = path.join(rootAbs, rel);
    let stat: fs.Stats;
    try {
      stat = fs.statSync(full);
    } catch {
      skipped++;
      continue;
    }
    if (!stat.isFile()) {
      skipped++;
      continue;
    }
    if (stat.size > MAX_FILE_BYTES) {
      skipped++;
      continue;
    }

    let content: string;
    try {
      content = fs.readFileSync(full, "utf8");
    } catch (e) {
      errors.push(`${rel}: ${e}`);
      skipped++;
      continue;
    }

    const hash = createHash("sha256").update(content).digest("hex");
    const prev = hashStmt.get(rel) as { hash: string } | undefined;
    if (!force && prev && prev.hash === hash) {
      skipped++;
      continue;
    }

    try {
      const fileId = upsertFile(db, rel, hash, Math.floor(stat.mtimeMs));
      deleteChunksForFile(db, fileId);
      const chunks = chunkSource(content, rel);
      if (chunks.length === 0) {
        skipped++;
        continue;
      }
      logProgress(`[ea-index] → ${rel} (${chunks.length} chunk(s))`);
      const texts = chunks.map((c) => c.content);
      const embeddings = await embedTexts(texts, "document");
      if (embeddings.length !== chunks.length) {
        throw new Error("embedding count mismatch");
      }
      for (let i = 0; i < chunks.length; i++) {
        const ch = chunks[i]!;
        const emb = embeddings[i]!;
        insertChunk(db, fileId, i, ch.startLine, ch.endLine, ch.content, emb);
      }
      indexed++;
      logProgress(`[ea-index] ✓ ${rel}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      errors.push(`${rel}: ${msg}`);
    }
  }

  closeDatabase();
  logProgress(
    `[ea-index] Done. filesIndexed=${indexed} filesSkippedOrUnchanged=${skipped} errors=${errors.length}`
  );
  return { indexed, skipped, errors };
}

export async function runSearch(
  rootAbs: string,
  dbPath: string,
  query: string,
  topK: number
): Promise<SearchHit[]> {
  if (!fs.existsSync(dbPath)) {
    return [];
  }
  if (!getApiKey()) {
    throw new Error("Set GEMINI_API_KEY or GOOGLE_API_KEY for query embedding");
  }

  const db = openDatabase(dbPath);
  const rows = listAllChunksWithEmbeddings(db);
  closeDatabase();

  if (rows.length === 0) return [];

  const qEmb = await embedQuery(query);
  return searchTopK(qEmb, rows, topK);
}
