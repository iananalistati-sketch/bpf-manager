-- Administrative user writes with server-side authorization and atomic audit.
-- This migration does NOT implement pending-user approval/onboarding.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Audit is append-only for application roles. No direct client read/write is granted yet.
create table public.auditoria_eventos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on update no action on delete no action,
  unidade_id uuid null references public.unidades(id) on update no action on delete no action,
  ator_id uuid not null references public.usuarios(id) on update no action on delete no action,
  entidade text not null,
  registro_id uuid not null,
  acao text not null,
  antes jsonb null,
  depois jsonb null,
  justificativa text not null,
  contexto jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint auditoria_eventos_justificativa_check check (length(btrim(justificativa)) >= 5),
  constraint auditoria_eventos_entidade_check check (length(btrim(entidade)) > 0),
  constraint auditoria_eventos_acao_check check (length(btrim(acao)) > 0)
);

create index idx_auditoria_eventos_empresa_data
  on public.auditoria_eventos (empresa_id, created_at desc);
create index idx_auditoria_eventos_registro_data
  on public.auditoria_eventos (entidade, registro_id, created_at desc);

alter table public.auditoria_eventos enable row level security;
revoke all on table public.auditoria_eventos from public, anon, authenticated, service_role;

-- Profile administration requires a stronger fixed permission set than user list/status management.
-- Expand only the restricted reader's permission-code visibility; this does not grant client access.
alter policy permissoes_authz_reader_codigos on public.permissoes
  using (codigo in (
    'configuracoes.visualizar',
    'usuarios.gerenciar',
    'perfis.gerenciar'
  ));

grant bpf_authz_reader to postgres with inherit false, set true;
grant create on schema private to bpf_authz_reader;
set role bpf_authz_reader;

create function private.empresa_gestao_perfis()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where nullif(current_setting('request.jwt.claim.sub', true), '')::uuid is not null
    and u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo
    and u.status = 'ativo'
    and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'usuarios.gerenciar')
     and bool_or(pm.codigo = 'perfis.gerenciar')
$function$;

comment on function private.empresa_gestao_perfis() is
  'Empresa autorizada para gestao de perfis de usuarios: subject JWT ativo e permissoes fixas validadas em perfis ativos compativeis.';

reset role;
revoke create on schema private from bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false, set false;
revoke all on function private.empresa_gestao_perfis() from public, anon, authenticated, service_role;

-- Restricted writer: no login, no bypass RLS, no ownership of application tables.
create role bpf_admin_writer
  nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant bpf_admin_writer to postgres with inherit false, set true;
grant usage on schema public, private to bpf_admin_writer;

-- The authorization helpers are owned by bpf_authz_reader. PostgreSQL must temporarily
-- SET ROLE to that owner to grant EXECUTE; postgres deliberately has no inherited rights.
grant bpf_authz_reader to postgres with inherit false, set true;
set role bpf_authz_reader;
grant execute on function private.empresa_leitura_usuarios() to bpf_admin_writer;
grant execute on function private.empresa_gestao_perfis() to bpf_admin_writer;
reset role;
grant bpf_authz_reader to postgres with inherit false, set false;

grant select (id, empresa_id, unidade_id, ativo, status, nome, email, updated_at)
  on public.usuarios to bpf_admin_writer;
grant update (unidade_id, ativo, status, updated_at)
  on public.usuarios to bpf_admin_writer;
grant select (id, empresa_id, nome, is_system, ativo)
  on public.perfis to bpf_admin_writer;
grant select (usuario_id, perfil_id, created_at, created_by), insert (usuario_id, perfil_id, created_by), delete
  on public.usuario_perfis to bpf_admin_writer;
grant select (perfil_id, permissao_id)
  on public.perfil_permissoes to bpf_admin_writer;
grant select (id, codigo)
  on public.permissoes to bpf_admin_writer;
grant select (id, empresa_id, nome, ativo)
  on public.unidades to bpf_admin_writer;
grant insert (empresa_id, unidade_id, ator_id, entidade, registro_id, acao, antes, depois, justificativa, contexto)
  on public.auditoria_eventos to bpf_admin_writer;

-- Writer policies. Authorization company always comes from the authenticated subject.
create policy usuarios_admin_writer_select on public.usuarios
  for select to bpf_admin_writer
  using (empresa_id = (select private.empresa_leitura_usuarios()));

create policy usuarios_admin_writer_update on public.usuarios
  for update to bpf_admin_writer
  using (empresa_id = (select private.empresa_leitura_usuarios()))
  with check (empresa_id = (select private.empresa_leitura_usuarios()));

create policy unidades_admin_writer_select on public.unidades
  for select to bpf_admin_writer
  using (empresa_id = (select private.empresa_leitura_usuarios()));

