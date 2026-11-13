-- =====================================================================
--  MGEO PDF – banco de dados e regras de segurança (Supabase / Postgres)
--  Cole tudo no Supabase → SQL Editor → Run. Pode rodar de novo sem medo.
-- =====================================================================

-- E-mails que viram ADM master automaticamente (sem senha aqui!)
create or replace function public.mgeo_admins() returns text[]
language sql immutable as $$
  select array['benati@mgeotecnologia.com', 'lucas@mgeotecnologia.com']
$$;

-- ---------- configurações gerais ----------
create table if not exists public.app_config (
  id            int primary key default 1 check (id = 1),
  auto_aprovar  boolean not null default true,      -- novos cadastros entram liberados
  atualizado_em timestamptz not null default now()
);
insert into public.app_config (id) values (1) on conflict do nothing;

-- ---------- regra do lead quente ----------
-- usina/fornecedor + gerente/supervisor + acima de 5.000 ha
create or replace function public.mgeo_quente(p_perfil text, p_funcao text, p_area text)
returns boolean language sql immutable as $$
  select coalesce(
    p_perfil in ('usina','fornecedor')
    and p_funcao in ('gerente','supervisor')
    and p_area in ('5000_20000','acima_20000'), false)
$$;

-- ---------- perfis ----------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  nome          text not null default '',
  whatsapp      text,
  email         text,
  verificado    boolean not null default false,          -- WhatsApp/e-mail confirmado
  perfil        text check (perfil in ('usina','fornecedor','produtor','consultor','outro')),
  funcao        text check (funcao in ('gerente','supervisor','tecnico','operador')),
  municipio     text,
  uf            text check (uf ~ '^[A-Z]{2}$'),
  lgpd_aceite   boolean not null default false,
  lgpd_em       timestamptz,
  empresa       text,
  area_faixa    text check (area_faixa in ('ate_500','500_1000','1000_5000','5000_20000','acima_20000')),
  interesses    text[] not null default '{}',
  role          text not null default 'cliente' check (role in ('cliente','admin')),
  status        text not null default 'ativo' check (status in ('pendente','ativo','bloqueado')),
  quente        boolean generated always as (public.mgeo_quente(perfil, funcao, area_faixa)) stored,
  quente_desde  timestamptz,
  contatado_em  timestamptz,
  obs           text,
  ultimo_acesso timestamptz,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists profiles_quente_idx on public.profiles (quente, contatado_em);
create index if not exists profiles_criado_idx on public.profiles (criado_em desc);

-- ---------- é ADM? (usado nas regras) ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'admin' and status = 'ativo')
$$;

-- ---------- novo usuário → cria o perfil ----------
create or replace function public.mgeo_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m        jsonb   := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  eh_admin boolean := lower(coalesce(new.email, '')) = any (public.mgeo_admins());
  auto     boolean := coalesce((select auto_aprovar from public.app_config where id = 1), true);
  tel      text    := nullif(ltrim(coalesce(new.phone, ''), '+'), '');
  lgpd     boolean := coalesce((m->>'lgpd') = 'true', false);
