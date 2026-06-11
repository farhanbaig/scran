// scan-label — hero feature. Reads a UK nutrition label via Gemini Flash,
// returns strict per-100g JSON. Enforces the free-tier AI scan quota server-side.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { z } from "npm:zod@3.23.8";
import {
  callGeminiJSON, cleanBase64, corsHeaders, extractJSON, FREE_DAILY_SCANS,
  GEMINI_DEFAULT_MODEL, getUser, isPro, json, newRequestId, rateLimited,
  recordScan, scansUsedToday, serviceClient,
} from "../_shared/mod.ts";

const Per100g = z.object({
  kcal: z.number(), proteinG: z.number(), carbsG: z.number(), fatG: z.number(),
  satFatG: z.number().nullable(), fibreG: z.number().nullable(),
  sugarG: z.number().nullable(), saltG: z.number().nullable(),
});
const LabelResult = z.object({
  status: z.enum(["ok", "unreadable", "not_a_label"]),
  productName: z.string().nullable(),
  per100g: Per100g,
  servingSizeG: z.number(),
  servingsPerPack: z.number().nullable(),
  readConfidence: z.number(),
  warnings: z.array(z.string()),
});

const SYSTEM = `You read United Kingdom food nutrition labels and output STRICT JSON only.
Rules:
- Prefer the PER 100g / PER 100ml column. If only a per-portion column is printed, normalise its values to per-100g using the stated portion weight and add a warning like "per-portion column used; per-100g not printed".
- Read SALT (UK labels), never sodium. Pass salt through as grams in saltG.
- NEVER invent a value. If a nutrient is not printed, set it to null.
- servingSizeG = the manufacturer's stated portion in grams (or ml). If absent, estimate a sensible default and warn.
- readConfidence in [0,1] reflects how clearly the table was legible.
- If the image is not a nutrition label, status="not_a_label". If it is a label but illegible, status="unreadable".`;

Deno.serve(async (req) => {
  const rid = newRequestId();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed", rid }, 405);
  try {
    const user = await getUser(req);
    if (!user) return json({ error: "unauthorized", rid }, 401);
    if (rateLimited(user.id)) return json({ error: "rate_limited", rid }, 429);

    const sb = serviceClient();
    const pro = await isPro(user.id);
    if (!pro) {
      const used = await scansUsedToday(sb, user.id);
      if (used >= FREE_DAILY_SCANS) {
        return json({ error: "QUOTA_EXCEEDED", code: "QUOTA_EXCEEDED", used, limit: FREE_DAILY_SCANS, rid }, 402);
      }
    }

    const { imageBase64 } = await req.json().catch(() => ({}));
    if (typeof imageBase64 !== "string" || imageBase64.length < 32) {
      return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
    }
    const model = pro
      ? (Deno.env.get("GEMINI_MODEL_PRO") ?? GEMINI_DEFAULT_MODEL)
      : (Deno.env.get("GEMINI_MODEL") ?? GEMINI_DEFAULT_MODEL);

    let raw: string;
    try {
      raw = await callGeminiJSON(model, SYSTEM, cleanBase64(imageBase64));
    } catch (e) {
      console.error(rid, "gemini_error", String(e));
      return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
    }
    const parsed = extractJSON(raw);
    if (!parsed || typeof parsed !== "object") {
      return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
    }
    const result = LabelResult.safeParse(parsed);
    if (!result.success) {
      console.error(rid, "zod_fail", result.error.message);
      return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
    }
    if (result.data.status === "ok") await recordScan(sb, user.id, "label");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));
    return json({ ...result.data, scansRemaining: remaining, rid }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
  }
});
