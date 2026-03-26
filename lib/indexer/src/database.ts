import Database from "better-sqlite3";
import path from "node:path";

export type ChunkRow = {
  id: number;
  file_id: number;
  path: string;
  ordinal: number;
  start_line: number;
  end_line: number;
  content: string;
  dim: number;
  embedding: Float32Array;
};

let singleton: Database.Database | null = null;

export function openDatabase(dbPath: string): Database.Database {
  if (singleton && singleton.name === path.resolve(dbPath)) {
    return singleton;
  }
  if (singleton) {
    singleton.close();
  }
  singleton = new Database(dbPath);
  singleton.pragma("journal_mode = WAL");
  singleton.pragma("foreign_keys = ON");
  migrate(singleton);
  return singleton;
}

function migrate(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      hash TEXT NOT NULL,
      mtime INTEGER,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_id INTEGER NOT NULL,
      ordinal INTEGER NOT NULL,
      start_line INTEGER NOT NULL,
      end_line INTEGER NOT NULL,
      content TEXT NOT NULL,
      dim INTEGER NOT NULL,
      embedding BLOB NOT NULL,
      FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file_id);
  `);
}

export function deleteChunksForFile(db: Database.Database, fileId: number): void {
  db.prepare("DELETE FROM chunks WHERE file_id = ?").run(fileId);
}

export function upsertFile(
  db: Database.Database,
  relPath: string,
  hash: string,
  mtime: number
): number {
  const now = Date.now();
  db.prepare(
    `INSERT INTO files (path, hash, mtime, updated_at) VALUES (?, ?, ?, ?)
     ON CONFLICT(path) DO UPDATE SET hash = excluded.hash, mtime = excluded.mtime, updated_at = excluded.updated_at`
  ).run(relPath, hash, mtime, now);
  const r = db.prepare("SELECT id FROM files WHERE path = ?").get(relPath) as { id: number };
  return r.id;
}

export function insertChunk(
  db: Database.Database,
  fileId: number,
  ordinal: number,
  startLine: number,
  endLine: number,
  content: string,
  embedding: Float32Array
): void {
  const dim = embedding.length;
  const buf = Buffer.from(embedding.buffer, embedding.byteOffset, embedding.byteLength);
  db.prepare(
    `INSERT INTO chunks (file_id, ordinal, start_line, end_line, content, dim, embedding)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(fileId, ordinal, startLine, endLine, content, dim, buf);
}

export function listAllChunksWithEmbeddings(db: Database.Database): ChunkRow[] {
  const rows = db
    .prepare(
      `SELECT c.id, c.file_id, f.path, c.ordinal, c.start_line, c.end_line, c.content, c.dim, c.embedding
       FROM chunks c JOIN files f ON f.id = c.file_id`
    )
    .all() as Array<{
    id: number;
    file_id: number;
    path: string;
    ordinal: number;
    start_line: number;
    end_line: number;
    content: string;
    dim: number;
    embedding: Buffer;
  }>;

  return rows.map((r) => ({
    id: r.id,
    file_id: r.file_id,
    path: r.path,
    ordinal: r.ordinal,
    start_line: r.start_line,
    end_line: r.end_line,
    content: r.content,
    dim: r.dim,
    embedding: new Float32Array(r.embedding.buffer, r.embedding.byteOffset, r.embedding.byteLength / 4),
  }));
}

export function deleteFileByPath(db: Database.Database, relPath: string): void {
  db.prepare("DELETE FROM files WHERE path = ?").run(relPath);
}

export function closeDatabase(): void {
  if (singleton) {
    singleton.close();
    singleton = null;
  }
}
