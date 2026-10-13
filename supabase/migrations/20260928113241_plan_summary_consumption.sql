-- Corrige o resumo comercial para contar o tenant inteiro sem ampliar as policies do reader do usuario.
set lock_timeout = '5s';
set statement_timeout = '60s';

grant bpf_plan_enforcer to postgres with inherit false, set true;
grant create on schema private to bpf_plan_enforcer;
set role bpf_plan_enforcer;

create function private.consumo_plano_empresa(p_empresa_id uuid)
returns table (usuarios_ativos bigint, unidades_ativas bigint)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    (
      select count(*)::bigint from (
        select u.id as usuario_id
        from public.usuarios u
        where u.empresa_id=p_empresa_id and u.ativo and u.status='ativo'
        union
        select ue.usuario_id
        from public.usuario_empresas ue
        where ue.empresa_id=p_empresa_id and ue.status='ativo'
      ) ativos
    ),
    (select count(*)::bigint from public.unidades un where un.empresa_id=p_empresa_id and un.ativo)
$function$;

revoke all on function private.consumo_plano_empresa(uuid) from public,anon,authenticated,service_role;
grant execute on function private.consumo_plano_empresa(uuid) to bpf_entitlement_reader;

reset role;
revoke create on schema private from bpf_plan_enforcer;
grant bpf_plan_enforcer to postgres with inherit false, set false;

grant bpf_entitlement_reader to postgres with inherit false, set true;
grant create on schema private to bpf_entitlement_reader;
set role bpf_entitlement_reader;

create or replace function private.meu_plano_resumo(p_empresa_id uuid)
returns table (
  plano_id uuid,
  plano_codigo text,
  plano_nome text,
  origem text,
  usuarios_ativos bigint,
  usuarios_ativos_max bigint,
  unidades_ativas bigint,
  unidades_max bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p.id,
    p.codigo,
    p.nome,
    ep.origem,
    consumo.usuarios_ativos,
    (select pe.valor_inteiro from public.plano_entitlements pe
      where pe.plano_id=p.id and pe.chave='usuarios_ativos.max' and pe.tipo='inteiro'),
    consumo.unidades_ativas,
    (select pe.valor_inteiro from public.plano_entitlements pe
      where pe.plano_id=p.id and pe.chave='unidades.max' and pe.tipo='inteiro')
  from public.usuario_empresas ue
  join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
  cross join lateral private.consumo_plano_empresa(p_empresa_id) consumo
  left join public.empresa_planos ep on ep.empresa_id=ue.empresa_id
  left join public.planos p on p.id=ep.plano_id
  where ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and ue.empresa_id=p_empresa_id and ue.status='ativo'
  limit 1
$function$;

comment on function private.meu_plano_resumo(uuid) is
  'Resumo comercial do tenant autorizado; consumo global e calculado por helper interno restrito.';

reset role;
revoke create on schema private from bpf_entitlement_reader;
grant bpf_entitlement_reader to postgres with inherit false, set false;

reset lock_timeout;
reset statement_timeout;
