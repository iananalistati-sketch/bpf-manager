-- Marco 1.5 / Comercial: bloqueia mutacoes autenticadas quando o workspace esta somente leitura.
-- Workspaces legados sem empresa_assinaturas permanecem liberados durante a transicao.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function private.assert_primary_workspace_write_allowed()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_empresa_id uuid;
  v_status text;
  v_trial_fim timestamptz;
begin
  if v_subject is null then
    raise exception using errcode='42501', message='Sessao invalida para escrita no workspace';
  end if;

  select u.empresa_id
    into v_empresa_id
  from public.usuarios u
  where u.id=v_subject
    and u.ativo
    and u.status='ativo';

  if v_empresa_id is null then
    raise exception using errcode='42501', message='Workspace primario indisponivel para escrita';
  end if;

  select ea.status, ea.trial_fim
    into v_status, v_trial_fim
  from public.empresa_assinaturas ea
  where ea.empresa_id=v_empresa_id;

  -- Compatibilidade: empresas existentes ainda sem assinatura cadastrada nao sao bloqueadas.
  if not found then
    return;
  end if;

  if v_status='active' then
    return;
  end if;

  if v_status='trialing' and v_trial_fim is not null and v_trial_fim > now() then
    return;
  end if;

  raise exception using errcode='42501', message='Workspace em modo somente leitura';
end
$function$;

revoke all on function private.assert_primary_workspace_write_allowed() from public, anon, service_role;
grant execute on function private.assert_primary_workspace_write_allowed() to authenticated;

create or replace function public.admin_usuario_alterar_status(
  p_usuario_id uuid,
  p_status text,
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform private.assert_primary_workspace_write_allowed();
  perform private.admin_usuario_alterar_status(p_usuario_id,p_status,p_justificativa);
end
$function$;

create or replace function public.admin_usuario_alterar_unidade(
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform private.assert_primary_workspace_write_allowed();
  perform private.admin_usuario_alterar_unidade(p_usuario_id,p_unidade_id,p_justificativa);
end
$function$;

create or replace function public.admin_usuario_alterar_perfil(
  p_usuario_id uuid,
  p_perfil_id uuid,
  p_acao text,
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform private.assert_primary_workspace_write_allowed();
  perform private.admin_usuario_alterar_perfil(p_usuario_id,p_perfil_id,p_acao,p_justificativa);
end
$function$;

create or replace function public.admin_empresa_atualizar(
  p_razao_social text,
  p_nome_fantasia text,
  p_cnpj text,
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform private.assert_primary_workspace_write_allowed();
  perform private.admin_empresa_atualizar(p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa);
end
$function$;

create or replace function public.admin_unidade_salvar(
  p_unidade_id uuid,
  p_nome text,
  p_codigo text,
  p_ativo boolean,
  p_justificativa text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  perform private.assert_primary_workspace_write_allowed();
  select private.admin_unidade_salvar(p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) into v_id;
  return v_id;
end
$function$;

create or replace function public.admin_setor_salvar(
  p_setor_id uuid,
  p_unidade_id uuid,
  p_nome text,
  p_codigo text,
  p_ativo boolean,
  p_justificativa text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  perform private.assert_primary_workspace_write_allowed();
  select private.admin_setor_salvar(p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) into v_id;
  return v_id;
end
$function$;

create or replace function public.admin_perfil_criar(
  p_nome text,
  p_descricao text,
  p_permissao_ids uuid[],
  p_justificativa text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  perform private.assert_primary_workspace_write_allowed();
  select private.admin_perfil_criar(p_nome,p_descricao,p_permissao_ids,p_justificativa) into v_id;
  return v_id;
end
$function$;

create or replace function public.admin_perfil_atualizar(
  p_perfil_id uuid,
  p_nome text,
  p_descricao text,
  p_ativo boolean,
  p_permissao_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  perform private.assert_primary_workspace_write_allowed();
  perform private.admin_perfil_atualizar(p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa);
end
$function$;

-- Mantem a superficie publica identica e apenas acrescenta a regra comercial antes da escrita.
revoke all on function public.admin_usuario_alterar_status(uuid,text,text) from public,anon,service_role;
revoke all on function public.admin_usuario_alterar_unidade(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.admin_usuario_alterar_perfil(uuid,uuid,text,text) from public,anon,service_role;
revoke all on function public.admin_empresa_atualizar(text,text,text,text) from public,anon,service_role;
revoke all on function public.admin_unidade_salvar(uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function public.admin_setor_salvar(uuid,uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function public.admin_perfil_criar(text,text,uuid[],text) from public,anon,service_role;
revoke all on function public.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) from public,anon,service_role;

grant execute on function public.admin_usuario_alterar_status(uuid,text,text) to authenticated;
grant execute on function public.admin_usuario_alterar_unidade(uuid,uuid,text) to authenticated;
grant execute on function public.admin_usuario_alterar_perfil(uuid,uuid,text,text) to authenticated;
grant execute on function public.admin_empresa_atualizar(text,text,text,text) to authenticated;
grant execute on function public.admin_unidade_salvar(uuid,text,text,boolean,text) to authenticated;
grant execute on function public.admin_setor_salvar(uuid,uuid,text,text,boolean,text) to authenticated;
grant execute on function public.admin_perfil_criar(text,text,uuid[],text) to authenticated;
grant execute on function public.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) to authenticated;

comment on function private.assert_primary_workspace_write_allowed() is
  'Gate comercial transitorio: workspaces com assinatura so podem mutar quando active ou trialing ainda valido; legados sem assinatura permanecem compativeis.';

reset lock_timeout;
reset statement_timeout;
