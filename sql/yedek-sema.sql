-- =====================================================================
-- AbschleppRadar · Supabase ŞEMA YEDEĞİ
-- Hazırlayan: Claude · 25.11.2026
-- =====================================================================
--
-- NEDEN: Supabase ücretsiz pakette OTOMATİK YEDEK YOK. Veritabanı
-- silinir veya proje kapanırsa, tablolar / fonksiyonlar / güvenlik
-- kuralları / cron işleri tamamen kaybolur. Repodaki sql/ klasöründe
-- sadece Kasım ortasından sonraki EK özellikler var -- temel yapı
-- hiçbir yerde yazılı değil, yalnızca Supabase'in içinde duruyor.
--
-- NE YAPAR: Aşağıdaki 7 sorgu, veritabanının YAPISINI metin olarak
-- çıkarır. Müşteri verisi ÇIKARMAZ (o ayrı, aşağıdaki nota bak).
--
-- NASIL: Supabase -> SQL Editor. Sorguları TEK TEK çalıştır.
-- Her sonucun altındaki "Download CSV" ile indir.
-- Dosyaları PC'de 03_Supabase_Yedek klasörüne, tarihli isimle koy:
--   2026-11-25_fonksiyonlar.csv  gibi.
-- İkinci kopya USB'ye.
--
-- NE SIKLIKLA: Ayda bir, ve her büyük SQL değişikliğinden sonra.
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) FONKSİYONLAR  --  EN ÖNEMLİSİ, bunu atlamak olmaz
--    Tüm RPC'ler, SECURITY DEFINER fonksiyonlar, tetikleyici
--    fonksiyonları tam gövdeleriyle gelir.
-- ---------------------------------------------------------------------
select p.proname                as fonksiyon,
       pg_get_functiondef(p.oid) as tanim
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public'
order  by p.proname;


-- ---------------------------------------------------------------------
-- 2) TABLOLAR VE SÜTUNLAR
--    Hangi tablo, hangi sütun, hangi tip, varsayılan değer.
-- ---------------------------------------------------------------------
select table_name       as tablo,
       ordinal_position as sira,
       column_name      as sutun,
       data_type        as tip,
       is_nullable      as bos_olabilir,
       column_default   as varsayilan
from   information_schema.columns
where  table_schema = 'public'
order  by table_name, ordinal_position;


-- ---------------------------------------------------------------------
-- 3) KISITLAR (birincil anahtar, yabancı anahtar, unique, check)
--    Tabloların birbirine nasıl bağlandığı burada.
-- ---------------------------------------------------------------------
select conrelid::regclass          as tablo,
       conname                     as kisit,
       pg_get_constraintdef(oid)   as tanim
from   pg_constraint
where  connamespace = 'public'::regnamespace
order  by 1, 2;


-- ---------------------------------------------------------------------
-- 4) RLS GÜVENLİK KURALLARI
--    Kimin hangi satırı görebildiği. Bunlar kaybolursa veri ya
--    tamamen açık ya tamamen kapalı kalır.
-- ---------------------------------------------------------------------
select tablename  as tablo,
       policyname as kural,
       permissive,
       roles,
       cmd        as islem,
       qual       as okuma_kosulu,
       with_check as yazma_kosulu
from   pg_policies
where  schemaname = 'public'
order  by tablename, policyname;


-- ---------------------------------------------------------------------
-- 5) TETİKLEYİCİLER (trigger)
-- ---------------------------------------------------------------------
select event_object_table  as tablo,
       trigger_name        as tetikleyici,
       action_timing       as ne_zaman,
       event_manipulation  as olay,
       action_statement    as calistirdigi
from   information_schema.triggers
where  trigger_schema = 'public'
order  by event_object_table, trigger_name;


-- ---------------------------------------------------------------------
-- 6) İNDEKSLER
--    Performans için. Kaybolursa sistem yavaşlar ama çalışır.
-- ---------------------------------------------------------------------
select tablename as tablo,
       indexname as indeks,
       indexdef  as tanim
from   pg_indexes
where  schemaname = 'public'
order  by tablename, indexname;


-- ---------------------------------------------------------------------
-- 7) CRON İŞLERİ
--    abschleppradar-loeschung (günlük 03:00) ve
--    abschleppradar-exklusiv (her dakika) burada görünmeli.
--    Görünmüyorlarsa bir sorun var -- bana söyle.
-- ---------------------------------------------------------------------
select jobid,
       jobname  as isim,
       schedule as zamanlama,
       command  as komut,
       active   as aktif
from   cron.job
order  by jobid;


-- =====================================================================
-- VERİ YEDEĞİ -- AYRI VE DİKKATLİ
-- =====================================================================
--
-- Yukarıdakiler YAPIYI yedekler, VERİYİ değil. Veri için Supabase
-- Table Editor -> her tablo -> Export -> CSV:
--   drivers, partners, qr_codes, requests, auftrag_log, app_settings
--
-- ⚠️ İKİ UYARI:
--
-- 1) requests tablosu MÜŞTERİ VERİSİ içerir (isim, telefon, adres).
--    Bu CSV asla GitHub'a, e-postaya veya buluta gitmez.
--    Sadece PC + USB.
--
-- 2) app_settings tablosu push_secret içerir.
--    Bu CSV'yi de kimseyle paylaşma, ekran görüntüsünü de alma.
--
-- Yapı dosyalarında (1-7) müşteri verisi ve sır YOKTUR, onlar güvenli.
-- =====================================================================
