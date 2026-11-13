-- =====================================================================
-- AbschleppRadar – Sofort-Aufträge laufen jetzt über Angebote
--  ALT: erster Abschlepper, der "verbindlich annimmt", bekommt den Auftrag
--       und setzt den Preis allein.
--  NEU: Abschlepper geben ein Angebot ab (Preis + Ankunftszeit),
--       der Kunde nimmt eines davon an. Erst dann werden die
--       Kontaktdaten geteilt. Storno-Fenster bleibt 10 Minuten.
--  Pro-Exklusivfenster (5 Min. über den Firmen-Link) bleibt unverändert:
--  in dieser Zeit darf nur die verlinkte Firma ein Angebot abgeben.
--  Zusätzlich: Zähler, wie oft eine Firma Aufträge zurückgegeben hat
--  (wird aus auftrag_log.released_at berechnet – keine neue Spalte).
-- In Supabase: SQL Editor -> New query -> alles einfügen -> RUN
-- =====================================================================

-- 1) Angebote bekommen eine Ankunftszeit (nur für Sofort-Aufträge gefüllt)
alter table public.angebote add column if not exists eta_min integer;

-- 2) Angebot abgeben: jetzt auch für Sofort, mit Ankunftszeit
create or replace function public.submit_offer(p_request uuid, p_preis numeric, p_notiz text,
                                               p_preis_bis numeric default null,
                                               p_termin_vorschlag text default null,
                                               p_eta integer default null)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_kat text; v_wann text;
begin
  if not public.is_approved_driver() then raise exception 'Konto noch nicht freigeschaltet'; end if;
  if p_preis is null or p_preis <= 0 or p_preis >= 100000 then raise exception 'Bitte einen gültigen Preis angeben'; end if;
  if p_preis_bis is not null and (p_preis_bis < p_preis or p_preis_bis >= 100000) then
    raise exception 'Der Preis „bis“ muss größer oder gleich „von“ sein';
  end if;

  select kategorie, wann into v_kat, v_wann from requests
  where id = p_request and status = 'neu' and wann in ('sofort','termin')
    and (exklusiv_bis is null or exklusiv_bis <= now() or bevorzugt_driver = auth.uid());
  if v_kat is null then raise exception 'Dieser Auftrag ist nicht mehr verfügbar'; end if;

  if v_kat <> (case when public.my_typ() = 'werkstatt' then 'werkstatt' else 'abschleppen' end) then
    raise exception 'Dieser Auftrag passt nicht zu Ihrem Kontotyp';
  end if;
  if v_kat = 'werkstatt' and coalesce(char_length(trim(p_notiz)), 0) < 10 then
    raise exception 'Bitte begründen Sie Ihre Schätzung (mindestens 10 Zeichen)';
  end if;

  -- Sofort: Ankunftszeit ist Pflicht und Teil des Angebots
  if v_wann = 'sofort' then
    if p_eta is null or p_eta < 1 or p_eta > 1440 then raise exception 'Bitte die Ankunftszeit angeben'; end if;
    if p_preis_bis is not null then raise exception 'Bei Sofort-Aufträgen bitte einen Festpreis angeben'; end if;
  end if;

  insert into angebote (request_id, driver_id, preis, preis_bis, notiz, termin_vorschlag, eta_min)
  values (p_request, auth.uid(), round(p_preis, 2), round(p_preis_bis, 2),
          left(nullif(trim(p_notiz), ''), 300), left(nullif(trim(p_termin_vorschlag), ''), 100),
          case when v_wann = 'sofort' then p_eta end)
  on conflict (request_id, driver_id)
  do update set preis = excluded.preis, preis_bis = excluded.preis_bis, notiz = excluded.notiz,
                termin_vorschlag = excluded.termin_vorschlag, eta_min = excluded.eta_min, created_at = now();
  return true;
end $function$;

-- 3) Kunde nimmt ein Angebot an: jetzt auch bei Sofort-Aufträgen
create or replace function public.choose_offer(p_id uuid, p_token uuid, p_offer bigint)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
declare v_a angebote; n int; r requests; o record; v_preis text;
  v_app text := public.app_url() || '#fahrer';
