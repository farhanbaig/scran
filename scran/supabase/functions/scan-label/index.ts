// scan-label — hero feature. Reads a UK nutrition label via Gemini Flash,
// returns per-100g JSON. Enforces the free-tier AI scan quota server-side.
// Tolerant by design: a label is "read" as long as the core numbers are there —
// a missing serving size or an absent optional nutrient must NOT throw the whole
// read away (the old strict-schema failure mode that rejected per-100g-only
// labels and reported them as "unreadable").
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callGeminiJSON, cleanBase64, corsHeaders, extractJSON, FREE_DAILY_SCANS,
  GEMINI_DEFAULT_MODEL, getUser, isPro, json, newRequestId, num, rateLimited,
  recordScan, scansUsedToday, serviceClient,
} from "../_shared/mod.ts";

const SYSTEM = `You read United Kingdom food nutrition labels and output STRICT JSON only (no prose, no markdown).
Rules:
- Prefer the PER 100g / PER 100ml column. If only a per-portion column is printed, normalise its values to per-100g using the stated portion weight and add a warning like "per-portion column used; per-100g not printed".
- ENERGY: report kcal (the kilocalories number), NOT kilojoules. "1750 kJ / 418 kcal" → kcal = 418.
- Read SALT (UK labels), never sodium. Pass salt through as grams in saltG.
- NEVER invent a value. If a nutrient is not printed, set it to null.
- servingSizeG: the manufacturer's stated portion in grams (or ml). MANY labels show only per-100g and no serving — that's fine, return null and still read everything else. Do NOT call the label unreadable just because a serving size is missing.
- readConfidence in [0,1] reflects how clearly the table was legible.
- status: "ok" if you can read the per-100g nutrition. "not_a_label" only if the image is clearly not a nutrition table. "unreadable" only if it IS a label but genuinely too blurry/cropped to read the numbers.

Shape:
{"status":"ok|unreadable|not_a_label","productName":string|null,"per100g":{"kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"satFatG":number|null,"fibreG":number|null,"sugarG":number|null,"saltG":number|null},"servingSizeG":number|null,"servingsPerPack":number|null,"readConfidence":number,"warnings":[string]}`;

// deno-lint-ignore no-explicit-any
function buildResult(parsed: Record<string, any>) {
  if (parsed.status === "not_a_label") {
    return { status: "not_a_label" as const };
  }
  const p = (parsed.per100g ?? {}) as Record<string, unknown>;
  const kcal = num(p.kcal ?? p.energyKcal ?? p.calories);
  const proteinG = num(p.proteinG ?? p.protein);
  const carbsG = num(p.carbsG ?? p.carbohydrate ?? p.carbs);
  const fatG = num(p.fatG ?? p.fat);

  // Genuinely unreadable only if we got essentially nothing.
  if (kcal == null && proteinG == null && carbsG == null && fatG == null) {
    return { status: "unreadable" as const };
  }

  const per100g = {
    kcal: kcal ?? 0,
    proteinG: proteinG ?? 0,
    carbsG: carbsG ?? 0,
    fatG: fatG ?? 0,
    satFatG: num(p.satFatG ?? p.saturates ?? p.saturatedFatG),
    fibreG: num(p.fibreG ?? p.fiberG ?? p.fibre),
    sugarG: num(p.sugarG ?? p.sugars),
    saltG: num(p.saltG ?? p.salt),
  };
  const warnings = Array.isArray(parsed.warnings)
    ? parsed.warnings.filter((w: unknown) => typeof w === "string").slice(0, 6)
    : [];
  const serving = num(parsed.servingSizeG ?? parsed.servingSize);
  if (serving == null) warnings.push("No serving size on the label — using 100g.");

  return {
    status: "ok" as const,
    productName: typeof parsed.productName === "string" && parsed.productName.trim()
      ? parsed.productName.trim() : null,
    per100g,
    servingSizeG: serving ?? 100,
    servingsPerPack: num(parsed.servingsPerPack),
    readConfidence: Math.min(1, Math.max(0, num(parsed.readConfidence, 0.8) as number)),
    warnings,
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
      console.error(rid, "unparseable", raw.slice(0, 200));
      return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
    }

    const result = buildResult(parsed as Record<string, unknown>);
    if (result.status === "ok") await recordScan(sb, user.id, "label");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));
    return json({ ...result, scansRemaining: remaining, rid }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ status: "unreadable", code: "SCAN_UNREADABLE", rid }, 200);
  }
});
