-- One administrative transaction. Never changes primary identity/company/profile links.
do $qa$
declare
  v_key constant text:='bpf:qa-secondary:v1';
  v_email text:=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8');
  v_user public.usuarios%rowtype;
  v_existing public.saas_provisionamentos%rowtype;
  v_company uuid; v_unit uuid; v_profile uuid; v_member uuid; v_plan uuid; v_subscription uuid;
  v_permissions jsonb; v_entitlements jsonb; v_before text; v_after text;
  v_start timestamptz:=now(); v_end timestamptz:=now()+interval '14 days';
begin
  if current_user<>'postgres' then raise exception using errcode='42501',message='QA secundario exige canal administrativo postgres'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_key,0));
  if (select count(*) from auth.users where lower(email)=v_email)<>1 then
    raise exception using errcode='22023',message='Conta Auth ausente ou ambigua'; end if;
  select u.* into strict v_user from public.usuarios u join auth.users a on a.id=u.id
    where lower(a.email)=v_email for update of u;
  if not v_user.ativo or v_user.status<>'ativo' or lower(v_user.email) is distinct from v_email
    or not exists(select 1 from auth.users a where a.id=v_user.id and to_jsonb(a)->>'email_confirmed_at' is not null
      and to_jsonb(a)->>'deleted_at' is null and coalesce((to_jsonb(a)->>'banned_until')::timestamptz,now())<=now()) then
    raise exception using errcode='42501',message='Conta existente deve estar confirmada e habilitada'; end if;
  perform 1 from public.usuario_empresas ue join public.empresas e on e.id=ue.empresa_id and e.ativo
    where ue.usuario_id=v_user.id and ue.empresa_id=v_user.empresa_id and ue.status='ativo' for update of ue;
  if not found then raise exception using errcode='42501',message='Vinculo principal ativo indisponivel; nenhuma identidade sera movida ou reativada'; end if;
  select * into v_existing from public.saas_provisionamentos where chave_idempotencia=v_key for update;
  if found then
    if v_existing.usuario_id<>v_user.id or v_existing.tipo<>'trial' or v_existing.status<>'concluido'
      or v_existing.contexto->>'qa_marker' is distinct from v_key then
      raise exception using errcode='23505',message='Marcador QA secundario utilizado ou divergente'; end if;
    return;
  end if;
  select id into v_plan from public.planos where codigo='business' and ativo;
  if v_plan is null or not exists(select 1 from public.plano_entitlements where plano_id=v_plan and chave='unidades.max' and tipo='inteiro' and valor_inteiro>=2)
    or not exists(select 1 from public.plano_entitlements where plano_id=v_plan and chave='usuarios_ativos.max' and tipo='inteiro' and valor_inteiro>=2) then
    raise exception using errcode='55000',message='Business configurado para validacao multiunidade indisponivel'; end if;
  select jsonb_agg(codigo order by codigo) into v_permissions from public.permissoes;
  if not coalesce(v_permissions ?& array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar','estrutura.gerenciar',
    'documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar'],false) then
    raise exception using errcode='55000',message='Catalogo incompleto para validacao'; end if;
  select jsonb_agg(jsonb_build_object('chave',chave,'tipo',tipo,'booleano',valor_booleano,'inteiro',valor_inteiro,'texto',valor_texto) order by chave)
    into v_entitlements from public.plano_entitlements where plano_id=v_plan;
  select md5(jsonb_build_object('identity',to_jsonb(u),
    'legacy',(select jsonb_agg(to_jsonb(up) order by perfil_id) from public.usuario_perfis up where usuario_id=u.id),
    'members',(select jsonb_agg(to_jsonb(ue) order by id) from public.usuario_empresas ue where usuario_id=u.id),
    'profiles',(select jsonb_agg(to_jsonb(up) order by usuario_empresa_id,perfil_id) from public.usuario_empresa_perfis up
      join public.usuario_empresas ue on ue.id=up.usuario_empresa_id where ue.usuario_id=u.id))::text)
    into v_before from public.usuarios u where u.id=v_user.id;

  insert into public.saas_provisionamentos(chave_idempotencia,tipo,usuario_id,status,contexto)
    values(v_key,'trial',v_user.id,'processando',jsonb_build_object('qa_marker',v_key,'executor','postgres_cli'));
  insert into public.empresas(razao_social,nome_fantasia,ativo,created_by)
    values('BPF Manager - Empresa TESTE','BPF TESTE',true,v_user.id) returning id into v_company;
  insert into public.empresa_planos(empresa_id,plano_id,origem,assigned_by)
    values(v_company,v_plan,'trial',v_user.id);
  insert into public.empresa_assinaturas(empresa_id,plano_id,status,trial_inicio,trial_fim,metadata)
    values(v_company,v_plan,'trialing',v_start,v_end,jsonb_build_object('qa_marker',v_key,'ambiente','teste','executor','postgres_cli'))
    returning id into v_subscription;
  insert into public.unidades(empresa_id,nome,ativo,created_by)
    values(v_company,'Unidade TESTE',true,v_user.id) returning id into v_unit;
  insert into public.perfis(empresa_id,nome,descricao,is_system,ativo,created_by)
    values(v_company,'Administrador TESTE','Validacao por segundo vinculo; permissoes atuais, sem ampliar acessos futuros',false,true,v_user.id)
    returning id into v_profile;
  insert into public.perfil_permissoes(perfil_id,permissao_id,created_by)
    select v_profile,id,v_user.id from public.permissoes where v_permissions ? codigo;
  insert into public.usuario_empresas(usuario_id,empresa_id,unidade_id,status,is_owner,created_by)
    values(v_user.id,v_company,v_unit,'ativo',true,v_user.id) returning id into v_member;
  insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by)
    values(v_member,v_profile,v_user.id);
  insert into public.empresa_onboarding(empresa_id,status,etapa_atual,dados)
    values(v_company,'nao_iniciado','empresa','{}'::jsonb);

  select md5(jsonb_build_object('identity',to_jsonb(u),
    'legacy',(select jsonb_agg(to_jsonb(up) order by perfil_id) from public.usuario_perfis up where usuario_id=u.id),
    'members',(select jsonb_agg(to_jsonb(ue) order by id) from public.usuario_empresas ue where usuario_id=u.id and empresa_id<>v_company),
    'profiles',(select jsonb_agg(to_jsonb(up) order by usuario_empresa_id,perfil_id) from public.usuario_empresa_perfis up
      join public.usuario_empresas ue on ue.id=up.usuario_empresa_id where ue.usuario_id=u.id and ue.empresa_id<>v_company))::text)
    into v_after from public.usuarios u where u.id=v_user.id;
  if v_before is distinct from v_after then raise exception using errcode='23514',message='Preparacao alterou identidade ou vinculo anterior; rollback integral'; end if;
  update public.saas_provisionamentos set empresa_id=v_company,status='concluido',completed_at=now(),contexto=contexto||jsonb_build_object(
    'unidade_id',v_unit,'perfil_id',v_profile,'membership_id',v_member,'plano_id',v_plan,'assinatura_id',v_subscription,
    'permissoes',v_permissions,'entitlements',v_entitlements,'trial_inicio',v_start,'trial_fim',v_end,'primario_id',v_user.empresa_id)
    where chave_idempotencia=v_key;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
    values(v_company,v_unit,v_user.id,'empresa',v_company,'workspace.qa_secundario_preparado',null,
      jsonb_build_object('membership_id',v_member,'perfil_id',v_profile,'plano_id',v_plan,'permissoes',v_permissions,'trial_fim',v_end),
      'Empresa exclusiva de teste solicitada pelo responsavel do projeto',
      jsonb_build_object('qa_marker',v_key,'executor','postgres_cli','atribuicao_administrativa',true,'vinculos_anteriores_preservados',v_before=v_after));
end $qa$;
