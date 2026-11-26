// AbschleppRadar – Telegram-Bot (Supabase Edge Function "telegram-webhook")
// Verknüpft einen Telegram-Chat mit dem Abschlepper-Konto, wenn dieser in der App
// auf "Telegram verbinden" tippt (Telegram sendet dann "/start <Code>").

const SUPABASE_URL = "https://tgpabumwznytuplybejc.supabase.co";
const SUPABASE_KEY = "sb_publishable_aJ8s0M0GtuVna3LgBpD9jw_rGGA7TMp"; // öffentlicher Schlüssel
const APP_URL = "https://adler-abschleppdienst-pannenhilfe.github.io/abschleppradar/#fahrer"; // nach Domain-Umstellung: "https://abschleppradar.de/#fahrer"

Deno.serve(async (req) => {
  // Nur echte Anfragen von Telegram akzeptieren
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-telegram-bot-api-secret-token") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  let update: any;
  try { update = await req.json(); } catch { return new Response("ok"); }
  const msg = update?.message;
  if (!token || !msg?.chat?.id || typeof msg.text !== "string") return new Response("ok");

  const chatId = msg.chat.id;
  const text = msg.text.trim();

  const send = (t: string) =>
    fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: t,
        reply_markup: { inline_keyboard: [[{ text: "📲 AbschleppRadar öffnen", url: APP_URL }]] },
      }),
    });

  // Passwort vergessen: Link geht nur an den mit dem Konto verbundenen Chat
  if (/^\/(passwort|password|pass)\b/i.test(text)) {
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/tg_password_reset`, {
      method: "POST",
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_chat: chatId }),
    });
    return new Response("ok");
  }

  const m = text.match(/^\/start\s+([0-9a-fA-F-]{36})$/);
  if (m) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/telegram_link`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_code: m[1], p_chat: chatId }),
    });
    const firma = r.ok ? await r.json() : null;
    if (firma) {
      await send(
        `✅ Verbunden mit „${firma}“.\n\nSie erhalten ab jetzt eine Nachricht, sobald ein neuer Auftrag in Ihrem Umkreis eingeht – solange Sie in der App auf „Verfügbar“ stehen.`,
      );
    } else {
      await send("❌ Verknüpfung fehlgeschlagen oder Link schon benutzt. Bitte in der App erneut auf „Telegram verbinden“ tippen.");
    }
  } else {
    await send("👋 Hallo! Bitte verbinden Sie Telegram über die AbschleppRadar-App: Anmelden → „Telegram verbinden“.\n\nPasswort vergessen? Schreiben Sie /passwort");
  }
  return new Response("ok");
});
