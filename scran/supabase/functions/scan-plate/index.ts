// scan-plate — honest plate estimation via Gemini. Robust by design: pinned
// fast model (no "-latest" alias drift), thinking disabled (auto-fallback if
// the param is rejected), tolerant JSON parsing + coercion, per-portion prompt
// that's easier for the model. Computes the per-100g block the client expects.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callGeminiJSON, cleanBase64, corsHeaders, extractJSON, FREE_DAILY_SCANS,
  GEMINI_DEFAULT_MODEL, GeminiError, getUser, isPro, json, newRequestId, num,
  rateLimited, recordScan, scansUsedToday, serviceClient,
} from "../_shared/mod.ts";

const SYSTEM = `You estimate the nutrition of a plate of food from a photo, for a UK audience. Output STRICT JSON ONLY (no prose, no markdown).
For EACH distinct food item give: name, grams (estimated portion weight), and the nutrition FOR THAT PORTION: kcal, proteinG, carbsG, fatG, and optionally satFatG, fibreG, sugarG, saltG (use null if unsure). Also confidence in [0,1].
ESTIMATE ONLY WHAT IS VISIBLE. Never assume a typical serving that is not in the photo; anchor grams to what is physically on the plate, using the plate (~26 cm dinner plate unless clearly smaller) as the size reference.
If the plate is mostly empty — residue, smears, bones, scraps — the visible food is usually only 10–60 g. Estimate just those remnants, set confidence at or below 0.4, and use the clarifyingQuestion to ask whether they want to log the full meal they already ate (clarifyingImpact: the likely kcal difference).
Confidence calibration: 0.85+ only for distinct, clearly visible items; 0.6–0.8 for a typical mixed plate; 0.5 or below when food is obscured, mixed into sauces, or mostly eaten. Be honest — photos hide oil, dressing, sugar.
UK conventions: salt not sodium.
Ask AT MOST ONE clarifyingQuestion only when the answer materially changes the result (mostly-eaten plate, cooked in oil/ghee, dressing, sugar in drink, fried vs grilled); else null.
If a USER CORRECTION is supplied with the photo, it is ground truth from the person who ate the meal: rename, replace, add or remove items exactly as it says, re-estimate nutrition for the corrected items, and raise confidence on corrected items to at least 0.85. A correction may answer a previous clarifying question (e.g. "yes — log the full meal I ate"): honour it, and never repeat a question it answers.
If there is genuinely no food, return status "no_food" with items [].
Shape:
{"status":"ok|no_food","items":[{"name":string,"grams":number,"kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"satFatG":number|null,"fibreG":number|null,"sugarG":number|null,"saltG":number|null,"confidence":number}],"overallConfidence":number,"clarifyingQuestion":string|null,"clarifyingImpact":string|null}`;

function toPer100g(it: Record<string, unknown>, grams: number) {
  const f = grams > 0 ? 100 / grams : 0;
  const scale = (v: number | null) => (v == null ? null : Math.round(v * f * 10) / 10);
  return {
    kcal: Math.round((num(it.kcal, 0) as number) * f),
    proteinG: scale(num(it.proteinG, 0)) ?? 0,
    carbsG: scale(num(it.carbsG, 0)) ?? 0,
    fatG: scale(num(it.fatG, 0)) ?? 0,
    satFatG: scale(num(it.satFatG)),
    fibreG: scale(num(it.fibreG)),
    sugarG: scale(num(it.sugarG)),
    saltG: scale(num(it.saltG)),
  };
}

Deno.serve(async (req) => {
  const rid = newRequestId();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed", rid }, 405);
  try {
    const user = await getUser(req);
    if (!user) return json({ error: "unauthorized", rid }, 401);
    if (rateLimited(user.id)) return json({ error: "rate_limited", rid }, 429);

    const { imageBase64, correction } = await req.json().catch(() => ({}));
    // A correction is a refinement of a scan the user already spent — it gets a
    // fresh Gemini pass but neither checks nor consumes the daily quota (the
    // burst rate limit above still bounds it).
    const note = typeof correction === "string" && correction.trim()
      ? correction.trim().slice(0, 280) : null;

    const sb = serviceClient();
    const pro = await isPro(user.id);
    if (!pro && !note) {
      const used = await scansUsedToday(sb, user.id);
      if (used >= FREE_DAILY_SCANS) {
        return json({ error: "QUOTA_EXCEEDED", code: "QUOTA_EXCEEDED", used, limit: FREE_DAILY_SCANS, rid }, 402);
      }
    }

    if (typeof imageBase64 !== "string" || imageBase64.length < 32) {
      return json({ status: "no_food", items: [], overallConfidence: 0, clarifyingQuestion: null, clarifyingImpact: null, rid }, 200);
    }

    const model = Deno.env.get("GEMINI_MODEL_PLATE") ?? Deno.env.get("GEMINI_MODEL") ?? GEMINI_DEFAULT_MODEL;

    let raw: string;
    try {
      raw = await callGeminiJSON(
        model, SYSTEM, cleanBase64(imageBase64),
        note ? `USER CORRECTION: ${note}` : null);
    } catch (e) {
      const gErr = e as GeminiError;
      const gStatus = typeof gErr?.status === "number" ? gErr.status : 0;
      console.error(rid, "gemini_error", model, "status=" + gStatus, String(gErr?.message ?? e).slice(0, 240));
      if (gStatus === 429) {
        return json({ error: "AI_BUSY", code: "AI_BUSY", detail: "Gemini rate limit / quota", rid }, 429);
      }
      return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", geminiStatus: gStatus, detail: String(gErr?.message ?? e).slice(0, 200), rid }, 502);
    }

    const parsed = extractJSON(raw);
    if (!parsed || typeof parsed !== "object") {
      console.error(rid, "unparseable", raw.slice(0, 200));
      return json({ status: "no_food", items: [], overallConfidence: 0, clarifyingQuestion: null, clarifyingImpact: null, note: "unparseable", rid }, 200);
    }

    const rawItems = Array.isArray(parsed.items) ? parsed.items : [];
    const items = rawItems
      .map((it: Record<string, unknown>) => {
        const grams = num(it.grams ?? it.estimatedGrams, 0) as number;
        if (!grams || grams <= 0) return null;
        const name = typeof it.name === "string" && it.name.trim() ? it.name.trim() : "Food item";
        return {
          name,
          estimatedGrams: Math.round(grams),
          per100g: toPer100g(it, grams),
          confidence: Math.min(1, Math.max(0, num(it.confidence, 0.6) as number)),
        };
      })
      .filter((x: unknown) => x !== null);

    if (items.length === 0) {
      return json({ status: "no_food", items: [], overallConfidence: 0, clarifyingQuestion: null, clarifyingImpact: null, rid }, 200);
    }

    const overall = (num(parsed.overallConfidence, null) as number | null)
      ?? (items.reduce((s: number, i: { confidence: number }) => s + i.confidence, 0) / items.length);
    const cq = typeof parsed.clarifyingQuestion === "string" ? parsed.clarifyingQuestion : null;
    const ci = typeof parsed.clarifyingImpact === "string" ? parsed.clarifyingImpact : null;

    if (!note) await recordScan(sb, user.id, "plate");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));

    return json({
      status: "ok", items,
      overallConfidence: Math.min(1, Math.max(0, overall)),
      clarifyingQuestion: cq, clarifyingImpact: ci,
      scansRemaining: remaining, rid,
    }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502);
  }
});
