-- Serialize destructive effective-admin mutations per company to avoid concurrent
-- transactions both observing another administrator and removing the last two at once.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- The previous administrative migration deliberately leaves postgres unable to SET
-- the restricted writer role. Re-enable it only while replacing writer-owned helpers.
grant bpf_admin_writer to postgres with inherit false, set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create or replace function private.admin_usuario_alterar_status(
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

  -- Company-scoped transaction lock must be acquired before evaluating whether the
  -- target is the last effective administrator.
  perform pg_advisory_xact_lock(hashtextextended(v_empresa::text, 0));

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

create or replace function private.admin_usuario_alterar_perfil(
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

  -- Use the same company lock as status mutations so destructive admin changes cannot
  -- race across different RPCs.
  perform pg_advisory_xact_lock(hashtextextended(v_empresa::text, 0));

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

-- CREATE OR REPLACE preserves the existing restricted ownership/grants. Reassert client
-- boundaries explicitly so the final state is obvious and reviewable.
revoke all on function private.admin_usuario_alterar_status(uuid, text, text) from public, anon, service_role;
revoke all on function private.admin_usuario_alterar_perfil(uuid, uuid, text, text) from public, anon, service_role;
grant execute on function private.admin_usuario_alterar_status(uuid, text, text) to authenticated;
grant execute on function private.admin_usuario_alterar_perfil(uuid, uuid, text, text) to authenticated;

reset lock_timeout;
reset statement_timeout;
