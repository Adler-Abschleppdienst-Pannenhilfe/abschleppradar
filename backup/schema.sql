--
-- PostgreSQL database dump
--

\restrict TXmmEAmAcTa0MfYISWMVnXfSmYc0TWK7Crfjbq4erWHX3PEIIP6ZHwV6r7mAI1n

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.12 (Debian 17.12-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: accept_request(uuid, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_request(p_id uuid, p_preis numeric, p_eta integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  raise exception 'Sofort-Aufträge laufen jetzt über Angebote – bitte App neu laden';
end $$;


--
-- Name: admin_abrechnung(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_abrechnung(p_von date, p_bis date) RETURNS TABLE(driver_id uuid, firma text, tel text, auftraege bigint, berechnet bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query
    select l.driver_id, max(l.firma), max(d.tel), count(*),
           count(*) filter (where public.log_berechnet(l))
    from auftrag_log l left join drivers d on d.id = l.driver_id
    where l.accepted_at >= p_von and l.accepted_at < p_bis + 1
    group by l.driver_id
    order by 5 desc;
end $$;


--
-- Name: admin_auftrag_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_auftrag_stats() RETURNS TABLE(driver_id uuid, angenommen bigint, zurueckgegeben bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query
    select l.driver_id,
           count(*) filter (where l.released_at is null),
           count(*) filter (where l.released_at is not null)
    from auftrag_log l
    where l.driver_id is not null
    group by l.driver_id;
end $$;


--
-- Name: admin_bewertungen(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_bewertungen(p_driver uuid) RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return (select coalesce(json_agg(x), '[]'::json) from (
            select sterne, text, created_at from bewertungen
            where driver_id = p_driver order by created_at desc limit 50) x);
end $$;


--
-- Name: admin_drivers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_drivers() RETURNS TABLE(id uuid, firma text, tel text, email text, approved boolean, status text, created_at timestamp with time zone, auftraege bigint, typ text, pro boolean, pro_frei_bis timestamp with time zone, sterne numeric, bew_anzahl bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query
    select d.id, d.firma, d.tel, u.email::text, d.approved, d.status, d.created_at,
           (select count(*) from auftrag_log l where l.driver_id = d.id), d.typ, d.pro, d.pro_frei_bis,
           (select round(avg(b.sterne)::numeric, 1) from bewertungen b where b.driver_id = d.id),
           (select count(*) from bewertungen b where b.driver_id = d.id)
    from drivers d left join auth.users u on u.id = d.id
    order by d.approved, d.created_at desc;
end $$;


--
-- Name: admin_invite_create(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_invite_create(p_typ text, p_firma text, p_tel text, p_email text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_code uuid;
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  if coalesce(char_length(trim(p_firma)),0) < 2 then raise exception 'Bitte Firmennamen angeben'; end if;
  if char_length(regexp_replace(coalesce(p_tel,''), '\D', '', 'g')) < 6 then raise exception 'Bitte gültige Telefonnummer angeben'; end if;
  insert into einladungen (typ, firma, tel, email)
  values (case when p_typ = 'werkstatt' then 'werkstatt' else 'abschlepper' end, trim(p_firma), trim(p_tel), nullif(trim(p_email), ''))
  returning code into v_code;
  return v_code;
end $$;


--
-- Name: admin_invite_delete(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_invite_delete(p_code uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  delete from einladungen where code = p_code and eingeloest_at is null;
end $$;


--
-- Name: admin_invites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_invites() RETURNS TABLE(code uuid, typ text, firma text, tel text, email text, created_at timestamp with time zone, eingeloest_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query select e.code, e.typ, e.firma, e.tel, e.email, e.created_at, e.eingeloest_at
               from einladungen e order by (e.eingeloest_at is not null), e.created_at desc limit 200;
end $$;


--
-- Name: admin_kanal_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_kanal_status() RETURNS TABLE(driver_id uuid, telegram boolean, push integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select d.id,
         d.telegram_chat_id is not null,
         (select count(*)::int from push_subs ps where ps.driver_id = d.id)
  from drivers d
  where public.is_admin();
$$;


--
-- Name: admin_log(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_log(p_von date, p_bis date) RETURNS TABLE(id bigint, accepted_at timestamp with time zone, firma text, ort text, probleme text[], released_at timestamp with time zone, storniert_at timestamp with time zone, erlassen boolean, berechnet boolean, request_status text, firmenlink boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return query
    select l.id, l.accepted_at, l.firma, l.ort, l.probleme, l.released_at, l.storniert_at,
           l.erlassen, public.log_berechnet(l), r.status,
           coalesce(r.bevorzugt_driver = l.driver_id and r.exklusiv_bis is not null, false)
    from auftrag_log l left join requests r on r.id = l.request_id
    where l.accepted_at >= p_von and l.accepted_at < p_bis + 1
    order by l.accepted_at desc;
end $$;


--
-- Name: admin_push(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_push(p_title text, p_body text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'Bitte einen Titel eingeben.'; end if;
  return public.push_send((select public.push_subs_json(array_agg(id), null) from drivers where approved),
                          '📣 ' || trim(p_title), trim(coalesce(p_body, '')), public.app_url() || '#fahrer', null);
end $$;


--
-- Name: admin_pw_link(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_pw_link(p_user uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  return public.pw_reset_create(p_user);
end $$;


--
-- Name: admin_qr_add(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_qr_add(p_anzahl integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_max int;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Kein Admin-Zugriff'; end if;
  if p_anzahl is null or p_anzahl < 1 or p_anzahl > 1000 then raise exception 'Anzahl 1–1000'; end if;
  select coalesce(max(nr), 0) into v_max from qr_codes;
  insert into qr_codes (code, nr)
  select 'q' || lpad(g::text, 4, '0'), g from generate_series(v_max + 1, v_max + p_anzahl) g;
  return v_max + p_anzahl;
end;
$$;


--
-- Name: admin_qr_assign(integer, integer, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_qr_assign(p_von integer, p_bis integer, p_driver uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_n int;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Kein Admin-Zugriff'; end if;
  if p_von is null or p_bis is null or p_von < 1 or p_bis < p_von or p_bis - p_von > 999 then
    raise exception 'Ungültiger Bereich';
  end if;
  update qr_codes
     set driver_id = p_driver,
         assigned_at = case when p_driver is null then null else now() end
   where nr between p_von and p_bis;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


--
-- Name: admin_qr_assign2(integer, integer, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_qr_assign2(p_von integer, p_bis integer, p_driver uuid, p_partner text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_n int;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Kein Admin-Zugriff'; end if;
  if p_von is null or p_bis is null or p_von < 1 or p_bis < p_von or p_bis - p_von > 999 then
    raise exception 'Ungültiger Bereich';
  end if;
  if p_driver is not null and p_partner is not null then raise exception 'Nur Firma ODER Partner'; end if;
  update qr_codes
     set driver_id  = p_driver,
         partner_id = (select id from partners where id::text = p_partner),
         assigned_at = case when p_driver is null and p_partner is null then null else now() end
   where nr between p_von and p_bis;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


--
-- Name: admin_qr_list(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_qr_list() RETURNS TABLE(code text, nr integer, driver_id uuid, partner_id text, firma text, typ text, pro boolean, assigned_at timestamp with time zone, scans integer, last_scan timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Kein Admin-Zugriff'; end if;
  return query
    select q.code, q.nr, q.driver_id, q.partner_id::text,
           coalesce(d.firma, p.name),
           case when d.id is not null then coalesce(d.typ,'abschlepper') else p.kategorie end,
           d.pro, q.assigned_at, q.scans, q.last_scan
      from qr_codes q
      left join drivers  d on d.id = q.driver_id
      left join partners p on p.id = q.partner_id
     order by q.nr;
end;
$$;


--
-- Name: admin_set_approved(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_approved(p_id uuid, p_ok boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  update drivers set approved = p_ok, status = case when p_ok then status else 'offline' end where id = p_id;
end $$;


--
-- Name: admin_set_erlassen(bigint, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_erlassen(p_id bigint, p_val boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  update auftrag_log set erlassen = p_val where id = p_id;
end $$;


--
-- Name: admin_set_pro(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_pro(p_id uuid, p_val boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Kein Zugriff'; end if;
  update drivers set pro = p_val,
    pro_frei_bis = case when p_val then 'infinity'::timestamptz else now() end
  where id = p_id;
end $$;


--
-- Name: app_url(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.app_url() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select value from app_settings where key = 'app_url';
$$;


--
-- Name: ar_km(double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ar_km(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
  select 2 * 6371 * asin(least(1, sqrt(
           sin(radians(b_lat - a_lat) / 2) ^ 2
         + cos(radians(a_lat)) * cos(radians(b_lat)) * sin(radians(b_lng - a_lng) / 2) ^ 2)))
$$;


--
-- Name: bewertung_frist(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bewertung_frist() RETURNS interval
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select make_interval(hours => greatest(1, coalesce(
    (select nullif(trim(value), '')::int from app_settings where key = 'bewertung_frist_stunden'), 12)));
$$;


--
-- Name: cancel_request(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_request(p_id uuid, p_token uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  update requests r set status = 'storniert'
  from request_contacts c
  where r.id = p_id and c.request_id = r.id and c.token = p_token and r.status in ('neu','angenommen');
  get diagnostics n = row_count;
  if n = 1 then
    update auftrag_log set storniert_at = now()
    where request_id = p_id and released_at is null and storniert_at is null;
  end if;
  return n = 1;
end $$;


--
-- Name: choose_offer(uuid, uuid, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.choose_offer(p_id uuid, p_token uuid, p_offer bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  where id = p_id and status = 'neu' and wann in ('sofort','termin')
    and (wann <> 'sofort' or created_at > now() - public.sofort_frist());
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
end $$;


--
-- Name: create_request(double precision, double precision, text, text, text, text, text, text[], text, text, text, timestamp with time zone, text, text, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_request(p_lat double precision, p_lng double precision, p_ort text, p_strasse text, p_marke text, p_modell text, p_kennzeichen text, p_probleme text[], p_ziel text, p_notiz text, p_wann text, p_termin timestamp with time zone, p_name text, p_tel text, p_mail text, p_firma text DEFAULT NULL::text, p_ziel_km numeric DEFAULT NULL::numeric) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_id uuid; v_nr bigint; v_token uuid; v_pref uuid;
begin
  if p_lat is null or p_lng is null or p_lat not between 46 and 56 or p_lng not between 2 and 17 then
    raise exception 'Standort ungültig';
  end if;
  if coalesce(char_length(trim(p_strasse)),0) < 2 or char_length(p_strasse) > 200 then
    raise exception 'Bitte Straße bzw. Standort angeben';
  end if;
  if coalesce(char_length(trim(p_marke)),0) < 2 or char_length(p_marke) > 60 then
    raise exception 'Bitte Fahrzeugmarke angeben';
  end if;
  if p_probleme is null or cardinality(p_probleme) = 0 or cardinality(p_probleme) > 7
     or not (p_probleme <@ array['abschleppen','starthilfe','reifen','schluessel','kraftstoff','unfall','sonstiges']) then
    raise exception 'Bitte Problem auswählen';
  end if;
  if p_wann not in ('sofort','termin') then raise exception 'Zeitpunkt ungültig'; end if;
  if p_wann = 'termin' and (p_termin is null or p_termin < now() - interval '1 hour') then
    raise exception 'Bitte gültigen Termin wählen';
  end if;
  if coalesce(char_length(trim(p_name)),0) < 2 or char_length(p_name) > 100 then
    raise exception 'Bitte Namen angeben';
  end if;
  if char_length(regexp_replace(coalesce(p_tel,''), '\D', '', 'g')) < 6 or char_length(p_tel) > 40 then
    raise exception 'Bitte gültige Telefonnummer angeben';
  end if;
  if (select count(*) from request_contacts c join requests r on r.id = c.request_id
      where c.tel = trim(p_tel) and r.status = 'neu' and r.created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Zu viele Anfragen – bitte kurz warten';
  end if;

  -- Firmen-Link: nur wenn die Firma freigeschaltet und nicht offline ist
  if coalesce(trim(p_firma), '') <> '' then
    select id into v_pref from drivers
    where kurz = lower(trim(p_firma)) and approved and pro and status <> 'offline';
  end if;

  insert into requests (lat, lng, ort, strasse, marke, modell, kennzeichen, probleme, ziel, notiz, wann, termin,
                        bevorzugt_driver, exklusiv_bis, alle_benachrichtigt, ziel_km)
  values (p_lat, p_lng, coalesce(left(trim(p_ort),80),''), trim(p_strasse), trim(p_marke),
          left(nullif(trim(p_modell),''),60), left(nullif(trim(p_kennzeichen),''),20), p_probleme,
          left(nullif(trim(p_ziel),''),200), left(nullif(trim(p_notiz),''),500), p_wann,
          case when p_wann = 'termin' then p_termin end,
          v_pref, case when v_pref is not null then now() + interval '5 minutes' end, v_pref is null,
          case when nullif(trim(p_ziel),'') is not null and p_ziel_km between 0 and 2000 then round(p_ziel_km, 1) end)
  returning requests.id, requests.nr into v_id, v_nr;

  insert into request_contacts (request_id, name, tel, mail)
  values (v_id, trim(p_name), trim(p_tel), left(nullif(trim(p_mail),''),120))
  returning request_contacts.token into v_token;

  return json_build_object('id', v_id, 'nr', v_nr, 'token', v_token);
end $$;


--
-- Name: create_werkstatt_request(double precision, double precision, text, text, text, text, timestamp with time zone, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_werkstatt_request(p_lat double precision, p_lng double precision, p_ort text, p_marke text, p_modell text, p_beschreibung text, p_termin timestamp with time zone, p_name text, p_tel text, p_mail text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_id uuid; v_nr bigint; v_token uuid;
begin
  if p_lat is null or p_lng is null or p_lat not between 46 and 56 or p_lng not between 2 and 17 then
    raise exception 'Standort ungültig';
  end if;
  if coalesce(char_length(trim(p_marke)),0) < 2 or char_length(p_marke) > 60 then raise exception 'Bitte Fahrzeugmarke angeben'; end if;
  if coalesce(char_length(trim(p_beschreibung)),0) < 10 or char_length(p_beschreibung) > 1000 then
    raise exception 'Bitte beschreiben Sie das Problem (mindestens 10 Zeichen)';
  end if;
  if p_termin is not null and p_termin < now() - interval '1 day' then raise exception 'Bitte gültigen Wunschtermin wählen'; end if;
  if coalesce(char_length(trim(p_name)),0) < 2 or char_length(p_name) > 100 then raise exception 'Bitte Namen angeben'; end if;
  if char_length(regexp_replace(coalesce(p_tel,''), '\D', '', 'g')) < 6 or char_length(p_tel) > 40 then
    raise exception 'Bitte gültige Telefonnummer angeben';
  end if;
  if (select count(*) from request_contacts c join requests r on r.id = c.request_id
      where c.tel = trim(p_tel) and r.status = 'neu' and r.created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Zu viele Anfragen – bitte kurz warten';
  end if;

  insert into requests (kategorie, lat, lng, ort, strasse, marke, modell, probleme, notiz, wann, termin, alle_benachrichtigt)
  values ('werkstatt', p_lat, p_lng, coalesce(left(trim(p_ort),80),''), '', trim(p_marke),
          left(nullif(trim(p_modell),''),60), array['sonstiges'], left(trim(p_beschreibung),1000), 'termin', p_termin, true)
  returning requests.id, requests.nr into v_id, v_nr;

  insert into request_contacts (request_id, name, tel, mail)
  values (v_id, trim(p_name), trim(p_tel), left(nullif(trim(p_mail),''),120))
  returning request_contacts.token into v_token;

  return json_build_object('id', v_id, 'nr', v_nr, 'token', v_token);
end $$;


--
-- Name: finish_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finish_request(p_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  update requests set status = 'erledigt'
  where id = p_id and accepted_by = auth.uid() and status = 'angenommen';
  get diagnostics n = row_count;
  if n = 1 and not exists (select 1 from requests where accepted_by = auth.uid() and status = 'angenommen') then
    update drivers set status = 'verfuegbar', updated_at = now() where id = auth.uid();
  end if;
  return n = 1;
end $$;


--
-- Name: firma_by_kurz(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.firma_by_kurz(p_kurz text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select firma from drivers where kurz = lower(trim(p_kurz)) and approved and pro limit 1;
$$;


--
-- Name: firma_sterne(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.firma_sterne(p_driver uuid) RETURNS json
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select json_build_object('schnitt', round(avg(sterne)::numeric, 1), 'anzahl', count(*))
  from bewertungen where driver_id = p_driver;
$$;


--
-- Name: get_request_status(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_request_status(p_id uuid, p_token uuid) RETURNS json
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: invite_info(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invite_info(p_code uuid) RETURNS json
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select json_build_object('firma', firma, 'tel', tel, 'email', email, 'typ', typ)
  from einladungen
  where code = p_code and eingeloest_at is null and created_at > now() - interval '60 days';
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;


--
-- Name: is_approved_driver(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_approved_driver() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from drivers where id = auth.uid() and approved);
$$;


--
-- Name: ist_offen(boolean, time without time zone, time without time zone, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ist_offen(p_24h boolean, p_von time without time zone, p_bis time without time zone, p_sa boolean, p_so boolean) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
end $$;


--
-- Name: kostenlos_bis(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kostenlos_bis() RETURNS timestamp with time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((select value from app_settings where key = 'kostenlos_bis')::date, date '2000-01-01')::timestamptz;
$$;


--
-- Name: kostenlos_bis_fuer(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kostenlos_bis_fuer(p_driver uuid) RETURNS timestamp with time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select greatest(
           (select created_at from drivers where id = p_driver),
           coalesce((select value from app_settings where key = 'start_am')::date, date '2026-12-01')::timestamptz
         ) + interval '6 months';
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auftrag_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auftrag_log (
    id bigint NOT NULL,
    request_id uuid,
    driver_id uuid,
    firma text NOT NULL,
    ort text,
    probleme text[],
    accepted_at timestamp with time zone DEFAULT now() NOT NULL,
    released_at timestamp with time zone,
    storniert_at timestamp with time zone,
    erlassen boolean DEFAULT false NOT NULL,
    preis numeric(8,2)
);


--
-- Name: log_berechnet(public.auftrag_log); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_berechnet(l public.auftrag_log) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select not l.erlassen
     and (l.storniert_at is null or l.storniert_at > l.accepted_at + interval '10 minutes')
     and l.accepted_at >= public.kostenlos_bis_fuer(l.driver_id)
     and not exists (select 1 from drivers d where d.id = l.driver_id
                     and d.pro_frei_bis is not null and l.accepted_at < d.pro_frei_bis);
$$;


--
-- Name: my_bewertungen(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_bewertungen() RETURNS json
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select json_build_object(
    'schnitt', (select round(avg(sterne)::numeric, 1) from bewertungen where driver_id = auth.uid()),
    'anzahl',  (select count(*) from bewertungen where driver_id = auth.uid()),
    'letzte',  (select coalesce(json_agg(x), '[]'::json) from (
                  select sterne, text, created_at from bewertungen
                  where driver_id = auth.uid() order by created_at desc limit 5) x));
$$;


--
-- Name: my_qr_codes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_qr_codes() RETURNS TABLE(code text, nr integer, scans integer, last_scan timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select q.code, q.nr, q.scans, q.last_scan
    from qr_codes q
   where q.driver_id = auth.uid()
   order by q.nr;
$$;


--
-- Name: my_typ(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_typ() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select typ from drivers where id = auth.uid();
$$;


--
-- Name: notify_new_driver(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_driver() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_email text; a record; v_text text;
begin
  begin
    select email into v_email from auth.users where id = new.id;
    v_text := case when new.approved then '✅ Eingeladene Firma hat sich registriert (bereits freigeschaltet)'
                   else '🆕 Neue Registrierung bei AbschleppRadar' end
      || E'\n\n' || case when new.typ = 'werkstatt' then '🔧 Werkstatt' else '🚛 Abschleppdienst' end
      || E'\n🏢 ' || new.firma
      || E'\n📞 ' || new.tel
      || coalesce(E'\n✉️ ' || v_email, '')
      || case when new.approved then '' else E'\n\nBitte prüfen und im Admin-Bereich freischalten.' end;
    for a in
      select d.telegram_chat_id from admins ad join drivers d on d.id = ad.user_id
      where d.telegram_chat_id is not null and d.id <> new.id
    loop
      perform public.tg_send(a.telegram_chat_id, v_text, '⚙️ Admin-Bereich öffnen', public.app_url() || '#admin');
    end loop;
  exception when others then
    raise warning 'Admin-Benachrichtigung fehlgeschlagen: %', sqlerrm;
  end;
  return new;
end $$;


--
-- Name: notify_new_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_new_request() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  begin
    perform public.notify_request(new.id, case when new.exklusiv_bis is not null then new.bevorzugt_driver end);
  exception when others then
    raise warning 'Telegram-Benachrichtigung fehlgeschlagen: %', sqlerrm;
  end;
  return new;
end $$;


--
-- Name: notify_request(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_request(p_id uuid, p_only uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
end $_$;


--
-- Name: partner_counts(double precision, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.partner_counts(p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_km double precision DEFAULT 100) RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_admin  boolean := false;
  v_km     double precision;
  v_drv    int; v_abschl int; v_werk int; v_verz int;
  v_gesamt int; v_nah int; v_online int;
begin
  begin
    v_admin := coalesce(public.is_admin(), false);
  exception when others then
    v_admin := false;
  end;

  v_km := case when v_admin then least(greatest(coalesce(p_km, 100), 1), 1000) else 100 end;

  select count(*),
         count(*) filter (where typ = 'abschlepper'),
         count(*) filter (where typ = 'werkstatt')
    into v_drv, v_abschl, v_werk
    from drivers where approved;

  select count(*) into v_verz from partners where aktiv;

  v_gesamt := v_drv + v_verz;

  if p_lat is not null and p_lng is not null then
    v_nah :=
        (select count(*) from drivers d
          where d.approved and d.lat is not null and d.lng is not null
            and public.ar_km(p_lat, p_lng, d.lat, d.lng) <= v_km)
      + (select count(*) from partners p
          where p.aktiv and p.lat is not null and p.lng is not null
            and public.ar_km(p_lat, p_lng, p.lat, p.lng) <= v_km);
  end if;

  if not v_admin then
    return json_build_object(
      'gesamt', case when v_gesamt >= 25 then v_gesamt end,
      'nah',    case when v_nah    >= 25 then v_nah    end);
  end if;

  select count(*) into v_online
    from drivers
   where approved
     and coalesce(status, 'offline') <> 'offline'
     and pos_at > now() - interval '15 minutes';

  return json_build_object(
    'admin', true, 'km', v_km,
    'gesamt', v_gesamt, 'nah', v_nah, 'online', v_online,
    'abschlepper', v_abschl, 'werkstatt', v_werk, 'verzeichnis', v_verz);
end;
$$;


--
-- Name: push_cleanup(text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_cleanup(p_secret text, p_endpoints text[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  if p_secret is distinct from (select value from app_settings where key = 'push_secret') then return 0; end if;
  delete from push_subs where endpoint = any(p_endpoints);
  get diagnostics n = row_count; return n;
end $$;


--
-- Name: push_delete_fahrer(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_delete_fahrer(p_endpoint text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  delete from push_subs where endpoint = p_endpoint and driver_id = auth.uid();
$$;


--
-- Name: push_on_offer(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_on_offer() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare r requests; v_firma text;
begin
  select * into r from requests where id = new.request_id;
  select firma into v_firma from drivers where id = new.driver_id;
  perform public.push_send(public.push_subs_json(null, new.request_id),
    '💶 Neues Angebot für Ihre Anfrage',
    coalesce(v_firma, 'Eine Firma') || ': ' || replace(to_char(new.preis, 'FM99999990.00'), '.', ',') || ' €'
      || coalesce(' – ' || replace(to_char(new.preis_bis, 'FM99999990.00'), '.', ',') || ' €', ''),
    public.app_url() || '#status', 'anfrage-' || r.nr);
  return new;
end $$;


--
-- Name: push_on_request_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_on_request_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_firma text; v_app text := public.app_url();
begin
  if new.status = 'angenommen' and old.status is distinct from 'angenommen' then
    select firma into v_firma from drivers where id = new.accepted_by;
    perform public.push_send(public.push_subs_json(null, new.id),
      case when new.kategorie = 'werkstatt' then '✅ Werkstatt hat zugesagt' else '✅ Ein Abschlepper hat zugesagt' end,
      coalesce(v_firma, '') || coalesce(' · ' || replace(to_char(new.preis, 'FM99999990.00'), '.', ',') || ' €', '')
        || case when new.wann = 'sofort' and new.eta_min is not null then ' · in ca. ' || new.eta_min || ' Min.' else '' end,
      v_app || '#status', 'anfrage-' || new.nr);
    if new.wann = 'termin' or new.kategorie = 'werkstatt' then   -- Kunde hat ein Angebot gewählt
      perform public.push_send(public.push_subs_json(array[new.accepted_by], null),
        '✅ Ihr Angebot wurde angenommen', 'Auftrag Nr. ' || new.nr || ' · ' || coalesce(new.ort, '') || ' – Kundendaten jetzt in der App.',
        v_app || '#fahrer', 'auftrag-' || new.nr);
    end if;
  elsif new.status = 'erledigt' and old.status is distinct from 'erledigt' then
    perform public.push_send(public.push_subs_json(null, new.id),
      '⭐ Wie zufrieden waren Sie?', 'Ihr Auftrag ist erledigt. Bewerten Sie jetzt mit 1–5 Sternen.', v_app || '#status', 'anfrage-' || new.nr);
  end if;
  return new;
end $$;


--
-- Name: push_save_fahrer(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_save_fahrer(p_endpoint text, p_p256dh text, p_auth text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null or not exists (select 1 from drivers where id = auth.uid()) then raise exception 'Bitte anmelden.'; end if;
  if length(p_endpoint) > 1000 or p_endpoint !~ '^https://' then raise exception 'Ungültig.'; end if;
  delete from push_subs where endpoint = p_endpoint and driver_id is not null and driver_id <> auth.uid();
  insert into push_subs (endpoint, p256dh, auth, driver_id, ziel)
  values (p_endpoint, p_p256dh, p_auth, auth.uid(), 'f:' || auth.uid())
  on conflict (endpoint, ziel) do update set p256dh = excluded.p256dh, auth = excluded.auth;
  return true;
end $$;


--
-- Name: push_save_kunde(uuid, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_save_kunde(p_id uuid, p_token uuid, p_endpoint text, p_p256dh text, p_auth text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if not exists (select 1 from request_contacts where request_id = p_id and token = p_token) then raise exception 'Anfrage nicht gefunden.'; end if;
  if length(p_endpoint) > 1000 or p_endpoint !~ '^https://' then raise exception 'Ungültig.'; end if;
  insert into push_subs (endpoint, p256dh, auth, request_id, ziel)
  values (p_endpoint, p_p256dh, p_auth, p_id, 'r:' || p_id)
  on conflict (endpoint, ziel) do update set p256dh = excluded.p256dh, auth = excluded.auth;
  return true;
end $$;


--
-- Name: push_send(jsonb, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_send(p_subs jsonb, p_title text, p_body text, p_url text DEFAULT NULL::text, p_tag text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_url text; v_secret text; n int := coalesce(jsonb_array_length(p_subs), 0);
begin
  if n = 0 then return 0; end if;
  select value into v_url from app_settings where key = 'supabase_url';
  select value into v_secret from app_settings where key = 'push_secret';
  if v_url is null or v_secret is null then return 0; end if;
  perform net.http_post(url := v_url || '/functions/v1/' || coalesce((select value from app_settings where key = 'push_function'), 'push-senden'),
    body := jsonb_build_object('secret', v_secret, 'subs', p_subs, 'title', left(p_title, 120),
                               'body', left(coalesce(p_body, ''), 400), 'url', coalesce(p_url, public.app_url()), 'tag', p_tag),
    headers := '{"Content-Type": "application/json"}'::jsonb);
  return n;
exception when others then
  raise warning 'push_send fehlgeschlagen: %', sqlerrm; return 0;
end $$;


--
-- Name: push_subs_json(uuid[], uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_subs_json(p_drivers uuid[], p_request uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object('endpoint', endpoint, 'p256dh', p256dh, 'auth', auth)), '[]'::jsonb)
  from push_subs
  where (p_drivers is not null and driver_id = any(p_drivers)) or (p_request is not null and request_id = p_request);
$$;


--
-- Name: push_test(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_test() RETURNS integer
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.push_send(public.push_subs_json(array[auth.uid()], null),
    '🔔 Test von AbschleppRadar', 'So sehen neue Aufträge auf Ihrem Handy aus.', public.app_url() || '#fahrer', 'test');
$$;


--
-- Name: pw_reset_create(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pw_reset_create(p_user uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_code uuid;
begin
  if (select count(*) from pw_resets where user_id = p_user and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Zu viele Anfragen – bitte in einer Stunde erneut versuchen';
  end if;
  insert into pw_resets (user_id) values (p_user) returning code into v_code;
  return v_code;
end $$;


--
-- Name: qr_info(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.qr_info(p_code text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare q qr_codes; d drivers; p partners;
begin
  update qr_codes x set scans = x.scans + 1, last_scan = now()
   where x.code = lower(trim(p_code))
  returning * into q;
  if q.code is null then return null; end if;
  if q.driver_id is not null then
    select * into d from drivers where id = q.driver_id and approved;
    if d.id is null then return null; end if;
    if d.typ = 'werkstatt' then
      return json_build_object('typ','werkstatt','name',d.firma);
    end if;
    if d.pro and d.kurz is not null then
      return json_build_object('typ','abschlepper','kurz',d.kurz,'name',d.firma);
    end if;
    return null;
  end if;
  if q.partner_id is not null then
    select * into p from partners where id = q.partner_id and aktiv;
    if p.id is null then return null; end if;
    return json_build_object('typ',p.kategorie,'name',p.name,'adresse',p.adresse,'ort',p.ort,'tel',p.tel);
  end if;
  return null;
end;
$$;


--
-- Name: qr_resolve(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.qr_resolve(p_code text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_kurz text;
begin
  update qr_codes q set scans = q.scans + 1, last_scan = now()
   where q.code = lower(trim(p_code))
  returning (select d.kurz from drivers d
              where d.id = q.driver_id and d.approved and d.pro and d.kurz is not null)
    into v_kurz;
  return v_kurz;
end;
$$;


--
-- Name: rate_request(uuid, uuid, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rate_request(p_id uuid, p_token uuid, p_sterne integer, p_text text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
end $$;


--
-- Name: redeem_invite(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.redeem_invite(p_code uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare e einladungen;
begin
  if auth.uid() is null then raise exception 'Bitte zuerst anmelden'; end if;
  select * into e from einladungen
  where code = p_code and eingeloest_at is null and created_at > now() - interval '60 days'
  for update;
  if e.code is null then return null; end if;

  if exists (select 1 from drivers where id = auth.uid()) then
    update drivers set approved = true, typ = e.typ, firma = e.firma, tel = e.tel where id = auth.uid();
  else
    insert into drivers (id, firma, tel, typ, approved) values (auth.uid(), e.firma, e.tel, e.typ, true);
  end if;
  update einladungen set eingeloest_von = auth.uid(), eingeloest_at = now() where code = e.code;
  return e.firma;
end $$;


--
-- Name: release_exclusive(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.release_exclusive() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare r record;
begin
  for r in select id from requests
           where status = 'neu' and not alle_benachrichtigt and exklusiv_bis <= now() loop
    update requests set alle_benachrichtigt = true where id = r.id;
    perform public.notify_request(r.id, null);
  end loop;
end $$;


--
-- Name: release_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.release_request(p_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  update requests set status = 'neu', accepted_by = null, accepted_at = null, preis = null, eta_min = null
  where id = p_id and accepted_by = auth.uid() and status = 'angenommen';
  get diagnostics n = row_count;
  if n = 1 then
    update auftrag_log set released_at = now()
    where id = (select max(id) from auftrag_log
                where request_id = p_id and driver_id = auth.uid() and released_at is null);
    delete from angebote where request_id = p_id and driver_id = auth.uid();
  end if;
  return n = 1;
end $$;


--
-- Name: reset_password_with_code(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_password_with_code(p_code uuid, p_password text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
declare r pw_resets; v_email text;
begin
  if p_password is null or char_length(p_password) < 8 then raise exception 'Das Passwort muss mindestens 8 Zeichen haben'; end if;
  select * into r from pw_resets
  where code = p_code and used_at is null and created_at > now() - interval '1 hour'
  for update;
  if r.code is null then raise exception 'Dieser Link ist abgelaufen oder wurde schon benutzt. Bitte neu anfordern.'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now()
  where id = r.user_id
  returning email into v_email;
  update pw_resets set used_at = now() where code = r.code;
  return v_email;
end $$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: set_oeffnungszeiten(boolean, time without time zone, time without time zone, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_oeffnungszeiten(p_24h boolean, p_von time without time zone, p_bis time without time zone, p_sa boolean, p_so boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
end $$;


--
-- Name: sofort_frist(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sofort_frist() RETURNS interval
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select make_interval(hours => greatest(1, coalesce(
    (select nullif(trim(value), '')::int from app_settings where key = 'sofort_frist_stunden'), 3)));
$$;


--
-- Name: submit_offer(uuid, numeric, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_offer(p_request uuid, p_preis numeric, p_notiz text, p_preis_bis numeric DEFAULT NULL::numeric, p_termin_vorschlag text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_kat text;
begin
  if not public.is_approved_driver() then raise exception 'Konto noch nicht freigeschaltet'; end if;
  if p_preis is null or p_preis <= 0 or p_preis >= 100000 then raise exception 'Bitte einen gültigen Preis angeben'; end if;
  if p_preis_bis is not null and (p_preis_bis < p_preis or p_preis_bis >= 100000) then
    raise exception 'Der Preis „bis“ muss größer oder gleich „von“ sein';
  end if;
  select kategorie into v_kat from requests
  where id = p_request and status = 'neu' and wann = 'termin'
    and (exklusiv_bis is null or exklusiv_bis <= now() or bevorzugt_driver = auth.uid());
  if v_kat is null then raise exception 'Dieser Auftrag ist nicht mehr verfügbar'; end if;
  if v_kat <> (case when public.my_typ() = 'werkstatt' then 'werkstatt' else 'abschleppen' end) then
    raise exception 'Dieser Auftrag passt nicht zu Ihrem Kontotyp';
  end if;
  if v_kat = 'werkstatt' and coalesce(char_length(trim(p_notiz)), 0) < 10 then
    raise exception 'Bitte begründen Sie Ihre Schätzung (mindestens 10 Zeichen)';
  end if;
  insert into angebote (request_id, driver_id, preis, preis_bis, notiz, termin_vorschlag)
  values (p_request, auth.uid(), round(p_preis, 2), round(p_preis_bis, 2),
          left(nullif(trim(p_notiz), ''), 300), left(nullif(trim(p_termin_vorschlag), ''), 100))
  on conflict (request_id, driver_id)
  do update set preis = excluded.preis, preis_bis = excluded.preis_bis, notiz = excluded.notiz,
                termin_vorschlag = excluded.termin_vorschlag, created_at = now();
  return true;
end $$;


--
-- Name: submit_offer(uuid, numeric, text, numeric, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_offer(p_request uuid, p_preis numeric, p_notiz text, p_preis_bis numeric DEFAULT NULL::numeric, p_termin_vorschlag text DEFAULT NULL::text, p_eta integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_kat text; v_wann text; v_created timestamptz;
begin
  if not public.is_approved_driver() then raise exception 'Konto noch nicht freigeschaltet'; end if;
  if p_preis is null or p_preis <= 0 or p_preis >= 100000 then raise exception 'Bitte einen gültigen Preis angeben'; end if;
  if p_preis_bis is not null and (p_preis_bis < p_preis or p_preis_bis >= 100000) then
    raise exception 'Der Preis „bis“ muss größer oder gleich „von“ sein';
  end if;

  select kategorie, wann, created_at into v_kat, v_wann, v_created from requests
  where id = p_request and status = 'neu' and wann in ('sofort','termin')
    and (exklusiv_bis is null or exklusiv_bis <= now() or bevorzugt_driver = auth.uid());
  if v_kat is null then raise exception 'Dieser Auftrag ist nicht mehr verfügbar'; end if;

  -- abgelaufene Sofort-Anfrage: der Kunde wartet nicht mehr darauf
  if v_wann = 'sofort' and v_created < now() - public.sofort_frist() then
    raise exception 'Diese Sofort-Anfrage ist abgelaufen – bitte nicht mehr anfahren';
  end if;

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
end $$;


--
-- Name: telegram_link(uuid, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.telegram_link(p_code uuid, p_chat bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_id uuid; v_firma text;
begin
  if p_code is null or p_chat is null then return null; end if;
  select id, firma into v_id, v_firma from drivers where telegram_link_code = p_code;
  if v_id is null then return null; end if;
  -- ein Telegram-Chat gehört immer nur zu einem Konto
  update drivers set telegram_chat_id = null where telegram_chat_id = p_chat and id <> v_id;
  -- verknüpfen und Code erneuern (der alte Link funktioniert danach nicht mehr)
  update drivers set telegram_chat_id = p_chat, telegram_link_code = gen_random_uuid() where id = v_id;
  return v_firma;
end $$;


--
-- Name: telegram_unlink(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.telegram_unlink() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  update drivers set telegram_chat_id = null where id = auth.uid();
$$;


--
-- Name: tg_password_reset(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_password_reset(p_chat bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare d record; v_code uuid;
begin
  select id, firma into d from drivers where telegram_chat_id = p_chat limit 1;
  if d.id is null then
    perform public.tg_send(p_chat, 'Mit diesem Telegram ist kein AbschleppRadar-Konto verbunden. Bitte rufen Sie uns an.');
    return;
  end if;
  begin
    v_code := public.pw_reset_create(d.id);
  exception when others then
    perform public.tg_send(p_chat, '⏳ ' || sqlerrm);
    return;
  end;
  perform public.tg_send(p_chat,
    '🔑 Passwort zurücksetzen für „' || d.firma || '“' || E'\n\nTippen Sie auf den Knopf und legen Sie ein neues Passwort fest. Der Link ist 1 Stunde gültig und funktioniert nur einmal.'
    || E'\n\nSie haben das nicht angefordert? Dann ignorieren Sie diese Nachricht.',
    '🔑 Neues Passwort festlegen', public.app_url() || '#passwort-' || v_code);
end $$;


--
-- Name: tg_send(bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tg_send(p_chat bigint, p_text text, p_button text DEFAULT NULL::text, p_url text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_token text; v_body jsonb;
begin
  if p_chat is null then return; end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_bot_token' limit 1;
  if v_token is null then return; end if;
  v_body := jsonb_build_object('chat_id', p_chat, 'text', p_text, 'disable_web_page_preview', true);
  if p_button is not null then
    v_body := v_body || jsonb_build_object('reply_markup', jsonb_build_object('inline_keyboard',
      jsonb_build_array(jsonb_build_array(jsonb_build_object('text', p_button, 'url', p_url)))));
  end if;
  perform net.http_post(url := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
                        body := v_body, headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then
  raise warning 'tg_send fehlgeschlagen: %', sqlerrm;
end $$;


--
-- Name: withdraw_offer(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.withdraw_offer(p_request uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  delete from angebote a using requests r
  where a.request_id = p_request and a.driver_id = auth.uid() and r.id = a.request_id and r.status = 'neu';
  get diagnostics n = row_count;
  return n > 0;
end $$;


--
-- Name: admins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admins (
    user_id uuid NOT NULL
);


--
-- Name: angebote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.angebote (
    id bigint NOT NULL,
    request_id uuid NOT NULL,
    driver_id uuid NOT NULL,
    preis numeric(8,2) NOT NULL,
    notiz text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    preis_bis numeric(8,2),
    termin_vorschlag text,
    eta_min integer,
    CONSTRAINT angebote_notiz_check CHECK ((char_length(notiz) <= 300)),
    CONSTRAINT angebote_preis_bis_check CHECK (((preis_bis IS NULL) OR (preis_bis >= preis))),
    CONSTRAINT angebote_preis_check CHECK (((preis > (0)::numeric) AND (preis < (100000)::numeric))),
    CONSTRAINT angebote_termin_len CHECK (((termin_vorschlag IS NULL) OR (char_length(termin_vorschlag) <= 100)))
);


--
-- Name: angebote_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.angebote ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.angebote_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_settings (
    key text NOT NULL,
    value text NOT NULL
);


--
-- Name: auftrag_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auftrag_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.auftrag_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bewertungen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bewertungen (
    id bigint NOT NULL,
    request_id uuid,
    driver_id uuid NOT NULL,
    sterne integer NOT NULL,
    text text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bewertungen_sterne_check CHECK (((sterne >= 1) AND (sterne <= 5))),
    CONSTRAINT bewertungen_text_check CHECK ((char_length(text) <= 500))
);


--
-- Name: bewertungen_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bewertungen_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bewertungen_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bewertungen_id_seq OWNED BY public.bewertungen.id;


--
-- Name: drivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drivers (
    id uuid NOT NULL,
    firma text NOT NULL,
    tel text NOT NULL,
    approved boolean DEFAULT false NOT NULL,
    status text DEFAULT 'offline'::text NOT NULL,
    lat double precision,
    lng double precision,
    radius_km integer DEFAULT 30 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    telegram_chat_id bigint,
    telegram_link_code uuid DEFAULT gen_random_uuid() NOT NULL,
    kurz text DEFAULT lower(substr(md5((random())::text), 1, 6)) NOT NULL,
    typ text DEFAULT 'abschlepper'::text NOT NULL,
    pro boolean DEFAULT false NOT NULL,
    pro_frei_bis timestamp with time zone,
    pos_at timestamp with time zone,
    notdienst_24h boolean DEFAULT true NOT NULL,
    oeffnung_von time without time zone,
    oeffnung_bis time without time zone,
    offen_sa boolean DEFAULT true NOT NULL,
    offen_so boolean DEFAULT false NOT NULL,
    CONSTRAINT drivers_firma_check CHECK (((char_length(firma) >= 2) AND (char_length(firma) <= 120))),
    CONSTRAINT drivers_radius_km_check CHECK (((radius_km >= 5) AND (radius_km <= 200))),
    CONSTRAINT drivers_status_check CHECK ((status = ANY (ARRAY['verfuegbar'::text, 'im_einsatz'::text, 'offline'::text]))),
    CONSTRAINT drivers_tel_check CHECK (((char_length(tel) >= 5) AND (char_length(tel) <= 40))),
    CONSTRAINT drivers_typ_check CHECK ((typ = ANY (ARRAY['abschlepper'::text, 'werkstatt'::text])))
);


--
-- Name: einladungen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.einladungen (
    code uuid DEFAULT gen_random_uuid() NOT NULL,
    typ text DEFAULT 'abschlepper'::text NOT NULL,
    firma text NOT NULL,
    tel text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    eingeloest_von uuid,
    eingeloest_at timestamp with time zone,
    CONSTRAINT einladungen_email_check CHECK ((char_length(email) <= 120)),
    CONSTRAINT einladungen_firma_check CHECK (((char_length(firma) >= 2) AND (char_length(firma) <= 120))),
    CONSTRAINT einladungen_tel_check CHECK (((char_length(tel) >= 5) AND (char_length(tel) <= 40))),
    CONSTRAINT einladungen_typ_check CHECK ((typ = ANY (ARRAY['abschlepper'::text, 'werkstatt'::text])))
);


--
-- Name: partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partners (
    id bigint NOT NULL,
    kategorie text NOT NULL,
    name text NOT NULL,
    adresse text,
    ort text,
    tel text,
    email text,
    website text,
    beschreibung text,
    lat double precision,
    lng double precision,
    aktiv boolean DEFAULT true NOT NULL,
    zustimmung boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    ohne_termin boolean DEFAULT false NOT NULL,
    anfragen boolean,
    notdienst_24h boolean DEFAULT false NOT NULL,
    oeffnung_von time without time zone,
    oeffnung_bis time without time zone,
    offen_sa boolean DEFAULT false NOT NULL,
    offen_so boolean DEFAULT false NOT NULL,
    CONSTRAINT partners_adresse_check CHECK ((char_length(adresse) <= 160)),
    CONSTRAINT partners_beschreibung_check CHECK ((char_length(beschreibung) <= 400)),
    CONSTRAINT partners_email_check CHECK ((char_length(email) <= 120)),
    CONSTRAINT partners_kategorie_check CHECK ((kategorie = ANY (ARRAY['gutachter'::text, 'werkstatt'::text, 'autowaesche'::text, 'reifenservice'::text]))),
    CONSTRAINT partners_name_check CHECK (((char_length(name) >= 2) AND (char_length(name) <= 120))),
    CONSTRAINT partners_ort_check CHECK ((char_length(ort) <= 80)),
    CONSTRAINT partners_tel_check CHECK ((char_length(tel) <= 40)),
    CONSTRAINT partners_website_check CHECK ((char_length(website) <= 200))
);


--
-- Name: partners_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.partners ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.partners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: push_subs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subs (
    id bigint NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    driver_id uuid,
    request_id uuid,
    ziel text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: push_subs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.push_subs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: push_subs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.push_subs_id_seq OWNED BY public.push_subs.id;


--
-- Name: pw_resets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pw_resets (
    code uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    used_at timestamp with time zone
);


--
-- Name: qr_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qr_codes (
    code text NOT NULL,
    nr integer NOT NULL,
    driver_id uuid,
    assigned_at timestamp with time zone,
    scans integer DEFAULT 0 NOT NULL,
    last_scan timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    partner_id bigint
);


--
-- Name: request_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_contacts (
    request_id uuid NOT NULL,
    name text NOT NULL,
    tel text NOT NULL,
    mail text,
    token uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nr bigint NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    ort text NOT NULL,
    strasse text NOT NULL,
    marke text NOT NULL,
    modell text,
    kennzeichen text,
    probleme text[] NOT NULL,
    ziel text,
    notiz text,
    wann text NOT NULL,
    termin timestamp with time zone,
    status text DEFAULT 'neu'::text NOT NULL,
    accepted_by uuid,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    preis numeric(8,2),
    eta_min integer,
    bevorzugt_driver uuid,
    exklusiv_bis timestamp with time zone,
    alle_benachrichtigt boolean DEFAULT true NOT NULL,
    kategorie text DEFAULT 'abschleppen'::text NOT NULL,
    preis_bis numeric(8,2),
    ziel_km numeric(7,1),
    CONSTRAINT requests_kategorie_check CHECK ((kategorie = ANY (ARRAY['abschleppen'::text, 'werkstatt'::text]))),
    CONSTRAINT requests_status_check CHECK ((status = ANY (ARRAY['neu'::text, 'angenommen'::text, 'erledigt'::text, 'storniert'::text]))),
    CONSTRAINT requests_wann_check CHECK ((wann = ANY (ARRAY['sofort'::text, 'termin'::text])))
);


--
-- Name: requests_nr_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.requests ALTER COLUMN nr ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.requests_nr_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bewertungen id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bewertungen ALTER COLUMN id SET DEFAULT nextval('public.bewertungen_id_seq'::regclass);


--
-- Name: push_subs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subs ALTER COLUMN id SET DEFAULT nextval('public.push_subs_id_seq'::regclass);


--
-- Name: admins admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (user_id);


--
-- Name: angebote angebote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.angebote
    ADD CONSTRAINT angebote_pkey PRIMARY KEY (id);


--
-- Name: angebote angebote_request_id_driver_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.angebote
    ADD CONSTRAINT angebote_request_id_driver_id_key UNIQUE (request_id, driver_id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);


--
-- Name: auftrag_log auftrag_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auftrag_log
    ADD CONSTRAINT auftrag_log_pkey PRIMARY KEY (id);


--
-- Name: bewertungen bewertungen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bewertungen
    ADD CONSTRAINT bewertungen_pkey PRIMARY KEY (id);


--
-- Name: bewertungen bewertungen_request_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bewertungen
    ADD CONSTRAINT bewertungen_request_id_key UNIQUE (request_id);


--
-- Name: drivers drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_pkey PRIMARY KEY (id);


--
-- Name: einladungen einladungen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.einladungen
    ADD CONSTRAINT einladungen_pkey PRIMARY KEY (code);


--
-- Name: partners partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partners
    ADD CONSTRAINT partners_pkey PRIMARY KEY (id);


--
-- Name: push_subs push_subs_endpoint_ziel_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subs
    ADD CONSTRAINT push_subs_endpoint_ziel_key UNIQUE (endpoint, ziel);


--
-- Name: push_subs push_subs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subs
    ADD CONSTRAINT push_subs_pkey PRIMARY KEY (id);


--
-- Name: pw_resets pw_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pw_resets
    ADD CONSTRAINT pw_resets_pkey PRIMARY KEY (code);


--
-- Name: qr_codes qr_codes_nr_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_codes
    ADD CONSTRAINT qr_codes_nr_key UNIQUE (nr);


--
-- Name: qr_codes qr_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_codes
    ADD CONSTRAINT qr_codes_pkey PRIMARY KEY (code);


--
-- Name: request_contacts request_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_contacts
    ADD CONSTRAINT request_contacts_pkey PRIMARY KEY (request_id);


--
-- Name: requests requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_pkey PRIMARY KEY (id);


--
-- Name: auftrag_log_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auftrag_log_time_idx ON public.auftrag_log USING btree (accepted_at);


--
-- Name: bewertungen_driver_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bewertungen_driver_idx ON public.bewertungen USING btree (driver_id, created_at DESC);


--
-- Name: drivers_kurz_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX drivers_kurz_idx ON public.drivers USING btree (kurz);


--
-- Name: partners_kat_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX partners_kat_idx ON public.partners USING btree (kategorie) WHERE aktiv;


--
-- Name: push_subs_driver_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX push_subs_driver_idx ON public.push_subs USING btree (driver_id);


--
-- Name: push_subs_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX push_subs_request_idx ON public.push_subs USING btree (request_id);


--
-- Name: requests_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requests_status_idx ON public.requests USING btree (status, created_at DESC);


--
-- Name: angebote angebote_push; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER angebote_push AFTER INSERT ON public.angebote FOR EACH ROW EXECUTE FUNCTION public.push_on_offer();


--
-- Name: drivers drivers_notify_admin; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER drivers_notify_admin AFTER INSERT ON public.drivers FOR EACH ROW EXECUTE FUNCTION public.notify_new_driver();


--
-- Name: requests requests_notify_telegram; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER requests_notify_telegram AFTER INSERT ON public.requests FOR EACH ROW EXECUTE FUNCTION public.notify_new_request();


--
-- Name: requests requests_push_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER requests_push_status AFTER UPDATE OF status ON public.requests FOR EACH ROW EXECUTE FUNCTION public.push_on_request_change();


--
-- Name: admins admins_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: angebote angebote_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.angebote
    ADD CONSTRAINT angebote_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: angebote angebote_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.angebote
    ADD CONSTRAINT angebote_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.requests(id) ON DELETE CASCADE;


--
-- Name: auftrag_log auftrag_log_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auftrag_log
    ADD CONSTRAINT auftrag_log_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: auftrag_log auftrag_log_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auftrag_log
    ADD CONSTRAINT auftrag_log_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.requests(id) ON DELETE SET NULL;


--
-- Name: bewertungen bewertungen_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bewertungen
    ADD CONSTRAINT bewertungen_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: bewertungen bewertungen_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bewertungen
    ADD CONSTRAINT bewertungen_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.requests(id) ON DELETE SET NULL;


--
-- Name: drivers drivers_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: einladungen einladungen_eingeloest_von_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.einladungen
    ADD CONSTRAINT einladungen_eingeloest_von_fkey FOREIGN KEY (eingeloest_von) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: push_subs push_subs_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subs
    ADD CONSTRAINT push_subs_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: push_subs push_subs_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subs
    ADD CONSTRAINT push_subs_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.requests(id) ON DELETE CASCADE;


--
-- Name: pw_resets pw_resets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pw_resets
    ADD CONSTRAINT pw_resets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: qr_codes qr_codes_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_codes
    ADD CONSTRAINT qr_codes_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: qr_codes qr_codes_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_codes
    ADD CONSTRAINT qr_codes_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(id) ON DELETE SET NULL;


--
-- Name: request_contacts request_contacts_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_contacts
    ADD CONSTRAINT request_contacts_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.requests(id) ON DELETE CASCADE;


--
-- Name: requests requests_accepted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: requests requests_bevorzugt_driver_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_bevorzugt_driver_fkey FOREIGN KEY (bevorzugt_driver) REFERENCES public.drivers(id) ON DELETE SET NULL;


--
-- Name: admins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

--
-- Name: angebote; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.angebote ENABLE ROW LEVEL SECURITY;

--
-- Name: angebote angebote_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY angebote_select_own ON public.angebote FOR SELECT TO authenticated USING ((driver_id = auth.uid()));


--
-- Name: app_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: auftrag_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auftrag_log ENABLE ROW LEVEL SECURITY;

--
-- Name: bewertungen; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bewertungen ENABLE ROW LEVEL SECURITY;

--
-- Name: request_contacts contacts_select_driver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contacts_select_driver ON public.request_contacts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.requests r
  WHERE ((r.id = request_contacts.request_id) AND (r.accepted_by = auth.uid())))));


--
-- Name: drivers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

--
-- Name: drivers drivers_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drivers_insert_own ON public.drivers FOR INSERT TO authenticated WITH CHECK (((id = auth.uid()) AND (approved = false)));


--
-- Name: drivers drivers_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drivers_select_own ON public.drivers FOR SELECT TO authenticated USING ((id = auth.uid()));


--
-- Name: drivers drivers_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY drivers_update_own ON public.drivers FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: einladungen; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.einladungen ENABLE ROW LEVEL SECURITY;

--
-- Name: partners; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;

--
-- Name: partners partners_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partners_admin_delete ON public.partners FOR DELETE TO authenticated USING (public.is_admin());


--
-- Name: partners partners_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partners_admin_insert ON public.partners FOR INSERT TO authenticated WITH CHECK (public.is_admin());


--
-- Name: partners partners_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partners_admin_update ON public.partners FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: partners partners_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY partners_public_read ON public.partners FOR SELECT TO authenticated, anon USING ((aktiv OR public.is_admin()));


--
-- Name: push_subs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_subs ENABLE ROW LEVEL SECURITY;

--
-- Name: pw_resets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pw_resets ENABLE ROW LEVEL SECURITY;

--
-- Name: qr_codes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.qr_codes ENABLE ROW LEVEL SECURITY;

--
-- Name: request_contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.request_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

--
-- Name: requests requests_select_driver; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY requests_select_driver ON public.requests FOR SELECT TO authenticated USING ((public.is_approved_driver() AND (kategorie =
CASE
    WHEN (public.my_typ() = 'werkstatt'::text) THEN 'werkstatt'::text
    ELSE 'abschleppen'::text
END) AND (((status = 'neu'::text) AND ((exklusiv_bis IS NULL) OR (exklusiv_bis <= now()) OR (bevorzugt_driver = auth.uid()))) OR (accepted_by = auth.uid()))));


--
-- PostgreSQL database dump complete
--

\unrestrict TXmmEAmAcTa0MfYISWMVnXfSmYc0TWK7Crfjbq4erWHX3PEIIP6ZHwV6r7mAI1n


-- ===================================================
-- Cron-Jobs (Stand 2026-11-25)
-- ===================================================
-- 21 | abschleppradar-loeschung | 0 3 * * * | t |  delete from public.requests where created_at < now() - interval '6 months' 
-- 22 | abschleppradar-exklusiv | * * * * * | t | select public.release_exclusive()
-- 24 | sil-pw-resets | 0 3 * * * | t |  delete from public.pw_resets where created_at < now() - interval '1 day' 
