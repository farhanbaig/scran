// lookup-barcode — proxies Open Food Facts v2 with UK preference and normalises
// to Scran's per-100g shape. No AI quota (barcode is always free).
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

async function getUser(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!token) return null;
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await sb.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}
function num(v: unknown): number | null {
  const n = typeof v === "string" ? parseFloat(v) : (v as number);
  return typeof n === "number" && isFinite(n) ? n : null;
}

Deno.serve(async (req) => {
  const id = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed", rid: id }, 405);
  try {
    const user = await getUser(req);
    if (!user) return json({ error: "unauthorized", rid: id }, 401);
    const { barcode } = await req.json().catch(() => ({}));
    if (typeof barcode !== "string" || !/^[0-9]{6,14}$/.test(barcode)) return json({ status: "not_found", rid: id }, 200);

    const fields = ["product_name", "brands", "nutriments", "serving_quantity", "serving_size", "countries_tags"].join(",");
    const url = `https://world.openfoodfacts.org/api/v2/product/${barcode}?fields=${fields}&cc=gb&lc=en`;
    const res = await fetch(url, { headers: { "User-Agent": "Scran/1.0 (hello@wiresidestudios.com)" } });
    if (!res.ok) return json({ status: "not_found", rid: id }, 200);
    const body = await res.json();
    if (body?.status !== 1 || !body?.product) return json({ status: "not_found", rid: id }, 200);

    const p = body.product;
    const n = p.nutriments ?? {};
    const kcal = num(n["energy-kcal_100g"]) ?? (num(n["energy_100g"]) != null ? Math.round((num(n["energy_100g"]) as number) / 4.184) : null);
    if (kcal == null) return json({ status: "not_found", rid: id }, 200);

    const per100g = {
      kcal,
      proteinG: num(n["proteins_100g"]) ?? 0,
      carbsG: num(n["carbohydrates_100g"]) ?? 0,
      fatG: num(n["fat_100g"]) ?? 0,
      satFatG: num(n["saturated-fat_100g"]),
      fibreG: num(n["fiber_100g"]),
      sugarG: num(n["sugars_100g"]),
      saltG: num(n["salt_100g"]) ?? (num(n["sodium_100g"]) != null ? Math.round((num(n["sodium_100g"]) as number) * 2.5 * 100) / 100 : null),
    };
    const servingSizeG = num(p.serving_quantity) ?? 100;
    return json({
      status: "found",
      product: { name: (p.product_name as string)?.trim() || "Unknown product", brand: (p.brands as string)?.split(",")[0]?.trim() || null, barcode },
      per100g, servingSizeG, rid: id,
    }, 200);
  } catch (e) {
    console.error(id, "unhandled", String(e));
    return json({ status: "not_found", rid: id }, 200);
  }
});
