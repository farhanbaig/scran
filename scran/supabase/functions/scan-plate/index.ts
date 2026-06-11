// scan-plate — honest, careful plate estimation via Gemini. Pinned fast model
// (no "-latest" alias drift), thinking disabled (auto-fallback if rejected),
// tolerant JSON parsing + coercion. Returns per-item solid/liquid + units, an
// "alternatives" list for ambiguous items, and up to two structured follow-up
// questions (with tappable options) that materially improve accuracy.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callGeminiJSON, cleanBase64, corsHeaders, extractJSON, FREE_DAILY_SCANS,
  GEMINI_DEFAULT_MODEL, GeminiError, getUser, isPro, json, newRequestId, num,
  rateLimited, recordScan, scansUsedToday, serviceClient,
} from "./_shared.ts";

const SYSTEM = `You are a careful UK nutrition estimator. From a photo of a meal or drink, identify each item as precisely as possible and estimate its nutrition. Output STRICT JSON ONLY (no prose, no markdown).

IDENTIFY PRECISELY. Name the specific food, not a category: "Grilled chicken thigh" not "meat"; "Cappuccino" not "coffee"; "Basmati rice" not "rice". If you cannot be sure, give your single best guess as the name AND list other plausible identities in "alternatives".

FOR EACH ITEM provide:
- name: specific best guess
- kind: "solid" or "liquid" (drinks, soups, smoothies, broths = liquid; everything you'd chew = solid)
- amount: estimated portion size — GRAMS for solids, MILLILITRES for liquids
- unit: "g" or "ml" (must match kind)
- the nutrition FOR THAT PORTION: kcal, proteinG, carbsG, fatG, and optionally satFatG, fibreG, sugarG, saltG (null if genuinely unknown)
- confidence in [0,1] — be honest; lower it when the item is obscured, mixed into sauce, or you guessed
- alternatives: 2–4 other plausible identities when you are unsure what the item is (e.g. an ambiguous red meat → ["Lamb","Pork","Beef"]); otherwise []

PORTIONS: estimate only what is VISIBLE, using the plate/cup/cutlery for scale (assume a ~26 cm dinner plate / ~250 ml mug unless clearly otherwise). A mostly-eaten/empty plate usually has only 10–60 g of remnants — estimate just those, set confidence ≤ 0.4, and ask (via a question) whether to log the full meal.

QUESTIONS: provide up to 2 follow-up questions that would MOST change the calorie estimate — only ask when it genuinely matters. Each question = { "prompt": short question, "options": 2–5 concrete tappable choices, "multi": true if several can apply }. Make options specific and ordered sensibly. Examples:
- hot/iced drinks → {"prompt":"Which milk?","options":["None / black","Semi-skimmed","Whole","Oat","Almond"],"multi":false} and {"prompt":"Sugar or syrup?","options":["None","1 tsp","2 tsp","Flavoured syrup"],"multi":false}
- curry / stir-fry → {"prompt":"How was it cooked?","options":["Little oil","Lots of oil or ghee","Creamy / coconut sauce"],"multi":false}
- toppings → {"prompt":"Any toppings?","options":["Cheese","Dressing","Croutons","Seeds"],"multi":true}
- cereal / pasta → a portion-size question.
UK conventions: salt not sodium.

CORRECTIONS: if a USER CORRECTION or ANSWERS are provided with the photo, treat them as ground truth — re-identify or replace items, re-estimate accordingly, raise confidence on resolved items to ≥0.85, and DROP any question the user has already answered.

If there is genuinely no food or drink, return {"status":"no_food","items":[],"questions":[]}.

Shape:
{"status":"ok|no_food","items":[{"name":string,"kind":"solid|liquid","amount":number,"unit":"g|ml","kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"satFatG":number|null,"fibreG":number|null,"sugarG":number|null,"saltG":number|null,"confidence":number,"alternatives":[string]}],"overallConfidence":number,"questions":[{"prompt":string,"options":[string],"multi":boolean}]}`;

