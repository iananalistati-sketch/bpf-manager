-- Read-only inspection, including account eligibility before provisioning.
with account as (
  select u.*, to_jsonb(a) as auth_record from public.usuarios u
  join auth.users a on a.id=u.id
  where lower(a.email)=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8')
), ledger as (
  select * from public.saas_provisionamentos where chave_idempotencia='bpf:qa-documentos:v1'
), qa as (
  select q.*, e.ativo as empresa_ativa,
    (q.contexto->>'qa_perfil_id')::uuid as perfil_id,
    (q.contexto->>'qa_unidade_id')::uuid as unidade_id,
    (q.contexto->>'qa_plano_id')::uuid as plano_id
  from ledger q join public.empresas e on e.id=q.empresa_id
  where q.usuario_id=(select id from account)
    and q.tipo='trial' and q.status='concluido'
    and q.contexto->>'qa_marker'='bpf:qa-documentos:v1'
), checks as (
select
  (select count(*)=1 from account where ativo and status in ('pendente','ativo')
    and lower(email)=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8')
    and auth_record->>'email_confirmed_at' is not null
    and auth_record->>'deleted_at' is null
    and coalesce((auth_record->>'banned_until')::timestamptz,now())<=now()) as conta_valida,
  not exists(select 1 from ledger) as marcador_ausente,
  exists(select 1 from account a where a.empresa_id is null and a.unidade_id is null
    and not exists(select 1 from public.usuario_empresas where usuario_id=a.id)
    and not exists(select 1 from public.usuario_perfis where usuario_id=a.id)
    and not exists(select 1 from public.saas_provisionamentos where usuario_id=a.id)
    and not exists(select 1 from public.empresas where created_by=a.id)) as conta_livre,
  exists(select 1 from qa q join account a on a.id=q.usuario_id
    join public.usuario_empresas ue on ue.usuario_id=a.id and ue.empresa_id=q.empresa_id
    join public.unidades un on un.id=q.unidade_id and un.empresa_id=q.empresa_id
    where q.empresa_ativa and a.ativo and a.status='ativo' and a.empresa_id=q.empresa_id
      and a.unidade_id=q.unidade_id and un.ativo and ue.unidade_id=q.unidade_id
      and ue.status='ativo' and ue.is_owner
      and (select count(*) from public.usuario_empresas where usuario_id=a.id)=1) as identidade_isolada,
  exists(select 1 from qa q join public.perfis p on p.id=q.perfil_id
    where p.empresa_id=q.empresa_id and not p.is_system and p.ativo
      and (select array_agg(perfil_id order by perfil_id) from public.usuario_perfis
           where usuario_id=q.usuario_id)=array[q.perfil_id]
      and (select array_agg(uep.perfil_id order by uep.perfil_id) from public.usuario_empresa_perfis uep
           join public.usuario_empresas ue on ue.id=uep.usuario_empresa_id
           where ue.usuario_id=q.usuario_id)=array[q.perfil_id]
      and (select jsonb_agg(pm.codigo order by pm.codigo) from public.perfil_permissoes pp
           join public.permissoes pm on pm.id=pp.permissao_id where pp.perfil_id=q.perfil_id)=q.contexto->'qa_permissoes'
      and (q.contexto->'qa_permissoes') ?& array['documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar']) as perfil_local_completo,
  exists(select 1 from qa q join public.empresa_assinaturas ea on ea.empresa_id=q.empresa_id
    join public.empresa_planos ep on ep.empresa_id=q.empresa_id
    join public.planos p on p.id=q.plano_id
    where ea.id::text=q.contexto->>'assinatura_id'
      and p.codigo='business' and p.ativo and ea.plano_id=p.id and ep.plano_id=p.id
      and ep.origem='trial' and ea.status='trialing' and ea.trial_fim>now()
      and ea.trial_fim=(q.contexto->>'qa_trial_fim')::timestamptz
      and ea.trial_fim=ea.trial_inicio+interval '14 days'
      and ea.provedor is null and ea.provedor_cliente_id is null
      and ea.provedor_assinatura_id is null and ea.converted_at is null
      and (select jsonb_agg(jsonb_build_object('chave',chave,'tipo',tipo,'booleano',valor_booleano,
        'inteiro',valor_inteiro,'texto',valor_texto) order by chave)
        from public.plano_entitlements where plano_id=p.id)=q.contexto->'qa_entitlements') as trial_preservado,
  exists(select 1 from qa q join public.empresa_onboarding eo on eo.empresa_id=q.empresa_id) as onboarding_disponivel,
  exists(select 1 from qa q join public.auditoria_eventos ae
    on ae.empresa_id=q.empresa_id and ae.registro_id=q.empresa_id and ae.ator_id=q.usuario_id
    where ae.acao='workspace.qa_preparado' and ae.contexto->>'qa_marker'='bpf:qa-documentos:v1'
      and ae.contexto->>'executor'='postgres_cli'
      and ae.depois->'permissoes'=q.contexto->'qa_permissoes') as provisionamento_auditado
)
select to_jsonb(checks) as checks,
  (select empresa_id from qa) as empresa_id,
  (select unidade_id from qa) as unidade_id,
  (select perfil_id from qa) as perfil_id,
  (select contexto->>'qa_trial_fim' from qa) as trial_fim,
  (select jsonb_array_length(contexto->'qa_permissoes') from qa) as quantidade_permissoes
from checks;
