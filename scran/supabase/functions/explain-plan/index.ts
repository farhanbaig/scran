// explain-plan — Claude Haiku writes 3 plain-English paragraphs explaining the
// user's plan. The exercise-already-included sentence is enforced verbatim.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
const EXERCISE_SENTENCE = "Your weekly exercise is already included in this target — logging a workout will not add calories back.";

async function getUser(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!token) return null;
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

function fallbackCopy(p: Record<string, number | string>): string {
  const t = Math.round(Number(p.dailyTargetKcal)), bmr = Math.round(Number(p.bmr)), tdee = Math.round(Number(p.tdee));
  const goal = String(p.goal);
  const g = goal === "lose" ? "lose weight" : goal === "gain" ? "gain weight" : "maintain your weight";
  return [
    `Your body burns about ${bmr} kcal a day at rest — that's your base metabolism, worked out from your height, weight, age and sex. Factoring in how active you are brings your daily burn (TDEE) to roughly ${tdee} kcal.`,
    `To ${g} at the rate you chose, we set your daily target to ${t} kcal. ${EXERCISE_SENTENCE}`,
    `These are honest estimates, not lab measurements — real bodies vary. Log consistently for a couple of weeks and the numbers tell you whether to nudge the target up or down.`,
  ].join("\n\n");
}

Deno.serve(async (req) => {
  const rid = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed", rid }, 405);
  try {
    const user = await getUser(req);
    if (!user) return json({ error: "unauthorized", rid }, 401);
    const { plan } = await req.json().catch(() => ({}));
    if (!plan || typeof plan !== "object") return json({ error: "bad_request", rid }, 400);

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ explanation: fallbackCopy(plan), source: "fallback", rid }, 200);

    const model = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5-20251001";
    const prompt =
      `Write exactly three short, warm, plain-English paragraphs explaining this UK calorie plan to its owner. ` +
      `Use "you/your". No markdown, no headings, no bullet points. Separate paragraphs with a blank line.\n` +
      `Paragraph 1: explain BMR and TDEE in human terms using their numbers.\n` +
      `Paragraph 2: explain how the daily target follows from their goal and rate, and include this sentence VERBATIM: "${EXERCISE_SENTENCE}"\n` +
      `Paragraph 3: an honest caveat that these are estimates that drift, and the plan will recalibrate from logged data.\n\n` +
      `Plan data (JSON): ${JSON.stringify(plan)}`;

    let text = "";
    try {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "Content-Type": "application/json" },
        body: JSON.stringify({ model, max_tokens: 600, temperature: 0.4, messages: [{ role: "user", content: prompt }] }),
      });
      if (res.ok) {
        const body = await res.json();
        text = (body?.content ?? []).map((b: { text?: string }) => b.text ?? "").join("").trim();
      } else {
        console.error(rid, "anthropic", res.status, (await res.text()).slice(0, 200));
      }
    } catch (e) { console.error(rid, "anthropic_error", String(e)); }

    if (!text) text = fallbackCopy(plan);
    if (!text.includes(EXERCISE_SENTENCE)) {
      const paras = text.split(/\n\n+/);
      if (paras.length >= 2) paras[1] = `${paras[1]} ${EXERCISE_SENTENCE}`; else paras.push(EXERCISE_SENTENCE);
      text = paras.join("\n\n");
    }
    return json({ explanation: text, source: "claude", rid }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ error: "internal", rid }, 500);
  }
});
