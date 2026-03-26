/** Gemini embeddings via REST (`batchEmbedContents`). Default model matches current Generative Language API. */

const DEFAULT_EMBED_MODEL = "models/gemini-embedding-001";

export function getEmbedModel(): string {
  const raw = (process.env.EA_EMBEDDING_MODEL ?? DEFAULT_EMBED_MODEL).trim();
  if (!raw) return DEFAULT_EMBED_MODEL;
  return raw.startsWith("models/") ? raw : `models/${raw}`;
}

export function getApiKey(): string {
  const k = process.env.GEMINI_API_KEY ?? process.env.GOOGLE_API_KEY ?? "";
  return k.trim();
}

export function isIndexQuiet(): boolean {
  return process.env.EA_INDEX_QUIET === "1";
}

async function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Prefer API "retry in Ns" hint for 429; otherwise exponential backoff. */
function backoffMsAfterFailure(err: Error, attempt: number): number {
  const msg = err.message;
  if (msg.includes("embed HTTP 429") || msg.includes("RESOURCE_EXHAUSTED")) {
    const m = msg.match(/[Rr]etry in ([\d.]+)\s*s/);
    if (m) {
      const sec = Math.ceil(parseFloat(m[1]!));
      return Math.min(120_000, Math.max(1_000, sec * 1000));
    }
    return Math.min(120_000, 8_000 * attempt);
  }
  return 500 * 2 ** attempt;
}

export async function embedTexts(
  texts: string[],
  role: "document" | "query"
): Promise<Float32Array[]> {
  if (texts.length === 0) return [];
  const apiKey = getApiKey();
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY or GOOGLE_API_KEY is not set");
  }
  const embedModel = getEmbedModel();
  const taskType = role === "query" ? "CODE_RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT";
  const url = `https://generativelanguage.googleapis.com/v1beta/${embedModel}:batchEmbedContents?key=${encodeURIComponent(apiKey)}`;

  const batchSize = 50;
  const all: Float32Array[] = [];
  const quiet = isIndexQuiet();
  const total = texts.length;
  for (let i = 0; i < texts.length; i += batchSize) {
    const slice = texts.slice(i, i + batchSize);
    if (!quiet) {
      console.error(
        `[ea-index] embedding API batch ${Math.min(i + 1, total)}–${Math.min(i + slice.length, total)} of ${total} chunk(s)…`
      );
    }
    let attempt = 0;
    let lastErr: Error | null = null;
    while (attempt < 5) {
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requests: slice.map((text) => ({
              model: embedModel,
              content: { parts: [{ text }] },
              taskType,
            })),
          }),
        });
        if (!res.ok) {
          const t = await res.text();
          throw new Error(`embed HTTP ${res.status}: ${t.slice(0, 500)}`);
        }
        const json = (await res.json()) as {
          embeddings?: Array<{ values?: number[] }>;
        };
        const emb = json.embeddings;
        if (!emb || emb.length !== slice.length) {
          throw new Error("batchEmbedContents: unexpected response shape");
        }
        for (const e of emb) {
          const vals = e.values;
          if (!vals?.length) throw new Error("missing embedding values");
          all.push(Float32Array.from(vals));
        }
        break;
      } catch (e) {
        lastErr = e instanceof Error ? e : new Error(String(e));
        attempt++;
        await sleep(backoffMsAfterFailure(lastErr, attempt));
      }
    }
    if (attempt >= 5 && lastErr) throw lastErr;
  }
  return all;
}

export async function embedQuery(q: string): Promise<Float32Array> {
  const [v] = await embedTexts([q], "query");
  return v;
}
