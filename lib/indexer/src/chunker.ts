/**
 * Language-aware chunking: regex/heuristic boundaries (functions, classes, defs).
 * Falls back to sliding windows for unstructured files (per tasks.md edge cases).
 */

const MAX_CHUNK_CHARS = 8000;
const OVERLAP_CHARS = 400;
const MIN_CHUNK_CHARS = 200;

export type TextChunk = {
  content: string;
  startLine: number;
  endLine: number;
};

function lineAt(s: string, idx: number): number {
  return s.slice(0, idx).split("\n").length;
}

/** Split on blank lines + common code boundaries */
const BOUNDARY_RE =
  /(?:\n\n|\n(?=(?:export\s+)?(?:async\s+)?function\s|\n(?:export\s+)?class\s|\n(?:export\s+)?(?:const|let|var)\s|\ndef\s|\nasync\s+def\s|\nfunc\s|\n(?:pub\s+)?fn\s))/g;

export function chunkSource(content: string, filePath: string): TextChunk[] {
  const ext = filePath.split(".").pop()?.toLowerCase() ?? "";
  const langLike = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "sh", "bash", "md"].includes(ext);

  if (!langLike || content.length < MIN_CHUNK_CHARS) {
    return slidingWindowChunks(content);
  }

  const parts: TextChunk[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  const re = new RegExp(BOUNDARY_RE.source, "g");
  while ((m = re.exec(content)) !== null) {
    const end = m.index + 1;
    const slice = content.slice(last, end).trimEnd();
    if (slice.length >= MIN_CHUNK_CHARS) {
      parts.push({
        content: slice,
        startLine: lineAt(content, last),
        endLine: lineAt(content, end),
      });
    }
    last = end;
  }
  const tail = content.slice(last).trimEnd();
  if (tail.length > 0) {
    parts.push({
      content: tail,
      startLine: lineAt(content, last),
      endLine: lineAt(content, content.length),
    });
  }

  const merged: TextChunk[] = [];
  for (const p of parts) {
    if (p.content.length > MAX_CHUNK_CHARS) {
      merged.push(...splitOversized(p.content, p.startLine));
    } else {
      merged.push(p);
    }
  }
  return merged.length > 0 ? merged : slidingWindowChunks(content);
}

function splitOversized(content: string, baseLine: number): TextChunk[] {
  const out: TextChunk[] = [];
  let i = 0;
  let offset = 0;
  while (offset < content.length) {
    let end = Math.min(offset + MAX_CHUNK_CHARS, content.length);
    if (end < content.length) {
      const slice = content.slice(offset, end);
      const lastNl = slice.lastIndexOf("\n");
      if (lastNl > MAX_CHUNK_CHARS / 2) end = offset + lastNl + 1;
    }
    const chunk = content.slice(offset, end);
    const startLine = baseLine + content.slice(0, offset).split("\n").length - 1;
    const endLine = baseLine + content.slice(0, end).split("\n").length - 1;
    out.push({ content: chunk.trim(), startLine, endLine });
    offset = end - OVERLAP_CHARS;
    if (offset <= i) offset = end;
    i++;
    if (i > 10000) break;
  }
  return out;
}

function slidingWindowChunks(content: string): TextChunk[] {
  const out: TextChunk[] = [];
  let offset = 0;
  const totalLines = content.split("\n").length;
  while (offset < content.length) {
    const end = Math.min(offset + MAX_CHUNK_CHARS, content.length);
    const chunk = content.slice(offset, end);
    const startLine = content.slice(0, offset).split("\n").length;
    const endLine = content.slice(0, end).split("\n").length;
    out.push({ content: chunk.trim(), startLine, endLine });
    if (end >= content.length) break;
    const next = end - OVERLAP_CHARS;
    offset = next > offset ? next : end;
    if (out.length > 5000) break;
  }
  return out.length > 0
    ? out
    : [{ content: content.slice(0, MAX_CHUNK_CHARS), startLine: 1, endLine: Math.max(1, totalLines) }];
}
