-- =====================================================================
-- AbschleppRadar – Öffnungszeiten / 24-Stunden-Notdienst
--
--  WARUM: Eine Sofort-Anfrage um 3 Uhr nachts ging bisher per Telegram
--  und Push an JEDE freigeschaltete Firma im Umkreis, die nicht offline
--  ist – auch an die, die um 18 Uhr Feierabend macht. Das nervt und
--  kostet auf Dauer Partner.
--
--  ENTSCHIEDEN (Murat, 23.11.): Die Zeiten steuern NUR die
--  Benachrichtigung. Wer gerade zu hat, bekommt keine Nachricht,
--  SIEHT den Auftrag aber weiterhin in der App und darf ein Angebot
--  abgeben. So geht kein Auftrag verloren, nur das Klingeln hört auf.
--  Ausnahme: Anfragen über den eigenen Firmen-Link (QR/Sticker der
--  Firma) gehen immer raus – das ist der eigene Kunde der Firma.
--
--  Verzeichnis-Partner (Gutachter, Werkstatt, Reifenservice,
--  Autowäsche) bekommen dieselben Felder, dort aber nur zur Anzeige
--  ("Jetzt geöffnet").
--
-- In Supabase: SQL Editor -> New query -> alles einfügen -> RUN
-- =====================================================================

-- 1) Felder für Abschleppdienste/Werkstätten.
--    Standard notdienst_24h = true → für alle bestehenden Firmen
--    ändert sich NICHTS, bis sie selbst Zeiten eintragen.
alter table public.drivers add column if not exists notdienst_24h boolean not null default true;
alter table public.drivers add column if not exists oeffnung_von  time;
alter table public.drivers add column if not exists oeffnung_bis  time;
alter table public.drivers add column if not exists offen_sa boolean not null default true;
alter table public.drivers add column if not exists offen_so boolean not null default false;

-- 2) Dieselben Felder für das Verzeichnis.
--    Hier Standard false + keine Zeiten = "unbekannt" → es wird gar
--    kein Hinweis angezeigt, solange niemand Zeiten einträgt.
alter table public.partners add column if not exists notdienst_24h boolean not null default false;
alter table public.partners add column if not exists oeffnung_von  time;
alter table public.partners add column if not exists oeffnung_bis  time;
alter table public.partners add column if not exists offen_sa boolean not null default false;
alter table public.partners add column if not exists offen_so boolean not null default false;

-- 3) Ist dieser Betrieb gerade offen?
--    true = offen, false = geschlossen, NULL = keine Angabe.
--    Rechnet in deutscher Zeit, auch über Mitternacht (z. B. 18–02 Uhr).
create or replace function public.ist_offen(p_24h boolean, p_von time, p_bis time,
                                            p_sa boolean, p_so boolean)
returns boolean language plpgsql stable security definer set search_path to 'public' as $function$
declare v_jetzt timestamp; v_zeit time; v_tag int; v_tag_ok boolean;
begin
  if coalesce(p_24h, false) then return true; end if;
  if p_von is null or p_bis is null then return null; end if;   -- keine Angabe

  v_jetzt := now() at time zone 'Europe/Berlin';
  v_zeit  := v_jetzt::time;
  v_tag   := extract(isodow from v_jetzt)::int;   -- 1 = Montag … 7 = Sonntag

  v_tag_ok := case v_tag
                when 6 then coalesce(p_sa, false)
                when 7 then coalesce(p_so, false)
                else true end;
  if not v_tag_ok then return false; end if;

  if p_bis > p_von then
    return v_zeit >= p_von and v_zeit < p_bis;
  else
    return v_zeit >= p_von or v_zeit < p_bis;     -- Schicht über Mitternacht
  end if;
end $function$;

