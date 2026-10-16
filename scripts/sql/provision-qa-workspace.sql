-- Operational QA bootstrap, not a migration. Exactly one atomic DO statement.
-- Only the validated hex token is substituted; no credentials or raw email in SQL.
do $qa$
declare
  v_email text := convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8');
  v_key constant text := 'bpf:qa-documentos:v1';
  v_user public.usuarios%rowtype;
  v_previous public.saas_provisionamentos%rowtype;
  v_result record;
  v_plan uuid;
  v_profile uuid;
  v_permissions jsonb;
  v_entitlements jsonb;
begin
  if current_user <> 'postgres' then
    raise exception using errcode='42501', message='Preparacao QA exige o canal administrativo postgres';
  end if;
  perform set_config('lock_timeout','5s',true);
  perform set_config('statement_timeout','60s',true);
  perform pg_advisory_xact_lock(hashtextextended(v_key,0));

  if (select count(*) from auth.users a where lower(a.email)=v_email) <> 1 then
    raise exception using errcode='22023', message='Conta de teste ausente ou ambigua no Auth';
  end if;
  select u.* into strict v_user from public.usuarios u
  join auth.users a on a.id=u.id where lower(a.email)=v_email
  for update of u;
  if not v_user.ativo or v_user.status not in ('pendente','ativo')
     or lower(v_user.email) is distinct from v_email
     or not exists (
       select 1 from auth.users a where a.id=v_user.id
         and to_jsonb(a)->>'email_confirmed_at' is not null
         and to_jsonb(a)->>'deleted_at' is null
         and coalesce((to_jsonb(a)->>'banned_until')::timestamptz, now()) <= now()
     ) then
    raise exception using errcode='42501', message='Conta QA deve estar confirmada, habilitada e sem bloqueio';
  end if;

  select * into v_previous from public.saas_provisionamentos
  where chave_idempotencia=v_key for update;
  if found then
    if v_previous.usuario_id <> v_user.id or v_previous.tipo <> 'trial'
       or v_previous.status <> 'concluido'
       or v_previous.contexto->>'qa_marker' is distinct from v_key then
      raise exception using errcode='23505', message='Marcador QA ja utilizado ou divergente';
    end if;
    -- Replay never restores permissions, renews the trial or changes tested data.
    return;
  end if;

  if v_user.empresa_id is not null or v_user.unidade_id is not null
     or exists(select 1 from public.usuario_empresas where usuario_id=v_user.id)
     or exists(select 1 from public.usuario_perfis where usuario_id=v_user.id)
     or exists(select 1 from public.saas_provisionamentos where usuario_id=v_user.id)
     or exists(select 1 from public.empresas where created_by=v_user.id) then
    raise exception using errcode='23514', message='Use conta exclusiva sem empresa ou vinculos anteriores; conta existente preservada';
  end if;

  select id into v_plan from public.planos where codigo='business' and ativo;
  if v_plan is null or not exists (
    select 1 from public.plano_entitlements where plano_id=v_plan
      and chave='unidades.max' and tipo='inteiro' and valor_inteiro >= 2
  ) or not exists (
    select 1 from public.plano_entitlements where plano_id=v_plan
      and chave='usuarios_ativos.max' and tipo='inteiro' and valor_inteiro >= 2
  ) then
    raise exception using errcode='55000', message='Plano Business ativo com limites para QA indisponivel';
  end if;
  select jsonb_agg(codigo order by codigo) into v_permissions from public.permissoes;
  if v_permissions is null or not v_permissions ?& array[
    'configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar',
    'documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar'
  ] then
    raise exception using errcode='55000', message='Catalogo de permissoes incompleto';
  end if;
  select jsonb_agg(jsonb_build_object('chave',chave,'tipo',tipo,'booleano',valor_booleano,
    'inteiro',valor_inteiro,'texto',valor_texto) order by chave)
  into v_entitlements from public.plano_entitlements where plano_id=v_plan;

  select * into strict v_result from public.provisionar_trial_server(
    v_user.id,'BPF Manager - Empresa TESTE','BPF TESTE','Unidade TESTE',v_key);
  update public.empresa_planos set plano_id=v_plan
  where empresa_id=v_result.empresa_id and origem='trial';
  update public.empresa_assinaturas set plano_id=v_plan,
    metadata=metadata || jsonb_build_object('ambiente','teste','qa_marker',v_key,'executor','postgres_cli')
  where id=v_result.assinatura_id;

  insert into public.perfis(empresa_id,nome,descricao,is_system,ativo,created_by)
  values(v_result.empresa_id,'Administrador TESTE','Permissoes atuais para validacao isolada; nao amplia acessos futuros',false,true,v_user.id)
  returning id into v_profile;
  insert into public.perfil_permissoes(perfil_id,permissao_id,created_by)
  select v_profile,p.id,v_user.id from public.permissoes p
  where v_permissions ? p.codigo;
  -- The legacy bridge also links this profile to the newly-created primary membership.
  insert into public.usuario_perfis(usuario_id,perfil_id,created_by)
  values(v_user.id,v_profile,v_user.id);
  -- Replace only the initial links just created for this previously unbound identity.
  -- No shared profile or shared permission is changed.
  delete from public.usuario_perfis where usuario_id=v_user.id and perfil_id<>v_profile;

  update public.saas_provisionamentos set contexto=contexto || jsonb_build_object(
    'qa_marker',v_key,'qa_perfil_id',v_profile,'qa_plano_id',v_plan,
    'qa_unidade_id',v_result.unidade_id,'qa_permissoes',v_permissions,
    'qa_entitlements',v_entitlements,'qa_trial_fim',v_result.trial_fim,
    'executor','postgres_cli','conta_exclusiva',true)
  where chave_idempotencia=v_key;
  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  values(v_result.empresa_id,v_result.unidade_id,v_user.id,'empresa',v_result.empresa_id,
    'workspace.qa_preparado',null,jsonb_build_object('perfil_id',v_profile,'plano_id',v_plan,
      'permissoes',v_permissions,'trial_fim',v_result.trial_fim),
    'Empresa exclusiva de teste solicitada pelo responsavel do projeto',
    jsonb_build_object('qa_marker',v_key,'executor','postgres_cli','atribuicao_administrativa',true));
end
$qa$;