begin
  select a.* into v_a from angebote a
  join request_contacts c on c.request_id = a.request_id
  join drivers d on d.id = a.driver_id
  where a.id = p_offer and a.request_id = p_id and c.token = p_token and d.approved;
  if v_a.id is null then return false; end if;

  update requests set status = 'angenommen', accepted_by = v_a.driver_id, accepted_at = now(),
                      preis = v_a.preis, preis_bis = v_a.preis_bis, eta_min = v_a.eta_min
  where id = p_id and status = 'neu' and wann in ('sofort','termin');
  get diagnostics n = row_count;
  if n = 1 then
    select * into r from requests where id = p_id;

    -- bei Sofort-Aufträgen ist die Firma ab jetzt im Einsatz
    if r.wann = 'sofort' then
      update drivers set status = 'im_einsatz', updated_at = now() where id = v_a.driver_id;
    end if;

    insert into auftrag_log (request_id, driver_id, firma, ort, probleme, preis)
    select r.id, d.id, d.firma, r.ort, r.probleme, v_a.preis from drivers d where d.id = v_a.driver_id;

    v_preis := replace(to_char(v_a.preis, 'FM99999990.00'), '.', ',') || ' €'
      || coalesce(' – ' || replace(to_char(v_a.preis_bis, 'FM99999990.00'), '.', ',') || ' €', '');

    perform public.tg_send((select telegram_chat_id from drivers where id = v_a.driver_id),
      case when r.kategorie = 'werkstatt' then '✅ Ihre Preisschätzung wurde ausgewählt!' else '✅ Ihr Angebot wurde angenommen!' end
      || E'\nAuftrag Nr. ' || r.nr
      || E'\n💶 ' || v_preis || ' inkl. MwSt.' || case when r.kategorie = 'werkstatt' then ' (unverbindlich)' else '' end
      || coalesce(E'\n⏱ Ankunft in ' || v_a.eta_min || ' Min. zugesagt', '')
      || coalesce(E'\n⏱ Termin ' || to_char(r.termin at time zone 'Europe/Berlin', 'DD.MM. HH24:MI'), '')
      || E'\n📍 ' || case when coalesce(r.strasse, '') <> '' then r.strasse || ', ' else '' end || r.ort
      || E'\n\nKundendaten finden Sie jetzt in der App – bitte melden Sie sich beim Kunden.',
      '📲 Auftrag öffnen', v_app);

    for o in select d.telegram_chat_id from angebote a join drivers d on d.id = a.driver_id
             where a.request_id = p_id and a.driver_id <> v_a.driver_id loop
      perform public.tg_send(o.telegram_chat_id,
        'ℹ️ Auftrag Nr. ' || r.nr || ': Der Kunde hat sich für ein anderes Angebot entschieden. Danke für Ihr Angebot!');
    end loop;
  end if;
  return n = 1;
end $function$;

-- 4) Kundenansicht: Angebote jetzt auch bei Sofort, inkl. Ankunftszeit
create or replace function public.get_request_status(p_id uuid, p_token uuid)
returns json language sql stable security definer set search_path to 'public' as $function$
  select json_build_object(
    'status', r.status, 'nr', r.nr, 'wann', r.wann, 'termin', r.termin, 'kategorie', r.kategorie,
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
                     or (r.status = 'angenommen' and r.accepted_at < now() - interval '30 minutes')),
    'angebote', case when r.status = 'neu' and r.wann in ('sofort','termin') then (
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

-- 5) Admin: wie viele Aufträge hat eine Firma angenommen und wie viele zurückgegeben?
create or replace function public.admin_auftrag_stats()
returns table (driver_id uuid, angenommen bigint, zurueckgegeben bigint)
language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query
    select l.driver_id,
           count(*) filter (where l.released_at is null),
           count(*) filter (where l.released_at is not null)
    from auftrag_log l
    where l.driver_id is not null
    group by l.driver_id;
end $function$;
revoke execute on function public.admin_auftrag_stats() from public, anon;
grant execute on function public.admin_auftrag_stats() to authenticated;

-- 6) "Erster nimmt an" wird nicht mehr benutzt – Funktion stillgelegt,
--    damit niemand über einen alten Client daran vorbei Aufträge greift.
create or replace function public.accept_request(p_id uuid, p_preis numeric, p_eta integer)
returns boolean language plpgsql security definer set search_path to 'public' as $function$
begin
  raise exception 'Sofort-Aufträge laufen jetzt über Angebote – bitte App neu laden';
end $function$;

select 'Sofort läuft jetzt über Angebote ✅' as status;