create policy perfis_admin_writer_select on public.perfis
  for select to bpf_admin_writer
  using (
    (empresa_id is null and is_system)
    or empresa_id = (select private.empresa_leitura_usuarios())
  );

create policy permissoes_admin_writer_select on public.permissoes
  for select to bpf_admin_writer
  using (codigo in ('configuracoes.gerenciar', 'usuarios.gerenciar', 'perfis.gerenciar'));

create policy perfil_permissoes_admin_writer_select on public.perfil_permissoes
  for select to bpf_admin_writer
  using (exists (
    select 1 from public.perfis p where p.id = perfil_permissoes.perfil_id
  ));

create policy usuario_perfis_admin_writer_select on public.usuario_perfis
  for select to bpf_admin_writer
  using (exists (
    select 1
    from public.usuarios u
    join public.perfis p on p.id = usuario_perfis.perfil_id
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    where u.id = usuario_perfis.usuario_id
      and u.empresa_id = (select private.empresa_leitura_usuarios())
  ));

create policy usuario_perfis_admin_writer_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (exists (
    select 1
    from public.usuarios u
    join public.perfis p on p.id = usuario_perfis.perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    where u.id = usuario_perfis.usuario_id
      and u.empresa_id = (select private.empresa_leitura_usuarios())
  ));

create policy usuario_perfis_admin_writer_delete on public.usuario_perfis
  for delete to bpf_admin_writer
  using (exists (
    select 1
    from public.usuarios u
    join public.perfis p on p.id = usuario_perfis.perfil_id
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    where u.id = usuario_perfis.usuario_id
      and u.empresa_id = (select private.empresa_leitura_usuarios())
  ));

create policy auditoria_eventos_admin_writer_insert on public.auditoria_eventos
  for insert to bpf_admin_writer
  with check (
    empresa_id = (select private.empresa_leitura_usuarios())
    and ator_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  );

