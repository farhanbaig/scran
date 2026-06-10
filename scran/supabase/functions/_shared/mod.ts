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

export async function callGeminiJSON(model: string, systemPrompt: string, imageBase64: string): Promise<string> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new Error("GEMINI_API_KEY not configured");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ inlineData: { mimeType: "image/jpeg", data: imageBase64 } }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0 },
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`gemini ${res.status}: ${t.slice(0, 300)}`);
  }
  const body = await res.json();
  return body?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}
