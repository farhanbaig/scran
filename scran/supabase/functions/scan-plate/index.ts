// scan-plate — honest, careful plate estimation via Gemini. Pinned fast model
// (no "-latest" alias drift), thinking disabled (auto-fallback if rejected),
// tolerant JSON parsing + coercion. Decomposes mixed dishes into countable
// components, returns per-item solid/liquid + units and an "alternatives" list,
// and asks up to three quantitative follow-up questions whose answers re-price
// the nutrition (not just the labels).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  callGeminiJSON, cleanBase64, corsHeaders, extractJSON, FREE_DAILY_SCANS,
  GEMINI_DEFAULT_MODEL, GeminiError, getUser, isPro, json, newRequestId, num,
  rateLimited, recordScan, scansUsedToday, serviceClient,
} from "./_shared.ts";

const SYSTEM = `You are a careful UK nutrition estimator. From a photo of a meal or drink, identify each item as precisely as possible and estimate its nutrition. Output STRICT JSON ONLY (no prose, no markdown).

IDENTIFY PRECISELY. Name the specific food, not a category: "Grilled chicken thigh" not "meat"; "Cappuccino" not "coffee"; "Basmati rice" not "rice". If you cannot be sure, give your single best guess as the name AND list other plausible identities in "alternatives".

OVERALL DISH NAME. Also return a short, natural name for the WHOLE plate as one meal in a top-level "dish" field (≤6 words): "Porridge with berries", "Chicken katsu curry", "Cheese omelette & toast". This is how the meal gets logged, so make it read like a meal a person would say.

DECOMPOSE MIXED DISHES into their visually distinct components as SEPARATE items so each is priced accurately: a bowl of porridge with fruit = "Porridge (oats + milk)" + "Sliced banana" + "Strawberries", not one blob. Sauces/dressings visibly present are their own item. Do NOT invent hidden ingredients as separate items — fold unseen liquids/fats into the component they're part of (milk into the porridge base; cooking oil into the fried item) and resolve them via questions instead. PREFER FEWER, MEANINGFUL ITEMS: only split out a component that is a real part of the meal (roughly ≥10% of it or ≥30 kcal). Do NOT create separate items for garnishes, sprinkles, a few seeds, or specks you are unsure about — fold them into the main item or omit them. If unsure whether something is even present, leave it out rather than inventing it.

COUNT WHAT IS COUNTABLE. Count discrete pieces and derive amounts from the count: strawberry halves → number of berries (~12 g each), banana slices → fraction of a banana (~118 g whole), eggs, sausages, biscuits, sushi pieces. Reflect the count in the item name when natural ("Strawberries (4)", "Half a banana, sliced"). When pieces are mixed INTO a dish so you cannot see them all (banana slices folded through porridge, berries in yoghurt), your visible count is a LOWER BOUND — do not assume it is the whole amount; ask a quantity question instead ("Half a banana or a whole one?").

SANITY-CHECK PHYSICALLY. Your component amounts must add up to roughly the visible cooked volume, and ratios must be plausible (porridge needs ~2.5–3× liquid to dry oats; a normal cooked porridge bowl is 250–400 g from 40–60 g dry oats). Never report dry/raw weights for a cooked dish — estimate the cooked food in front of you.

FOR EACH ITEM provide:
- name: specific best guess
- kind: "solid" or "liquid" (drinks, soups, smoothies, broths = liquid; everything you'd chew = solid)
- amount: estimated portion size — GRAMS for solids, MILLILITRES for liquids
- unit: "g" or "ml" (must match kind)
- the nutrition FOR THAT PORTION: kcal, proteinG, carbsG, fatG, and optionally satFatG, fibreG, sugarG, saltG (null if genuinely unknown)
- confidence in [0,1] — be honest; lower it when the item is obscured, mixed into sauce, or a hidden ingredient (milk type, oil, sugar) materially changes its nutrition and is still unknown
- alternatives: 2–4 other plausible identities when you are unsure what the item is (e.g. an ambiguous red meat → ["Lamb","Pork","Beef"]); otherwise []

PORTIONS: estimate only what is VISIBLE, using the plate/cup/cutlery for scale (assume a ~26 cm dinner plate / ~250 ml mug unless clearly otherwise). A mostly-eaten/empty plate usually has only 10–60 g of remnants — estimate just those, set confidence ≤ 0.4, and ask (via a question) whether to log the full meal.

QUESTIONS: provide up to 3 follow-up questions that would MOST change the estimate — only ask when it genuinely matters. PREFER QUANTITATIVE questions whose options are concrete amounts or counts; the answers feed straight back into the numbers. Each question = { "prompt": short question, "options": 2–5 concrete tappable choices, "multi": true if several can apply }. Order options smallest → largest. Examples:
- hidden liquid → {"prompt":"How was the porridge made?","options":["Water only","Splash of milk (~50ml)","Half milk half water","All milk (~200ml)"],"multi":false} plus {"prompt":"Which milk?","options":["Semi-skimmed","Whole","Skimmed","Oat","Almond"],"multi":false}
- sweetness → {"prompt":"Sugar, honey or syrup added?","options":["None","1 tsp","1 tbsp","2+ tbsp"],"multi":false}
- counts you can't fully see → {"prompt":"How many strawberries in total?","options":["2–3","4–5","6–8","More"],"multi":false} or {"prompt":"How much banana went in?","options":["Half a banana","A whole banana","Two bananas"],"multi":false}
- curry / stir-fry → {"prompt":"How was it cooked?","options":["Little oil (1 tsp)","Moderate oil (1 tbsp)","Lots of oil or ghee","Creamy / coconut sauce"],"multi":false}
- toppings → {"prompt":"Any toppings?","options":["Cheese","Dressing","Croutons","Seeds"],"multi":true}
UK conventions: salt not sodium.

CORRECTIONS: if a USER CORRECTION or ANSWERS are provided with the photo, treat them as ground truth and RE-PRICE THE NUTRITION, not just the labels: a stated milk type/amount changes the porridge base's kcal and fat for that portion; a stated count changes the item's amount; a stated oil changes kcal density. Recompute every affected item's amount AND nutrition from the answer, raise confidence on resolved items to ≥0.85, and DROP any question the user has already answered. RE-PRICE ONLY — do not invent NEW items the user didn't mention; corrections refine the existing items, they don't add garnishes.

SCORING: overallConfidence reflects how much is still unknown — while a question that materially changes the numbers is unanswered, cap overallConfidence at 0.7; once answers resolve the big unknowns, score 0.85–0.95. Never report high confidence while a major hidden ingredient is unresolved.

If there is genuinely no food or drink, return {"status":"no_food","items":[],"questions":[]}.

Shape:
{"status":"ok|no_food","dish":string,"items":[{"name":string,"kind":"solid|liquid","amount":number,"unit":"g|ml","kcal":number,"proteinG":number,"carbsG":number,"fatG":number,"satFatG":number|null,"fibreG":number|null,"sugarG":number|null,"saltG":number|null,"confidence":number,"alternatives":[string]}],"overallConfidence":number,"questions":[{"prompt":string,"options":[string],"multi":boolean}]}`;

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
      // Drop tiny, low-confidence specks (phantom garnishes) — but keep small
      // high-confidence items like a teaspoon of oil.
      const conf = Math.min(1, Math.max(0, num(it.confidence, 0.6) as number));
      if (amount < 5 && conf < 0.5) return null;
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
        confidence: conf,
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

    // Overall meal name (how it gets logged). Fall back to the largest item.
    const dishRaw = typeof parsed.dish === "string" ? parsed.dish.trim() : "";
    const dish = dishRaw
      ? dishRaw.slice(0, 80)
      : (items.slice().sort((a, b) =>
          (b.per100g.kcal * b.estimatedGrams) - (a.per100g.kcal * a.estimatedGrams))[0]?.name ?? null);

    if (!note) await recordScan(sb, user.id, "plate");
    const remaining = pro ? null : Math.max(0, FREE_DAILY_SCANS - (await scansUsedToday(sb, user.id)));

    return json({
      status: "ok",
      dish,
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
