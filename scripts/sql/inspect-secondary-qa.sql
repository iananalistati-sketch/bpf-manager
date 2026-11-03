with account as (
  select u.*,to_jsonb(a) as lifecycle from public.usuarios u join auth.users a on a.id=u.id
  where lower(a.email)=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8')
), ledger as(select * from public.saas_provisionamentos where chave_idempotencia='bpf:qa-secondary:v1'),
qa as(select q.* from ledger q where q.tipo='trial' and q.status='concluido' and q.contexto->>'qa_marker'='bpf:qa-secondary:v1'
  and q.usuario_id=(select id from account)),
checks as(select
  (select count(*)=1 from account where ativo and status='ativo' and lifecycle->>'email_confirmed_at' is not null
    and lifecycle->>'deleted_at' is null and coalesce((lifecycle->>'banned_until')::timestamptz,now())<=now()) as conta_valida,
  not exists(select 1 from ledger) as marcador_ausente,
  exists(select 1 from account a join public.usuario_empresas ue on ue.usuario_id=a.id and ue.empresa_id=a.empresa_id
    join public.empresas e on e.id=a.empresa_id and e.ativo where ue.status='ativo') as primario_ativo,
  exists(select 1 from qa q join account a on a.id=q.usuario_id
    join public.usuario_empresas ue on ue.id::text=q.contexto->>'membership_id' and ue.empresa_id=q.empresa_id and ue.usuario_id=a.id
    join public.empresas e on e.id=q.empresa_id and e.ativo
    join public.unidades un on un.id=ue.unidade_id and un.empresa_id=q.empresa_id and un.ativo
    where ue.status='ativo' and ue.is_owner and a.empresa_id<>q.empresa_id and a.empresa_id::text=q.contexto->>'primario_id'
      and un.id::text=q.contexto->>'unidade_id') as segundo_vinculo,
  exists(select 1 from qa q join public.perfis p on p.id::text=q.contexto->>'perfil_id' and p.empresa_id=q.empresa_id and not p.is_system and p.ativo
    where (select jsonb_agg(pm.codigo order by pm.codigo) from public.perfil_permissoes pp join public.permissoes pm on pm.id=pp.permissao_id where pp.perfil_id=p.id)=q.contexto->'permissoes'
      and (q.contexto->'permissoes') ?& array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar','estrutura.gerenciar','documentos.visualizar','documentos.criar','documentos.editar','documentos.aprovar']
      and (select count(*) from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id where ue.usuario_id=q.usuario_id and ue.empresa_id=q.empresa_id)=1
      and exists(select 1 from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id
        where ue.usuario_id=q.usuario_id and ue.empresa_id=q.empresa_id and up.perfil_id=p.id)
      and not exists(select 1 from public.usuario_perfis up where up.usuario_id=q.usuario_id and up.perfil_id=p.id)) as perfil_local,
  exists(select 1 from qa q join public.empresa_assinaturas ea on ea.empresa_id=q.empresa_id
    join public.empresa_planos ep on ep.empresa_id=q.empresa_id and ep.plano_id=ea.plano_id
    join public.planos p on p.id=ep.plano_id and p.ativo and p.codigo='business'
    where ea.id::text=q.contexto->>'assinatura_id' and p.id::text=q.contexto->>'plano_id'
      and ea.status='trialing' and ea.trial_fim>now() and ep.origem='trial'
      and ea.trial_inicio=(q.contexto->>'trial_inicio')::timestamptz and ea.trial_fim=(q.contexto->>'trial_fim')::timestamptz
      and ea.trial_fim=ea.trial_inicio+interval '14 days'
      and ea.provedor is null and ea.provedor_cliente_id is null and ea.provedor_assinatura_id is null and ea.converted_at is null
      and (select jsonb_agg(jsonb_build_object('chave',chave,'tipo',tipo,'booleano',valor_booleano,'inteiro',valor_inteiro,'texto',valor_texto) order by chave)
        from public.plano_entitlements where plano_id=p.id)=q.contexto->'entitlements') as trial_valido,
  exists(select 1 from qa q join public.empresa_onboarding eo on eo.empresa_id=q.empresa_id) as onboarding,
  exists(select 1 from qa q join public.auditoria_eventos ae on ae.empresa_id=q.empresa_id and ae.ator_id=q.usuario_id
    where ae.acao='workspace.qa_secundario_preparado' and ae.contexto->>'qa_marker'='bpf:qa-secondary:v1'
      and ae.contexto->>'executor'='postgres_cli' and ae.contexto->'vinculos_anteriores_preservados'='true'::jsonb) as auditoria)
select to_jsonb(checks) as checks,(select empresa_id from qa) as empresa_id,
  (select contexto->>'trial_fim' from qa) as trial_fim from checks;
