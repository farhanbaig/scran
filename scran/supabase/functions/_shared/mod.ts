// Shared helpers for Scran edge functions.
// NOTE: the live deployment inlines a copy of this file inside scan-label and
// scan-plate (as ./_shared.ts). This is the canonical source — to redeploy with
// the CLI, the functions import it via ../_shared/mod.ts.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function newRequestId(): string {
  return crypto.randomUUID();
}

const buckets = new Map<string, number[]>();
export function rateLimited(userId: string, limit = 10, windowMs = 60_000): boolean {
  const now = Date.now();
  const arr = (buckets.get(userId) ?? []).filter((t) => now - t < windowMs);
  if (arr.length >= limit) { buckets.set(userId, arr); return true; }
  arr.push(now); buckets.set(userId, arr); return false;
}

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

export async function getUser(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!token) return null;
  const { data, error } = await serviceClient().auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

export async function isPro(appUserId: string): Promise<boolean> {
  const key = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!key) return false;
  try {
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${appUserId}`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    if (!res.ok) return false;
    const body = await res.json();
    const ent = body?.subscriber?.entitlements?.pro;
    if (!ent) return false;
    if (!ent.expires_date) return true;
    return new Date(ent.expires_date).getTime() > Date.now();
  } catch {
    return false;
  }
}

export const FREE_DAILY_SCANS = 3;

export async function scansUsedToday(sb: SupabaseClient, userId: string): Promise<number> {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  const { count } = await sb
    .from("ai_scan_events")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", start.toISOString());
  return count ?? 0;
}

export async function recordScan(sb: SupabaseClient, userId: string, kind: "label" | "plate") {
  await sb.from("ai_scan_events").insert({ user_id: userId, kind });
}

export function cleanBase64(input: string): string {
  const comma = input.indexOf(",");
  const body = input.startsWith("data:") && comma >= 0 ? input.slice(comma + 1) : input;
  return body.replace(/\s/g, "");
}

// Pinned default. "-latest" aliases are a production hazard: Google repoints
// them to newer models whose latency/thinking behaviour breaks our timeout
// budget (this took scan-plate down). Override per-function via env if needed.
export const GEMINI_DEFAULT_MODEL = "gemini-2.5-flash";

export class GeminiError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}

// Pull model text out of a generateContent response, skipping "thought" parts
// (thinking models put reasoning in parts marked thought:true; the answer may
// not be parts[0]).
function candidateText(body: Record<string, unknown>): string {
  // deno-lint-ignore no-explicit-any
  const cand = (body as any)?.candidates?.[0];
  const parts: Array<{ text?: string; thought?: boolean }> = cand?.content?.parts ?? [];
  return parts
    .filter((p) => typeof p.text === "string" && p.thought !== true)
    .map((p) => p.text as string)
    .join("");
}

// Vision call returning raw model text. Thinking is disabled for speed; if the
// model rejects that parameter we drop it and continue. Retries once on 5xx /
// network / timeout (never on other 4xx). Per-attempt hard timeout keeps two
// attempts inside the app's 45s client window. `userText` adds an optional text
// part next to the image (used for plate-scan corrections).
export async function callGeminiJSON(
  model: string, systemPrompt: string, imageBase64: string,
  userText: string | null = null, perAttemptMs = 18_000,
): Promise<string> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new GeminiError(0, "GEMINI_API_KEY not configured");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  const userParts: unknown[] = [{ inlineData: { mimeType: "image/jpeg", data: imageBase64 } }];
  if (userText) userParts.push({ text: userText });
  const payload = (disableThinking: boolean) => ({
    systemInstruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts: userParts }],
    generationConfig: {
      responseMimeType: "application/json",
      temperature: 0,
      maxOutputTokens: 4096,
      ...(disableThinking ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
    },
  });

  let lastStatus = 0;
  let lastErr = "unknown";
  let disableThinking = true;
  for (let attempt = 0; attempt < 2; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), perAttemptMs);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload(disableThinking)),
        signal: controller.signal,
      });
      if (res.ok) {
        const body = await res.json();
        const text = candidateText(body);
        if (text) return text;
        // deno-lint-ignore no-explicit-any
        const finish = (body as any)?.candidates?.[0]?.finishReason ?? "?";
        lastStatus = 200;
        lastErr = `empty candidate (finishReason=${finish}): ` + JSON.stringify(body).slice(0, 160);
      } else {
        lastStatus = res.status;
        lastErr = (await res.text()).slice(0, 220);
        // Model doesn't accept thinkingConfig — drop it and retry immediately.
        if (res.status === 400 && disableThinking && lastErr.toLowerCase().includes("thinking")) {
          disableThinking = false;
          clearTimeout(timer);
          attempt--;
          continue;
        }
        if (res.status >= 400 && res.status < 500 && res.status !== 429) break;
      }
    } catch (e) {
      lastErr = String(e);
    } finally {
      clearTimeout(timer);
    }
    if (attempt === 0) await new Promise((r) => setTimeout(r, 300));
  }
  throw new GeminiError(lastStatus, lastErr);
}

// Tolerant JSON extraction: strips code fences and pulls the first {...} block.
// deno-lint-ignore no-explicit-any
export function extractJSON(text: string): any | null {
  let t = text.trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```[a-zA-Z]*\s*/, "").replace(/```\s*$/, "");
  }
  try { return JSON.parse(t); } catch { /* fall through */ }
  const first = t.indexOf("{");
  const last = t.lastIndexOf("}");
  if (first >= 0 && last > first) {
    try { return JSON.parse(t.slice(first, last + 1)); } catch { /* ignore */ }
  }
  return null;
}

export function num(v: unknown, def: number | null = null): number | null {
  if (v === null || v === undefined || v === "") return def;
  const n = typeof v === "string" ? parseFloat(v) : (v as number);
  return typeof n === "number" && isFinite(n) ? n : def;
}
