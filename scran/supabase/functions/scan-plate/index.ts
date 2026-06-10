// scan-plate — honest plate estimation via Gemini Flash. Per-item estimates with
// confidence and at most ONE clarifying question. Quota-gated.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { z } from "npm:zod@3.23.8";
import {
  callGeminiJSON, cleanBase64, corsHeaders, FREE_DAILY_SCANS, getUser, isPro,
  json, newRequestId, rateLimited, recordScan, scansUsedToday, serviceClient,
} from "../_shared/mod.ts";

const Per100g = z.object({
  kcal: z.number(), proteinG: z.number(), carbsG: z.number(), fatG: z.number(),
  satFatG: z.number().nullable(), fibreG: z.number().nullable(),
  sugarG: z.number().nullable(), saltG: z.number().nullable(),
});
const PlateResult = z.object({
  status: z.enum(["ok", "no_food"]),
  items: z.array(z.object({
    name: z.string(), estimatedGrams: z.number(), per100g: Per100g, confidence: z.number(),
  })),
  overallConfidence: z.number(),
  clarifyingQuestion: z.string().nullable(),
  clarifyingImpact: z.string().nullable(),
});

const SYSTEM = `You estimate the nutritional content of a plate of food from a photo, for a UK audience. Output STRICT JSON only.
Rules:
- Identify each distinct food item. For each, estimate portion weight in grams and give per-100g nutrition (UK conventions: salt not sodium; null any nutrient you cannot reasonably estimate).
- Be honest about uncertainty: confidence in [0,1] per item and overallConfidence overall. Plate photos cannot reveal hidden oil, dressing, or sugar — reflect that in confidence.
- Ask AT MOST ONE clarifyingQuestion, and ONLY when it materially changes the result (cooked in oil/ghee, dressing on salad, sugar in drink, fried vs grilled). Otherwise clarifyingQuestion=null. clarifyingImpact describes the kcal swing.
- If there is no food, status="no_food" and items=[].`;

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
      return json({ status: "no_food", items: [], overallConfidence: 0, clarifyingQuestion: null, clarifyingImpact: null, rid }, 200);
    }
    const model = pro
      ? (Deno.env.get("GEMINI_MODEL_PRO") ?? "gemini-flash-latest")
      : (Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest");

    let raw: string;
    try { raw = await callGeminiJSON(model, SYSTEM, cleanBase64(imageBase64)); }
    catch (e) { console.error(rid, "gemini_error", String(e)); return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502); }

    let parsed: unknown;
    try { parsed = JSON.parse(raw); } catch { return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502); }
    const result = PlateResult.safeParse(parsed);
    if (!result.success) { console.error(rid, "zod_fail", result.error.message); return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502); }

    if (result.data.status === "ok" && result.data.items.length > 0) await recordScan(sb, user.id, "plate");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));
    return json({ ...result.data, scansRemaining: remaining, rid }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502);
  }
});
