-- Read-only account preconditions. No identifiers, email, Auth payload or metadata returned.
with alvo as (
  select a.id, to_jsonb(a) as lifecycle from auth.users a
  where lower(a.email)=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8')
), cadastro as (
  select u.* from public.usuarios u where u.id in(select id from alvo)
), marcador as (
  select q.usuario_id,q.tipo,q.status,q.contexto->>'qa_marker' as qa_tag
  from public.saas_provisionamentos q where q.chave_idempotencia='bpf:qa-documentos:v1'
)
select
  (select count(*)::int from alvo) as auth_encontrados,
  (select count(*)::int from cadastro) as cadastros_encontrados,
  (select count(*)::int from alvo where lifecycle->>'email_confirmed_at' is not null) as auth_confirmados,
  (select count(*)::int from alvo where (lifecycle->>'banned_until')::timestamptz>now()) as auth_banidos,
  (select count(*)::int from alvo where lifecycle->>'deleted_at' is not null) as auth_excluidos,
  (select count(*)::int from cadastro where ativo and status in('pendente','ativo')) as cadastros_habilitados,
  (select count(*)::int from cadastro where lower(email)=convert_from(decode('__BPF_QA_EMAIL_HEX__','hex'),'UTF8')) as emails_coincidentes,
  (select count(*)::int from cadastro where empresa_id is not null) as empresas_principais,
  (select count(*)::int from cadastro where unidade_id is not null) as unidades_principais,
  (select count(*)::int from public.usuario_empresas where usuario_id in(select id from alvo)) as memberships,
  (select count(*)::int from public.usuario_perfis where usuario_id in(select id from alvo)) as perfis_legados,
  (select count(*)::int from public.saas_provisionamentos where usuario_id in(select id from alvo)) as provisionamentos,
  (select count(*)::int from public.empresas where created_by in(select id from alvo)) as empresas_criadas,
  exists(select 1 from marcador) as marcador_existe,
  exists(select 1 from marcador where usuario_id in(select id from alvo)) as marcador_desta_conta,
  exists(select 1 from marcador where usuario_id in(select id from alvo)
    and tipo='trial' and status='concluido' and qa_tag='bpf:qa-documentos:v1') as marcador_valido;
