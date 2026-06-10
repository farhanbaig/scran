// delete-account — full Supabase wipe for the calling user. Removes food photos,
// then deletes the auth user; all tables cascade via ON DELETE CASCADE.
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

Deno.serve(async (req) => {
  const rid = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed", rid }, 405);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  try {
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!token) return json({ error: "unauthorized", rid }, 401);
    const { data: u, error: ue } = await sb.auth.getUser(token);
    if (ue || !u.user) return json({ error: "unauthorized", rid }, 401);
    const userId = u.user.id;

    const { data: files } = await sb.storage.from("food-photos").list(userId, { limit: 1000 });
    if (files && files.length) {
      await sb.storage.from("food-photos").remove(files.map((f) => `${userId}/${f.name}`));
    }
    const { error: de } = await sb.auth.admin.deleteUser(userId);
    if (de) { console.error(rid, "deleteUser", de.message); return json({ error: "delete_failed", rid }, 500); }
    return json({ status: "deleted", rid }, 200);
  } catch (e) {
    console.error(rid, "unhandled", String(e));
    return json({ error: "internal", rid }, 500);
  }
});
