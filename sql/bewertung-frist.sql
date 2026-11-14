-- =====================================================================
-- AbschleppRadar – Bewertung erst nach dem Auftrag
--
--  PROBLEM (Murats Einwand 13.11.): Der Kunde konnte schon 30 Minuten
--  nach der Annahme bewerten – da ist der Abschlepper oft noch gar
--  nicht angekommen. Eine Bewertung über eine Leistung, die noch
--  gar nicht erbracht wurde, ist für den Partner unfair.
--
--  NEU: Bewerten geht erst, wenn
--       - der Fahrer auf "Auftrag erledigt" gedrückt hat, ODER
--       - 12 Stunden seit der Annahme vergangen sind.
--  Die 12 Stunden sind die Rückfalltür: Fahrer vergessen das
--  Erledigt-Drücken oft, und ohne Rückfalltür kämen fast keine
--  Bewertungen zusammen.
--
--  Zwei Funktionen müssen geändert werden, sonst passt die Anzeige
--  nicht zur Prüfung: rate_request (speichert) und
--  get_request_status (zeigt den Bewerten-Kasten an).
--
-- In Supabase: SQL Editor -> New query -> alles einfügen -> RUN
-- =====================================================================

-- 1) Frist als Einstellung – später änderbar mit:
--    update app_settings set value = '6' where key = 'bewertung_frist_stunden';
insert into public.app_settings (key, value) values ('bewertung_frist_stunden', '12')
on conflict (key) do nothing;

create or replace function public.bewertung_frist()
returns interval language sql stable security definer set search_path to 'public' as $function$
  select make_interval(hours => greatest(1, coalesce(
    (select nullif(trim(value), '')::int from app_settings where key = 'bewertung_frist_stunden'), 12)));
$function$;

-- 2) Speichern: 30 Minuten -> Frist aus der Einstellung
create or replace function public.rate_request(p_id uuid, p_token uuid, p_sterne integer, p_text text default null)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare r requests;
begin
  if p_sterne is null or p_sterne < 1 or p_sterne > 5 then raise exception 'Bitte 1 bis 5 Sterne wählen.'; end if;
  select q.* into r from requests q join request_contacts c on c.request_id = q.id
   where q.id = p_id and c.token = p_token;
  if not found or r.accepted_by is null then raise exception 'Anfrage nicht gefunden.'; end if;
  if not (r.status = 'erledigt'
          or (r.status = 'angenommen' and r.accepted_at < now() - public.bewertung_frist())) then
    raise exception 'Bewertung ist erst nach dem Auftrag möglich.';
  end if;
  if exists (select 1 from bewertungen where request_id = p_id) then raise exception 'Sie haben bereits bewertet. Danke!'; end if;
  insert into bewertungen (request_id, driver_id, sterne, text)
  values (p_id, r.accepted_by, p_sterne, nullif(left(trim(coalesce(p_text,'')), 500), ''));
  return true;
end $function$;

-- 3) Anzeige: kann_bewerten benutzt dieselbe Frist
--    (Rest der Funktion unverändert gegenüber sofort-ablauf.sql)
create or replace function public.get_request_status(p_id uuid, p_token uuid)
returns json language sql stable security definer set search_path to 'public' as $function$
  select json_build_object(
    'status', r.status, 'nr', r.nr, 'wann', r.wann, 'termin', r.termin, 'kategorie', r.kategorie,
    'abgelaufen', (r.status = 'neu' and r.wann = 'sofort' and r.created_at < now() - public.sofort_frist()),
    'firma', case when r.status in ('angenommen','erledigt') then d.firma end,
    'tel',   case when r.status = 'angenommen' then d.tel end,
    'preis', case when r.status in ('angenommen','erledigt') then r.preis end,
    'preis_bis', case when r.status in ('angenommen','erledigt') then r.preis_bis end,
    'eta_min', case when r.status = 'angenommen' then r.eta_min end,
    'accepted_at', r.accepted_at,
    'exklusiv_firma', case when r.status = 'neu' and r.exklusiv_bis > now() then bd.firma end,
    'firma_sterne', case when r.status in ('angenommen','erledigt') then public.firma_sterne(d.id) end,
    'kunde_lat', r.lat, 'kunde_lng', r.lng,
    'fahrer_lat', case when r.status = 'angenommen' and r.wann = 'sofort' and r.kategorie = 'abschleppen'
                        and d.pos_at > now() - interval '10 minutes' then d.lat end,
    'fahrer_lng', case when r.status = 'angenommen' and r.wann = 'sofort' and r.kategorie = 'abschleppen'
                        and d.pos_at > now() - interval '10 minutes' then d.lng end,
    'fahrer_zeit', case when r.status = 'angenommen' and r.wann = 'sofort' and r.kategorie = 'abschleppen' then d.pos_at end,
    'bewertet', exists (select 1 from bewertungen b where b.request_id = r.id),
    'kann_bewerten', r.accepted_by is not null and (r.status = 'erledigt'
                     or (r.status = 'angenommen' and r.accepted_at < now() - public.bewertung_frist())),
    'angebote', case when r.status = 'neu' and r.wann in ('sofort','termin')
                      and (r.wann <> 'sofort' or r.created_at > now() - public.sofort_frist()) then (
        select coalesce(json_agg(json_build_object('id', a.id, 'firma', ad.firma, 'preis', a.preis, 'preis_bis', a.preis_bis,
                                                   'notiz', a.notiz, 'termin_vorschlag', a.termin_vorschlag,
                                                   'eta_min', a.eta_min,
                                                   'sterne', public.firma_sterne(ad.id))
                                 order by a.preis), '[]'::json)
        from angebote a join drivers ad on ad.id = a.driver_id
        where a.request_id = r.id and ad.approved) end)
  from requests r
  join request_contacts c on c.request_id = r.id
  left join drivers d  on d.id  = r.accepted_by
  left join drivers bd on bd.id = r.bevorzugt_driver
  where r.id = p_id and c.token = p_token;
$function$;

-- Kontrolle: muss 12:00:00 und 06:00:00 ergeben
select public.bewertung_frist() as bewertung_frist, public.sofort_frist() as sofort_frist;
