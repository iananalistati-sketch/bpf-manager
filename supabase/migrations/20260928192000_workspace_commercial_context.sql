-- Marco 1.5 / Trial: contrato read-only do estado comercial e onboarding do tenant.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function public.meu_workspace_comercial(p_empresa_id uuid)
returns table (
  empresa_id uuid,
  plano_codigo text,
  plano_nome text,
  assinatura_status text,
  trial_inicio timestamptz,
  trial_fim timestamptz,
  trial_expirado boolean,
  dias_trial_restantes integer,
  modo_acesso text,
  onboarding_status text,
  onboarding_etapa text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
begin
  if v_subject is null or not exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue on ue.usuario_id=u.id
    where u.id=v_subject
      and u.ativo and u.status='ativo'
      and ue.empresa_id=p_empresa_id
      and ue.status='ativo'
  ) then
    raise exception using errcode='42501', message='Tenant comercial nao autorizado para a sessao';
  end if;

  return query
  select
    p_empresa_id,
    p.codigo,
    p.nome,
    ea.status,
    ea.trial_inicio,
    ea.trial_fim,
    (ea.status='trialing' and ea.trial_fim is not null and ea.trial_fim <= now()) as trial_expirado,
    case
      when ea.status='trialing' and ea.trial_fim is not null
        then greatest(0, ceil(extract(epoch from (ea.trial_fim-now())) / 86400.0)::integer)
      else 0
    end as dias_trial_restantes,
    case
      when ea.status='active' then 'normal'
      when ea.status='trialing' and ea.trial_fim > now() then 'normal'
      else 'somente_leitura'
    end as modo_acesso,
    coalesce(eo.status,'nao_iniciado'),
    eo.etapa_atual
  from public.empresa_assinaturas ea
  left join public.planos p on p.id=ea.plano_id
  left join public.empresa_onboarding eo on eo.empresa_id=ea.empresa_id
  where ea.empresa_id=p_empresa_id;
end
$function$;

revoke all on function public.meu_workspace_comercial(uuid) from public, anon, service_role;
grant execute on function public.meu_workspace_comercial(uuid) to authenticated;

comment on function public.meu_workspace_comercial(uuid) is
  'Contexto comercial tenant-aware: trial/assinatura, modo de acesso e progresso de onboarding sem confiar no empresa_id do cliente.';

reset lock_timeout;
reset statement_timeout;