function toPer100g(it: Record<string, unknown>, amount: number) {
  const f = amount > 0 ? 100 / amount : 0;
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

function mapItems(parsed: Record<string, unknown>) {
  const raw = Array.isArray(parsed.items) ? parsed.items : [];
  return raw
    .map((it: Record<string, unknown>) => {
      const amount = num(it.amount ?? it.grams ?? it.estimatedGrams, 0) as number;
      if (!amount || amount <= 0) return null;
      const kind = it.kind === "liquid" ? "liquid" : "solid";
      const unit = it.unit === "ml" || it.unit === "g" ? it.unit : (kind === "liquid" ? "ml" : "g");
      const name = typeof it.name === "string" && it.name.trim() ? it.name.trim() : "Food item";
      const alternatives = Array.isArray(it.alternatives)
        ? it.alternatives.filter((x) => typeof x === "string" && x.trim()).slice(0, 4)
        : [];
      return {
        name,
        kind,
        unit,
        estimatedGrams: Math.round(amount),
        per100g: toPer100g(it, amount),
        confidence: Math.min(1, Math.max(0, num(it.confidence, 0.6) as number)),
        alternatives,
      };
    })
    .filter((x: unknown) => x !== null);
}

function mapQuestions(parsed: Record<string, unknown>) {
  const raw = Array.isArray(parsed.questions) ? parsed.questions : [];
  return raw
    .map((q: Record<string, unknown>) => {
      const prompt = typeof q.prompt === "string" ? q.prompt
        : (typeof q.question === "string" ? q.question : null);
      if (!prompt || !prompt.trim()) return null;
      const options = Array.isArray(q.options)
        ? q.options.filter((x) => typeof x === "string" && x.trim()).slice(0, 6)
        : [];
      return { prompt: prompt.trim(), options, multi: q.multi === true };
    })
    .filter((x: unknown) => x !== null)
    .slice(0, 3);
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
    const note = typeof correction === "string" && correction.trim()
      ? correction.trim().slice(0, 600) : null;

    const sb = serviceClient();
    const pro = await isPro(user.id);
    if (!pro && !note) {
      const used = await scansUsedToday(sb, user.id);
      if (used >= FREE_DAILY_SCANS) {
        return json({ error: "QUOTA_EXCEEDED", code: "QUOTA_EXCEEDED", used, limit: FREE_DAILY_SCANS, rid }, 402);
      }
    }

    if (typeof imageBase64 !== "string" || imageBase64.length < 32) {
      return json({ status: "no_food", items: [], overallConfidence: 0, questions: [], rid }, 200);
    }

    const model = Deno.env.get("GEMINI_MODEL_PLATE") ?? Deno.env.get("GEMINI_MODEL") ?? GEMINI_DEFAULT_MODEL;

    let raw: string;
    try {
      raw = await callGeminiJSON(
        model, SYSTEM, cleanBase64(imageBase64),
        note ? `USER CORRECTION / ANSWERS: ${note}` : null);
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
      return json({ status: "no_food", items: [], overallConfidence: 0, questions: [], note: "unparseable", rid }, 200);
    }

    const items = mapItems(parsed);
    if (items.length === 0) {
      return json({ status: "no_food", items: [], overallConfidence: 0, questions: [], rid }, 200);
    }
    const questions = mapQuestions(parsed);

    const overall = (num(parsed.overallConfidence, null) as number | null)
      ?? (items.reduce((s: number, i: { confidence: number }) => s + i.confidence, 0) / items.length);

    if (!note) await recordScan(sb, user.id, "plate");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));

    return json({
      status: "ok",
      items,
      overallConfidence: Math.min(1, Math.max(0, overall)),
      questions,
      scansRemaining: remaining,
      rid,
    }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ error: "SCAN_FAILED", code: "SCAN_FAILED", rid }, 502);
  }
});
