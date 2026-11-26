# Supabase Edge Functions

Sicherungskopien der Edge Functions. Sie laufen in Supabase, nicht hier –
dieser Ordner ist nur das Backup, damit der Code nicht nur an einer
einzigen Stelle existiert.

| Function | Slug | Zweck | Hier im Repo? |
| --- | --- | --- | --- |
| telegram-webhook | `telegram-webhook` | Telegram-Konto mit Abschlepper verknüpfen, Auftragsmeldungen, Passwort-Reset | **ja** |
| push-senden | `clever-worker` | Web-Push-Benachrichtigungen (RFC 8291/8292, von Hand implementiert) | **nein** |

## Warum push-senden hier fehlt

Dieses Repo ist **öffentlich** (Voraussetzung für GitHub Pages im kostenlosen Tarif).
`push-senden` enthält zwei echte Geheimnisse fest im Code:

- `PUSH_SECRET` – damit ruft die Datenbank die Function auf
- `VAPID_PRIVATE_JWK` – der private Schlüssel zum Signieren der Push-Nachrichten

Beide würden hier für jeden lesbar. Die Datei liegt deshalb nur lokal:
`AbschleppRadar/03_Supabase_Yedek/` auf dem PC, zweite Kopie auf USB.

**Wenn sie jemals doch hier landen soll:** erst die beiden Werte in Supabase-Secrets
auslagern (`Deno.env.get(...)`, so wie telegram-webhook es schon macht), dann die
Function neu deployen, dann erst committen.

## Nötige Supabase-Secrets

`telegram-webhook` liest zur Laufzeit:

- `TELEGRAM_WEBHOOK_SECRET`
- `TELEGRAM_BOT_TOKEN`

Nur die **Namen** gehören hierher, niemals die Werte.

## Offener Punkt

In `telegram-webhook` steht `APP_URL` noch auf die alte GitHub-Pages-Adresse:

    https://adler-abschleppdienst-pannenhilfe.github.io/abschleppradar/#fahrer

Im Code steht als Kommentar schon, dass nach der Domain-Umstellung
`https://abschleppradar.de/#fahrer` richtig wäre. Die Umstellung ist passiert,
die Zeile wurde nie angepasst. Funktioniert über die Weiterleitung weiter,
sollte aber bei nächster Gelegenheit geändert werden.
