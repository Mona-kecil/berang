import { EmailMessage } from "cloudflare:email";

const FROM = "feedback@monosodiums.com";
const TO = "michael@monosodiums.com";
const EMAIL = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== "/feedback") return env.ASSETS.fetch(request);
    if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });

    let form;
    try { form = await request.formData(); } catch { return reply(400, "Write something first."); }
    // People leave this field empty because they never see it. Bots fill it in.
    if (form.get("website")) return reply(200);
    const message = String(form.get("message") ?? "").trim();
    const email = String(form.get("email") ?? "").trim();
    if (!message) return reply(400, "Write something first.");
    if (message.length > 5000) return reply(400, "Keep it under 5,000 characters.");
    if (email && (email.length > 254 || !EMAIL.test(email))) return reply(400, "Check your email address.");

    const { success } = await env.LIMIT.limit({ key: request.headers.get("CF-Connecting-IP") ?? "" });
    if (!success) return reply(429, "Too many messages. Try again in a minute.");

    const headers = [
      `From: Berang feedback <${FROM}>`,
      `To: ${TO}`,
      ...(email ? [`Reply-To: ${email}`] : []),
      `Subject: Berang feedback`,
      `Date: ${new Date().toUTCString()}`,
      `Message-ID: <${crypto.randomUUID()}@monosodiums.com>`,
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: base64",
    ];
    const body = `${message}\n\n--\nFrom: ${email || "no address given"}\nPage: ${request.headers.get("Referer") ?? "unknown"}\n`;
    const raw = `${headers.join("\r\n")}\r\n\r\n${base64(body)}\r\n`;
    try {
      await env.EMAIL.send(new EmailMessage(FROM, TO, raw));
    } catch (error) {
      console.error("send failed", error);
      return reply(502, "It didn't send. Try again in a minute.");
    }
    return reply(200);
  },
};

function reply(status, error) {
  return Response.json(error ? { error } : { ok: true }, { status });
}

function base64(text) {
  let binary = "";
  for (const byte of new TextEncoder().encode(text)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/.{76}/g, "$&\r\n");
}