begin
  insert into public.profiles
    (id, nome, whatsapp, email, verificado, perfil, funcao, municipio, uf, lgpd_aceite, lgpd_em, role, status)
  values (
    new.id,
    coalesce(nullif(trim(m->>'nome'), ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Usuário'),
    case when tel is not null then '+' || tel else nullif(m->>'whatsapp', '') end,
    new.email,
    new.phone_confirmed_at is not null or new.email_confirmed_at is not null,
    case when m->>'perfil' in ('usina','fornecedor','produtor','consultor','outro') then m->>'perfil' end,
    case when m->>'funcao' in ('gerente','supervisor','tecnico','operador') then m->>'funcao' end,
    nullif(trim(m->>'municipio'), ''),
    case when upper(m->>'uf') ~ '^[A-Z]{2}$' then upper(m->>'uf') end,
    lgpd,
    case when lgpd then now() end,
    case when eh_admin then 'admin' else 'cliente' end,
    case
      when eh_admin then 'ativo'
      when tel is not null and auto then 'ativo'      -- cadastro pelo app (WhatsApp)
      else 'pendente'                                  -- e-mail: só o ADM libera
    end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists mgeo_on_auth_user_created on auth.users;
create trigger mgeo_on_auth_user_created
  after insert on auth.users for each row execute function public.mgeo_novo_usuario();

-- ---------- código do WhatsApp confirmado → marca verificado ----------
create or replace function public.mgeo_usuario_confirmado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.phone_confirmed_at is not null and old.phone_confirmed_at is null)
     or (new.email_confirmed_at is not null and old.email_confirmed_at is null) then
    update public.profiles
       set verificado = true,
           whatsapp   = coalesce(case when coalesce(new.phone, '') <> '' then '+' || ltrim(new.phone, '+') end, whatsapp)
     where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists mgeo_on_auth_user_confirmed on auth.users;
create trigger mgeo_on_auth_user_confirmed
  after update on auth.users for each row execute function public.mgeo_usuario_confirmado();

-- ---------- proteção: cliente não muda papel, status, etc. ----------
create or replace function public.mgeo_protege_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(auth.jwt()->>'role', '') = 'authenticated'
     and not public.is_admin() then
    new.role         := old.role;
    new.status       := old.status;
    new.whatsapp     := old.whatsapp;
    new.email        := old.email;
    new.verificado   := old.verificado;
    new.contatado_em := old.contatado_em;
    new.obs          := old.obs;
    new.criado_em    := old.criado_em;
    new.lgpd_em      := old.lgpd_em;
    new.quente_desde := old.quente_desde;
  end if;

  if tg_op = 'UPDATE' and new.lgpd_aceite and not coalesce(old.lgpd_aceite, false) then
    new.lgpd_em := now();
  end if;

  -- marca a hora em que virou lead quente (prazo de 48 h para ligar)
  if public.mgeo_quente(new.perfil, new.funcao, new.area_faixa) then
    if tg_op = 'INSERT' or not public.mgeo_quente(old.perfil, old.funcao, old.area_faixa) then
      new.quente_desde := now();
    end if;
  else
    new.quente_desde := null;
  end if;

  new.atualizado_em := now();
  return new;
end $$;

drop trigger if exists mgeo_profiles_guard on public.profiles;
create trigger mgeo_profiles_guard
  before insert or update on public.profiles for each row execute function public.mgeo_protege_perfil();

-- ---------- regras de acesso (RLS) ----------
alter table public.profiles   enable row level security;
alter table public.app_config enable row level security;

drop policy if exists "perfil: ver o próprio ou ADM" on public.profiles;
create policy "perfil: ver o próprio ou ADM" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

drop policy if exists "perfil: editar o próprio" on public.profiles;
create policy "perfil: editar o próprio" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "perfil: ADM edita todos" on public.profiles;
create policy "perfil: ADM edita todos" on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "perfil: ADM exclui" on public.profiles;
create policy "perfil: ADM exclui" on public.profiles
  for delete to authenticated using (public.is_admin());

drop policy if exists "config: ler" on public.app_config;
create policy "config: ler" on public.app_config
  for select to authenticated using (true);

drop policy if exists "config: ADM altera" on public.app_config;
create policy "config: ADM altera" on public.app_config
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- visitantes sem login não enxergam nada
revoke all on public.profiles   from anon;
revoke all on public.app_config from anon;

-- ---------- se os ADMs já existirem antes deste script ----------
insert into public.profiles (id, nome, email, verificado, role, status)
select u.id, split_part(u.email, '@', 1), u.email, true, 'admin', 'ativo'
  from auth.users u
 where lower(u.email) = any (public.mgeo_admins())
on conflict (id) do update set role = 'admin', status = 'ativo';