-- 4) Benachrichtigung: unverändert bis auf EINE Zeile in der
--    Firmen-Auswahl (unten mit "NEU" markiert).
create or replace function public.notify_request(p_id uuid, p_only uuid default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare r requests; d record; v_dist numeric; v_probs text; v_text text; v_footer text; v_typ text;
  v_app text := public.app_url() || '#fahrer';
begin
  select * into r from requests where id = p_id;
  if r.id is null or r.status <> 'neu' then return; end if;
  v_typ := case when r.kategorie = 'werkstatt' then 'werkstatt' else 'abschlepper' end;

  select string_agg(case p
    when 'abschleppen' then '🚛 Abschleppen' when 'starthilfe' then '🔋 Starthilfe'
    when 'reifen' then '🛞 Reifenwechsel' when 'schluessel' then '🔑 Ausgesperrt'
    when 'kraftstoff' then '⛽ Kein Kraftstoff' when 'unfall' then '⚠️ Unfall'
    else '🔧 Sonstiges' end, ', ') into v_probs
  from unnest(r.probleme) p;

  v_footer := case
    when p_only is not null then E'\n\n⭐ Direktanfrage über Ihren Firmen-Link – nur Sie sehen diesen Auftrag in den nächsten 5 Minuten. Geben Sie Festpreis und Ankunftszeit an.'
    when r.kategorie = 'werkstatt' then E'\n\n💶 Geben Sie in der App eine unverbindliche Preisschätzung mit kurzer Begründung ab – der Kunde wählt.'
    when r.wann = 'termin' then E'\n\n💶 Termin-Auftrag: Geben Sie in der App ein Angebot ab – der Kunde wählt.'
    -- Seit dem Angebots-Verfahren (13.11.) gilt NICHT mehr "wer zuerst annimmt":
    -- der Kunde wählt aus den Angeboten aus.
    else E'\n\n💶 Geben Sie in der App Festpreis und Ankunftszeit an – der Kunde wählt aus. Bitte erst losfahren, wenn Ihr Angebot angenommen wurde.' end;

  for d in
    select id, telegram_chat_id, lat, lng, radius_km, status from drivers
    where approved and typ = v_typ
      and (telegram_chat_id is not null or exists (select 1 from push_subs ps where ps.driver_id = drivers.id))
      and (case when p_only is not null then id = p_only and status <> 'offline'
                else status = 'verfuegbar' and id is distinct from r.bevorzugt_driver end)
      -- NEU: außerhalb der eigenen Öffnungszeiten keine Benachrichtigung.
      -- Keine Zeiten eingetragen -> wie bisher benachrichtigen.
      -- Direktanfrage über den eigenen Firmen-Link -> immer benachrichtigen.
      and (p_only is not null
           or coalesce(public.ist_offen(drivers.notdienst_24h, drivers.oeffnung_von,
                                        drivers.oeffnung_bis, drivers.offen_sa, drivers.offen_so), true))
  loop
    v_dist := null;
    if d.lat is not null and d.lng is not null then
      v_dist := 6371 * 2 * asin(sqrt(
        power(sin(radians(r.lat - d.lat) / 2), 2) +
        cos(radians(d.lat)) * cos(radians(r.lat)) * power(sin(radians(r.lng - d.lng) / 2), 2)));
      continue when p_only is null and v_dist > d.radius_km;
    end if;
    if r.kategorie = 'werkstatt' then
      v_text := '🔧 Neue Werkstatt-Anfrage Nr. ' || r.nr
        || E'\n🚗 ' || r.marke || coalesce(' ' || r.modell, '')
        || E'\n📍 ' || r.ort
        || case when v_dist is not null then ' (' || replace(round(v_dist, 1)::text, '.', ',') || ' km)' else '' end
        || E'\n📝 ' || left(coalesce(r.notiz, ''), 300)
        || coalesce(E'\n📅 Wunschtermin: ' || to_char(r.termin at time zone 'Europe/Berlin', 'DD.MM.'), '')
        || v_footer;
    else
      v_text := '🚨 Neuer Auftrag Nr. ' || r.nr || E'\n' || coalesce(v_probs, '')
        || E'\n📍 ' || r.strasse || ', ' || r.ort
        || case when v_dist is not null then ' (' || replace(round(v_dist, 1)::text, '.', ',') || ' km)' else '' end
        || E'\n🚗 ' || r.marke || coalesce(' ' || r.modell, '')
        || E'\n⏱ ' || case when r.wann = 'sofort' then 'Sofort'
                          else coalesce('Termin ' || to_char(r.termin at time zone 'Europe/Berlin', 'DD.MM. HH24:MI'), 'Termin') end
        || coalesce(E'\n🏁 Ziel: ' || r.ziel || coalesce(' (ca. ' || round(r.ziel_km)::text || ' km Fahrstrecke)', ''), '')
        || v_footer;
    end if;
    if d.telegram_chat_id is not null then
      perform public.tg_send(d.telegram_chat_id, v_text, '📲 Auftrag in der App ansehen', v_app);
    end if;
    perform public.push_send(public.push_subs_json(array[d.id], null),
      split_part(v_text, E'\n', 1),
      regexp_replace(substr(v_text, strpos(v_text, E'\n') + 1), E'\n\n.*$', ''),
      v_app, 'auftrag-' || r.nr);
  end loop;
end $function$;

-- 5) Die Firma speichert ihre eigenen Zeiten (nur die eigenen).
create or replace function public.set_oeffnungszeiten(p_24h boolean, p_von time, p_bis time,
                                                      p_sa boolean, p_so boolean)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_approved_driver() then raise exception 'Konto noch nicht freigeschaltet'; end if;
  if not coalesce(p_24h, false) and (p_von is null or p_bis is null) then
    raise exception 'Bitte Öffnungszeit von und bis angeben';
  end if;
  if not coalesce(p_24h, false) and p_von = p_bis then
    raise exception 'Öffnungszeit „von“ und „bis“ dürfen nicht gleich sein';
  end if;
  update drivers set notdienst_24h = coalesce(p_24h, false),
                     oeffnung_von = case when coalesce(p_24h, false) then null else p_von end,
                     oeffnung_bis = case when coalesce(p_24h, false) then null else p_bis end,
                     offen_sa = coalesce(p_sa, false),
                     offen_so = coalesce(p_so, false),
                     updated_at = now()
  where id = auth.uid();
  return true;
end $function$;

-- 6) Für den Admin: welcher Betrieb kann überhaupt benachrichtigt werden?
--    Eine Firma ohne Telegram UND ohne Push-Abo steht zwar im System,
--    erfährt aber von keinem einzigen Auftrag. Das muss sichtbar sein.
create or replace function public.admin_kanal_status()
returns table(driver_id uuid, telegram boolean, push integer)
language sql stable security definer set search_path to 'public' as $function$
  select d.id,
         d.telegram_chat_id is not null,
         (select count(*)::int from push_subs ps where ps.driver_id = d.id)
  from drivers d
  where public.is_admin();
$function$;

-- Kontrolle: wer ist gerade offen?
select firma,
       case when notdienst_24h then '24 Stunden'
            when oeffnung_von is null then 'keine Angabe'
            else to_char(oeffnung_von,'HH24:MI') || '–' || to_char(oeffnung_bis,'HH24:MI') end as zeiten,
       coalesce(public.ist_offen(notdienst_24h, oeffnung_von, oeffnung_bis, offen_sa, offen_so), true) as bekommt_benachrichtigung
from public.drivers order by firma;
