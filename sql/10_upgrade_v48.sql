-- v48: E-MAIL THAT WORKS EVERYWHERE.
-- The e-mail is sent by your Supabase database (pg_net) straight to Brevo, so no Netlify function is needed
-- and it works from any address (Netlify, GitHub Pages, Live Server, a folder on your computer).
-- The Brevo key is kept in a table that the browser can NOT read; it is entered once on the Email page.
-- Run this file ONCE in the Supabase SQL editor (after 09). Safe to run again.

create extension if not exists pg_net;

create table if not exists mail_settings (
  id           int primary key default 1 check (id = 1),
  api_key      text,
  sender_email text,
  sender_name  text,
  reply_to     text,
  updated_at   timestamptz default now()
);
alter table mail_settings enable row level security;          -- no policy: nobody can read it directly
revoke all on mail_settings from anon, authenticated;

-- what is saved (the key itself is never returned, only its last 4 characters)
create or replace function mail_settings_get(t text) returns json language plpgsql security definer set search_path=public as $$
declare m mail_settings;
begin perform _admin(t);
  select * into m from mail_settings where id=1;
  return json_build_object(
    'configured', coalesce(m.api_key,'')<>'' and coalesce(m.sender_email,'')<>'',
    'has_key',    coalesce(m.api_key,'')<>'',
    'key_hint',   case when coalesce(m.api_key,'')<>'' then '••••' || right(m.api_key,4) else '' end,
    'sender_email', coalesce(m.sender_email,''), 'sender_name', coalesce(m.sender_name,''), 'reply_to', coalesce(m.reply_to,''));
end $$;

-- save: an empty p_key keeps the key that is already saved
create or replace function mail_settings_set(t text, p_key text, p_email text, p_name text, p_reply text) returns void language plpgsql security definer set search_path=public as $$
begin perform _admin(t);
  if coalesce(trim(p_email),'') !~ '^\S+@\S+\.\S+$' then raise exception 'Type a valid sender e-mail'; end if;
  insert into mail_settings(id, api_key, sender_email, sender_name, reply_to, updated_at)
  values (1, nullif(trim(p_key),''), trim(p_email), nullif(trim(p_name),''), nullif(trim(p_reply),''), now())
  on conflict (id) do update set
    api_key      = coalesce(nullif(trim(p_key),''), mail_settings.api_key),
    sender_email = trim(p_email),
    sender_name  = nullif(trim(p_name),''),
    reply_to     = nullif(trim(p_reply),''),
    updated_at   = now();
end $$;

-- send: ONE request to Brevo, same method as the working Nagarjuna app: visible "To" = the admin, the students in BCC.
-- (older 5-argument version removed)
drop function if exists mail_send(text,text,text,text,jsonb);
create or replace function mail_send(t text, subject text, html text, txt text, recipients jsonb, visible jsonb default '[]'::jsonb) returns bigint language plpgsql security definer set search_path=public as $$
declare m mail_settings; rid bigint; payload jsonb; bcc_l jsonb; to_l jsonb;
begin perform _admin(t);
  select * into m from mail_settings where id=1;
  if coalesce(m.api_key,'')='' then raise exception 'Brevo API key is not saved. Open Email > E-mail settings.'; end if;
  if coalesce(m.sender_email,'')='' then raise exception 'Sender e-mail is not saved. Open Email > E-mail settings.'; end if;
  if coalesce(subject,'')='' or coalesce(html,'')='' then raise exception 'Subject and message are required'; end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('email', x->>'email', 'name', nullif(x->>'name','')))), '[]'::jsonb)
    into bcc_l from jsonb_array_elements(coalesce(recipients,'[]'::jsonb)) x where (x->>'email') ~ '^\S+@\S+\.\S+$';
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('email', x->>'email', 'name', nullif(x->>'name','')))), '[]'::jsonb)
    into to_l from jsonb_array_elements(coalesce(visible,'[]'::jsonb)) x where (x->>'email') ~ '^\S+@\S+\.\S+$';
  if jsonb_array_length(to_l)=0 then to_l := jsonb_build_array(jsonb_build_object('email', coalesce(m.reply_to, m.sender_email), 'name', coalesce(m.sender_name,'Portal'))); end if;
  if jsonb_array_length(bcc_l)>99 then raise exception 'Too many recipients in one request (max 99)'; end if;
  payload := jsonb_build_object(
    'sender',  jsonb_strip_nulls(jsonb_build_object('name', coalesce(m.sender_name,'Portal'), 'email', m.sender_email)),
    'replyTo', jsonb_strip_nulls(jsonb_build_object('name', coalesce(m.sender_name,'Portal'), 'email', coalesce(m.reply_to, m.sender_email))),
    'to', to_l, 'subject', left(subject,300), 'htmlContent', html, 'textContent', coalesce(txt,''), 'tags', jsonb_build_array('portal'));
  if jsonb_array_length(bcc_l)>0 then payload := payload || jsonb_build_object('bcc', bcc_l); end if;
  select net.http_post(url := 'https://api.brevo.com/v3/smtp/email', body := payload,
    headers := jsonb_build_object('api-key', m.api_key, 'content-type', 'application/json', 'accept', 'application/json'),
    timeout_milliseconds := 20000) into rid;
  return rid;
end $$;

-- setup check: asks Brevo for the account and the sender list (answers are read with mail_result)
create or replace function mail_check(t text) returns json language plpgsql security definer set search_path=public as $$
declare m mail_settings; a bigint; s bigint;
begin perform _admin(t);
  select * into m from mail_settings where id=1;
  if coalesce(m.api_key,'')<>'' then
    select net.http_get(url := 'https://api.brevo.com/v3/account', headers := jsonb_build_object('api-key', m.api_key, 'accept', 'application/json'), timeout_milliseconds := 15000) into a;
    select net.http_get(url := 'https://api.brevo.com/v3/senders', headers := jsonb_build_object('api-key', m.api_key, 'accept', 'application/json'), timeout_milliseconds := 15000) into s;
  end if;
  return json_build_object('has_key', coalesce(m.api_key,'')<>'', 'sender_email', coalesce(m.sender_email,''), 'rid_account', a, 'rid_senders', s);
end $$;

-- answer of a request: { pending:true } until Brevo has answered, then { status, body, error }
create or replace function mail_result(t text, rid bigint) returns json language plpgsql security definer set search_path=public as $$
declare r record; b jsonb;
begin perform _admin(t);
  select status_code, content, error_msg, timed_out into r from net._http_response where id = rid;
  if not found then return json_build_object('pending', true); end if;
  begin b := r.content::jsonb; exception when others then b := jsonb_build_object('message', left(coalesce(r.content,''), 300)); end;
  return json_build_object('pending', false, 'status', r.status_code, 'body', b,
    'error', case when r.timed_out then 'Brevo did not answer in time' else r.error_msg end);
end $$;

revoke all on function mail_settings_get(text), mail_settings_set(text,text,text,text,text), mail_send(text,text,text,text,jsonb,jsonb), mail_check(text), mail_result(text,bigint) from public;
grant execute on function mail_settings_get(text), mail_settings_set(text,text,text,text,text), mail_send(text,text,text,text,jsonb,jsonb), mail_check(text), mail_result(text,bigint) to anon, authenticated;