-- Create writer-owned private helpers/functions. They remain subject to RLS.
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create function private.usuario_admin_efetivo(p_usuario_id uuid, p_empresa_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select exists (
    select 1
    from public.usuarios u
    join public.usuario_perfis up on up.usuario_id = u.id
    join public.perfis p on p.id = up.perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    join public.perfil_permissoes pp on pp.perfil_id = p.id
    join public.permissoes pm on pm.id = pp.permissao_id
    where u.id = p_usuario_id
      and u.empresa_id = p_empresa_id
      and u.ativo
      and u.status = 'ativo'
    group by u.id
    having bool_or(pm.codigo = 'configuracoes.gerenciar')
       and bool_or(pm.codigo = 'usuarios.gerenciar')
       and bool_or(pm.codigo = 'perfis.gerenciar')
  )
$function$;

create function private.existe_outro_admin_efetivo(p_usuario_id uuid, p_empresa_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select exists (
    select 1
    from public.usuarios u
    join public.usuario_perfis up on up.usuario_id = u.id
    join public.perfis p on p.id = up.perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
    join public.perfil_permissoes pp on pp.perfil_id = p.id
    join public.permissoes pm on pm.id = pp.permissao_id
    where u.id <> p_usuario_id
      and u.empresa_id = p_empresa_id
      and u.ativo
      and u.status = 'ativo'
    group by u.id
    having bool_or(pm.codigo = 'configuracoes.gerenciar')
       and bool_or(pm.codigo = 'usuarios.gerenciar')
       and bool_or(pm.codigo = 'perfis.gerenciar')
  )
$function$;

create function private.admin_usuario_alterar_status(
  p_usuario_id uuid,
  p_status text,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_empresa uuid;
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_antes jsonb;
  v_depois jsonb;
  v_novo_ativo boolean;
begin
  v_empresa := private.empresa_leitura_usuarios();
  if v_empresa is null then
    raise exception using errcode = '42501', message = 'Sem permissao para administrar usuarios';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if p_status not in ('ativo', 'inativo', 'bloqueado') then
    raise exception using errcode = '22023', message = 'Status administrativo invalido';
  end if;

  select * into v_usuario
  from public.usuarios
  where id = p_usuario_id and empresa_id = v_empresa
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Usuario nao encontrado no escopo autorizado';
  end if;
  if v_usuario.status = 'pendente' then
    raise exception using errcode = '42501', message = 'Usuario pendente exige fluxo de vinculacao/aprovacao dedicado';
  end if;
  if p_usuario_id = v_ator and p_status <> 'ativo' then
    raise exception using errcode = '42501', message = 'Nao e permitido inativar ou bloquear o proprio usuario';
  end if;

  v_novo_ativo := (p_status = 'ativo');
  if v_usuario.status = p_status and v_usuario.ativo = v_novo_ativo then
    raise exception using errcode = '22023', message = 'Nenhuma alteracao de status identificada';
  end if;

  if p_status <> 'ativo'
     and private.usuario_admin_efetivo(p_usuario_id, v_empresa)
     and not private.existe_outro_admin_efetivo(p_usuario_id, v_empresa) then
    raise exception using errcode = '42501', message = 'Operacao removeria o ultimo administrador efetivo da empresa';
  end if;

  v_antes := jsonb_build_object('status', v_usuario.status, 'ativo', v_usuario.ativo, 'unidade_id', v_usuario.unidade_id);

  update public.usuarios
  set status = p_status,
      ativo = v_novo_ativo,
      updated_at = now()
  where id = p_usuario_id;

  v_depois := jsonb_build_object('status', p_status, 'ativo', v_novo_ativo, 'unidade_id', v_usuario.unidade_id);

  insert into public.auditoria_eventos(
    empresa_id, unidade_id, ator_id, entidade, registro_id, acao, antes, depois, justificativa, contexto
  ) values (
    v_empresa, v_usuario.unidade_id, v_ator, 'usuario', p_usuario_id, 'usuario.status_alterado',
    v_antes, v_depois, btrim(p_justificativa), jsonb_build_object('origem', 'rpc')
  );
end
$function$;

create function private.admin_usuario_alterar_unidade(
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_empresa uuid;
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_unidade_nome text;
begin
  v_empresa := private.empresa_leitura_usuarios();
  if v_empresa is null then
    raise exception using errcode = '42501', message = 'Sem permissao para administrar usuarios';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Justificativa deve possuir ao menos 5 caracteres';
  end if;

  select * into v_usuario
  from public.usuarios
  where id = p_usuario_id and empresa_id = v_empresa
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Usuario nao encontrado no escopo autorizado';
  end if;
  if v_usuario.status = 'pendente' then
    raise exception using errcode = '42501', message = 'Usuario pendente exige fluxo de vinculacao/aprovacao dedicado';
  end if;
  if v_usuario.unidade_id is not distinct from p_unidade_id then
    raise exception using errcode = '22023', message = 'Nenhuma alteracao de unidade identificada';
  end if;

  if p_unidade_id is not null then
    select nome into v_unidade_nome
    from public.unidades
    where id = p_unidade_id and empresa_id = v_empresa and ativo;
    if not found then
      raise exception using errcode = '22023', message = 'Unidade invalida, inativa ou fora da empresa';
    end if;
  end if;

  update public.usuarios
  set unidade_id = p_unidade_id,
      updated_at = now()
  where id = p_usuario_id;

  insert into public.auditoria_eventos(
    empresa_id, unidade_id, ator_id, entidade, registro_id, acao, antes, depois, justificativa, contexto
  ) values (
    v_empresa, p_unidade_id, v_ator, 'usuario', p_usuario_id, 'usuario.unidade_alterada',
    jsonb_build_object('unidade_id', v_usuario.unidade_id),
    jsonb_build_object('unidade_id', p_unidade_id, 'unidade_nome', v_unidade_nome),
    btrim(p_justificativa), jsonb_build_object('origem', 'rpc')
  );
end
$function$;

create function private.admin_usuario_alterar_perfil(
  p_usuario_id uuid,
  p_perfil_id uuid,
  p_acao text,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_empresa uuid;
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_perfil public.perfis%rowtype;
  v_existe boolean;
  v_admin_antes boolean;
  v_admin_depois boolean;
begin
  v_empresa := private.empresa_gestao_perfis();
  if v_empresa is null then
    raise exception using errcode = '42501', message = 'Sem permissao para gerir perfis de usuarios';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 5 then
    raise exception using errcode = '22023', message = 'Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if p_acao not in ('atribuir', 'remover') then
    raise exception using errcode = '22023', message = 'Acao de perfil invalida';
  end if;
  if p_usuario_id = v_ator then
    raise exception using errcode = '42501', message = 'Nao e permitido alterar o proprio perfil administrativo';
  end if;

  select * into v_usuario
  from public.usuarios
  where id = p_usuario_id and empresa_id = v_empresa
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Usuario nao encontrado no escopo autorizado';
  end if;
  if v_usuario.status = 'pendente' then
    raise exception using errcode = '42501', message = 'Usuario pendente exige fluxo de vinculacao/aprovacao dedicado';
  end if;

  select * into v_perfil
  from public.perfis
  where id = p_perfil_id
    and ((empresa_id is null and is_system) or empresa_id = v_empresa);
  if not found then
    raise exception using errcode = '22023', message = 'Perfil fora do escopo autorizado';
  end if;
  if p_acao = 'atribuir' and not v_perfil.ativo then
    raise exception using errcode = '22023', message = 'Perfil inativo nao pode ser atribuido';
  end if;

  select exists(
    select 1 from public.usuario_perfis where usuario_id = p_usuario_id and perfil_id = p_perfil_id
  ) into v_existe;
  v_admin_antes := private.usuario_admin_efetivo(p_usuario_id, v_empresa);

  if p_acao = 'atribuir' then
    if v_existe then
      raise exception using errcode = '22023', message = 'Perfil ja atribuido ao usuario';
    end if;
    insert into public.usuario_perfis(usuario_id, perfil_id, created_by)
    values (p_usuario_id, p_perfil_id, v_ator);
  else
    if not v_existe then
      raise exception using errcode = '22023', message = 'Perfil nao esta atribuido ao usuario';
    end if;
    delete from public.usuario_perfis
    where usuario_id = p_usuario_id and perfil_id = p_perfil_id;
  end if;

  v_admin_depois := private.usuario_admin_efetivo(p_usuario_id, v_empresa);
  if v_admin_antes and not v_admin_depois
     and not private.existe_outro_admin_efetivo(p_usuario_id, v_empresa) then
    raise exception using errcode = '42501', message = 'Operacao removeria o ultimo administrador efetivo da empresa';
  end if;

  insert into public.auditoria_eventos(
    empresa_id, unidade_id, ator_id, entidade, registro_id, acao, antes, depois, justificativa, contexto
  ) values (
    v_empresa, v_usuario.unidade_id, v_ator, 'usuario', p_usuario_id,
    case when p_acao = 'atribuir' then 'usuario.perfil_atribuido' else 'usuario.perfil_removido' end,
    jsonb_build_object('perfil_id', p_perfil_id, 'perfil_nome', v_perfil.nome, 'atribuido', not (p_acao = 'atribuir')),
    jsonb_build_object('perfil_id', p_perfil_id, 'perfil_nome', v_perfil.nome, 'atribuido', (p_acao = 'atribuir')),
    btrim(p_justificativa), jsonb_build_object('origem', 'rpc')
  );
end
$function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

revoke all on function private.usuario_admin_efetivo(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.existe_outro_admin_efetivo(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_usuario_alterar_status(uuid, text, text) from public, anon, service_role;
revoke all on function private.admin_usuario_alterar_unidade(uuid, uuid, text) from public, anon, service_role;
revoke all on function private.admin_usuario_alterar_perfil(uuid, uuid, text, text) from public, anon, service_role;
grant execute on function private.admin_usuario_alterar_status(uuid, text, text) to authenticated;
grant execute on function private.admin_usuario_alterar_unidade(uuid, uuid, text) to authenticated;
grant execute on function private.admin_usuario_alterar_perfil(uuid, uuid, text, text) to authenticated;

-- Public API wrappers are SECURITY INVOKER. Privileged code remains private and writer-owned.
create function public.admin_usuario_alterar_status(
  p_usuario_id uuid,
  p_status text,
  p_justificativa text
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_usuario_alterar_status(p_usuario_id, p_status, p_justificativa)
$function$;

create function public.admin_usuario_alterar_unidade(
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_justificativa text
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_usuario_alterar_unidade(p_usuario_id, p_unidade_id, p_justificativa)
$function$;

create function public.admin_usuario_alterar_perfil(
  p_usuario_id uuid,
  p_perfil_id uuid,
  p_acao text,
  p_justificativa text
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_usuario_alterar_perfil(p_usuario_id, p_perfil_id, p_acao, p_justificativa)
$function$;

revoke all on function public.admin_usuario_alterar_status(uuid, text, text) from public, anon, service_role;
revoke all on function public.admin_usuario_alterar_unidade(uuid, uuid, text) from public, anon, service_role;
revoke all on function public.admin_usuario_alterar_perfil(uuid, uuid, text, text) from public, anon, service_role;
grant execute on function public.admin_usuario_alterar_status(uuid, text, text) to authenticated;
grant execute on function public.admin_usuario_alterar_unidade(uuid, uuid, text) to authenticated;
grant execute on function public.admin_usuario_alterar_perfil(uuid, uuid, text, text) to authenticated;

comment on function public.admin_usuario_alterar_status(uuid, text, text) is
  'Comando autenticado para status de usuario da propria empresa; escrita privada auditada.';
comment on function public.admin_usuario_alterar_unidade(uuid, uuid, text) is
  'Comando autenticado para unidade de usuario da propria empresa; escrita privada auditada.';
comment on function public.admin_usuario_alterar_perfil(uuid, uuid, text, text) is
  'Comando autenticado para atribuir/remover perfil compativel; exige perfis.gerenciar e impede autoalteracao.';

reset lock_timeout;
reset statement_timeout;