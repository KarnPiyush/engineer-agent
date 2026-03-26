import type { ChunkRow } from "./database.js";

export function cosineSimilarity(a: Float32Array, b: Float32Array): number {
  if (a.length !== b.length) return -1;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i]! * b[i]!;
    na += a[i]! * a[i]!;
    nb += b[i]! * b[i]!;
  }
  const d = Math.sqrt(na) * Math.sqrt(nb);
  return d === 0 ? 0 : dot / d;
}

export type SearchHit = {
  path: string;
  startLine: number;
  endLine: number;
  score: number;
  content: string;
};

export function searchTopK(
  queryEmbedding: Float32Array,
  chunks: ChunkRow[],
  k: number,
  minScore = 0.25
): SearchHit[] {
  const scored: SearchHit[] = [];
  for (const c of chunks) {
    if (c.embedding.length !== queryEmbedding.length) continue;
    const score = cosineSimilarity(queryEmbedding, c.embedding);
    if (score < minScore) continue;
    scored.push({
      path: c.path,
      startLine: c.start_line,
      endLine: c.end_line,
      score,
      content: c.content,
    });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, k);
}
