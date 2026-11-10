const express = require("express");
const crypto = require("crypto");
const { createClient } = require("@supabase/supabase-js");

const app = express();
app.use(express.json({ limit: "20kb" }));
app.use(express.static("public"));

const MISSION_MS = 120_000;
const KEY_MS = 24 * 60 * 60 * 1000;

let supabase;
function db() {
  if (supabase) return supabase;
  const url = process.env.SUPABASE_URL;
  const secret = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !secret) throw new Error("Configure SUPABASE_URL e SUPABASE_SECRET_KEY nas variáveis de ambiente.");
  supabase = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  return supabase;
}
function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
function newKey() {
  return "R7-" + crypto.randomBytes(12).toString("hex").toUpperCase();
}
function validUuid(value) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function asyncRoute(fn) {
  return (req, res) => Promise.resolve(fn(req, res)).catch((err) => {
    console.error("API error:", err.message);
    res.status(500).json({ error: "Erro interno. Confira a configuração do banco de dados." });
  });
}

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, databaseConfigured: Boolean(process.env.SUPABASE_URL && (process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY)) });
});

app.post("/api/start", asyncRoute(async (_req, res) => {
  const { data, error } = await db().rpc("start_key_session");
  if (error) throw error;
  res.json({ sessionId: data, mission: 1, durationMs: MISSION_MS });
}));

app.get("/api/status", asyncRoute(async (req, res) => {
  const sessionId = req.header("x-session-id");
  if (!validUuid(sessionId)) return res.status(400).json({ error: "Sessão inválida." });
  const { data, error } = await db().rpc("get_key_session_status", { p_session_id: sessionId });
  if (error) throw error;
  if (!data || data.error) return res.status(404).json({ error: "Sessão não encontrada." });
  res.json(data);
}));

app.post("/api/continue", asyncRoute(async (req, res) => {
  const sessionId = req.header("x-session-id");
  if (!validUuid(sessionId)) return res.status(400).json({ error: "Sessão inválida." });

  const key = newKey();
  const { data, error } = await db().rpc("complete_key_mission", {
    p_session_id: sessionId,
    p_key_hash: sha256(key)
  });
  if (error) {
    if (error.message && error.message.includes("WAIT")) {
      return res.status(403).json({ error: "Aguarde os 2 minutos desta missão." });
    }
    throw error;
  }
  if (!data || data.error) return res.status(404).json({ error: "Sessão não encontrada." });

  if (data.completed) {
    return res.json({ completed: true, key, expiresAt: data.expires_at });
  }
  res.json({ mission: data.mission, completedMissions: data.completed_missions, durationMs: MISSION_MS });
}));

app.post("/api/validate", asyncRoute(async (req, res) => {
  const key = String(req.body?.key || "").trim().toUpperCase();
  if (!/^R7-[A-F0-9]{24}$/.test(key)) return res.json({ valid: false, reason: "Formato de KEY inválido." });
  const { data, error } = await db().rpc("validate_generated_key", { p_key_hash: sha256(key) });
  if (error) throw error;
  res.json(data || { valid: false, reason: "KEY não encontrada." });
}));

// Vercel usa a aplicação exportada; localmente este arquivo também inicia o servidor.
if (require.main === module) {
  const port = process.env.PORT || 3000;
  app.listen(port, () => console.log(`R7 Key Generator em http://localhost:${port}`));
}
module.exports = app;
