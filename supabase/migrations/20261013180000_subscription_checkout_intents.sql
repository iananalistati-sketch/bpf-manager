-- Marco 1.5 / Contratacao: intencoes provider-neutral antes do checkout externo.
set lock_timeout = '5s';
set statement_timeout = '60s';

create table public.assinatura_contratacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on update no action on delete no action,
  assinatura_id uuid not null references public.empresa_assinaturas(id) on update no action on delete cascade,
  solicitado_por uuid not null references public.usuarios(id) on update no action on delete no action,
  plano_id uuid not null references public.planos(id) on update no action on delete no action,
  chave_idempotencia text not null unique,
  status text not null default 'preparada'
    check (status in ('preparada','checkout_criado','confirmada','cancelada','falhou','expirada')),
  provedor text null,
  provedor_checkout_id text null,
  checkout_url text null,
  expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assinatura_contratacoes_chave_check check (
    length(btrim(chave_idempotencia)) between 12 and 200
  ),
  constraint assinatura_contratacoes_expiracao_check check (expires_at > created_at),
  constraint assinatura_contratacoes_provider_check check (
    provedor is null
    or (
      length(btrim(provedor)) between 2 and 60
      and provedor = lower(provedor)
      and provedor ~ '^[a-z0-9][a-z0-9._-]*$'
    )
  ),
  constraint assinatura_contratacoes_checkout_check check (
    (status='preparada' and provedor is null and provedor_checkout_id is null and checkout_url is null)
    or
    (status<>'preparada')
  )
);

create index idx_assinatura_contratacoes_empresa_data
  on public.assinatura_contratacoes(empresa_id, created_at desc);
create index idx_assinatura_contratacoes_assinatura
  on public.assinatura_contratacoes(assinatura_id, created_at desc);
create unique index idx_assinatura_contratacoes_provider_checkout
  on public.assinatura_contratacoes(provedor, provedor_checkout_id)
  where provedor is not null and provedor_checkout_id is not null;

alter table public.assinatura_contratacoes enable row level security;
revoke all on table public.assinatura_contratacoes from public, anon, authenticated, service_role;

create or replace function public.preparar_contratacao_server(
  p_ator_id uuid,
  p_empresa_id uuid,
  p_plano_codigo text,
  p_chave_idempotencia text
)
returns table (
  contratacao_id uuid,
  empresa_id uuid,
  assinatura_id uuid,
  plano_id uuid,
  plano_codigo text,
  status text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_codigo text := lower(btrim(coalesce(p_plano_codigo,'')));
  v_chave text := btrim(coalesce(p_chave_idempotencia,''));
  v_assinatura public.empresa_assinaturas%rowtype;
  v_existente public.assinatura_contratacoes%rowtype;
  v_plano_id uuid;
  v_unidade_id uuid;
  v_limite_usuarios bigint;
  v_limite_unidades bigint;
  v_consumo_usuarios bigint;
  v_consumo_unidades bigint;
  v_id uuid;
  v_expira timestamptz := now() + interval '30 minutes';
begin
  if p_ator_id is null or p_empresa_id is null
     or length(v_codigo) < 1 or length(v_codigo) > 120
     or v_codigo !~ '^[a-z0-9][a-z0-9._-]*$'
     or length(v_chave) < 12 or length(v_chave) > 200 then
    raise exception using errcode='22023', message='Dados invalidos para preparar contratacao';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_chave,0));

  select ac.* into v_existente
  from public.assinatura_contratacoes ac
  where ac.chave_idempotencia=v_chave
  for update;

  if found then
    if v_existente.empresa_id <> p_empresa_id
       or v_existente.solicitado_por <> p_ator_id
       or not exists (
         select 1 from public.planos p
         where p.id=v_existente.plano_id and p.codigo=v_codigo
       ) then
      raise exception using errcode='23505', message='Chave de idempotencia ja utilizada com outra contratacao';
    end if;

    return query
    select ac.id,ac.empresa_id,ac.assinatura_id,ac.plano_id,p.codigo,ac.status,ac.expires_at
    from public.assinatura_contratacoes ac
    join public.planos p on p.id=ac.plano_id
    where ac.id=v_existente.id;
    return;
  end if;

  select ue.unidade_id into v_unidade_id
  from public.usuarios u
  join public.usuario_empresas ue on ue.usuario_id=u.id
  where u.id=p_ator_id
    and u.ativo and u.status='ativo'
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo'
    and ue.is_owner
  order by ue.id
  limit 1;

  if not found then
    raise exception using errcode='42501', message='Somente o owner ativo pode iniciar a contratacao';
  end if;

  select ea.* into v_assinatura
  from public.empresa_assinaturas ea
  where ea.empresa_id=p_empresa_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Assinatura do workspace nao encontrada';
  end if;

  if v_assinatura.status='active' and exists (
    select 1 from public.planos p where p.id=v_assinatura.plano_id and p.codigo=v_codigo
  ) then
    raise exception using errcode='23514', message='Workspace ja possui este plano ativo';
  end if;

  select p.id into v_plano_id
  from public.planos p
  where p.codigo=v_codigo and p.ativo;

  if v_plano_id is null then
    raise exception using errcode='22023', message='Plano comercial invalido ou inativo';
  end if;

  select pe.valor_inteiro into v_limite_usuarios
  from public.plano_entitlements pe
  where pe.plano_id=v_plano_id and pe.chave='usuarios_ativos.max' and pe.tipo='inteiro';

  select pe.valor_inteiro into v_limite_unidades
  from public.plano_entitlements pe
  where pe.plano_id=v_plano_id and pe.chave='unidades.max' and pe.tipo='inteiro';

  select count(*) into v_consumo_unidades
  from public.unidades un
  where un.empresa_id=p_empresa_id and un.ativo;

  select count(*) into v_consumo_usuarios
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id=p_empresa_id and u.ativo and u.status='ativo'
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
    where ue.empresa_id=p_empresa_id and ue.status='ativo'
  ) ativos;

  if v_limite_unidades is not null and v_consumo_unidades > v_limite_unidades then
    raise exception using errcode='23514', message='Plano selecionado nao comporta as unidades ativas atuais';
  end if;

  if v_limite_usuarios is not null and v_consumo_usuarios > v_limite_usuarios then
    raise exception using errcode='23514', message='Plano selecionado nao comporta os usuarios ativos atuais';
  end if;

  insert into public.assinatura_contratacoes(
    empresa_id,assinatura_id,solicitado_por,plano_id,chave_idempotencia,status,expires_at,metadata
  ) values (
    p_empresa_id,v_assinatura.id,p_ator_id,v_plano_id,v_chave,'preparada',v_expira,
    jsonb_build_object('origem','self_service','assinatura_status_origem',v_assinatura.status)
  )
  returning id into v_id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,v_unidade_id,p_ator_id,'assinatura_contratacao',v_id,'assinatura.contratacao_preparada',
    null,
    jsonb_build_object('assinatura_id',v_assinatura.id,'plano_id',v_plano_id,'plano_codigo',v_codigo,'expires_at',v_expira),
    'Preparacao de contratacao self-service',
    jsonb_build_object('idempotency_key',v_chave)
  );

  return query
  select ac.id,ac.empresa_id,ac.assinatura_id,ac.plano_id,p.codigo,ac.status,ac.expires_at
  from public.assinatura_contratacoes ac
  join public.planos p on p.id=ac.plano_id
  where ac.id=v_id;
end
$function$;

create or replace function public.registrar_checkout_assinatura_server(
  p_contratacao_id uuid,
  p_provedor text,
  p_provedor_checkout_id text,
  p_checkout_url text,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  contratacao_id uuid,
  empresa_id uuid,
  assinatura_id uuid,
  plano_id uuid,
  status text,
  checkout_url text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provedor text := lower(btrim(coalesce(p_provedor,'')));
  v_checkout_id text := btrim(coalesce(p_provedor_checkout_id,''));
  v_url text := btrim(coalesce(p_checkout_url,''));
  v_row public.assinatura_contratacoes%rowtype;
begin
  if p_contratacao_id is null
     or length(v_provedor) < 2 or length(v_provedor) > 60
     or v_provedor !~ '^[a-z0-9][a-z0-9._-]*$'
     or length(v_checkout_id) < 3 or length(v_checkout_id) > 255
     or length(v_url) < 12 or length(v_url) > 2048
     or left(lower(v_url),8) <> 'https://' then
    raise exception using errcode='22023', message='Dados invalidos do checkout';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' or pg_column_size(p_metadata) > 65536 then
    raise exception using errcode='22023', message='Metadata do checkout invalida';
  end if;

  select ac.* into v_row
  from public.assinatura_contratacoes ac
  where ac.id=p_contratacao_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Contratacao nao encontrada';
  end if;

  if v_row.expires_at <= now() and v_row.status='preparada' then
    update public.assinatura_contratacoes
    set status='expirada',updated_at=now()
    where id=v_row.id;
    raise exception using errcode='23514', message='Contratacao expirada antes da criacao do checkout';
  end if;

  if v_row.status='checkout_criado' then
    if v_row.provedor <> v_provedor
       or v_row.provedor_checkout_id <> v_checkout_id
       or v_row.checkout_url <> v_url then
      raise exception using errcode='23505', message='Checkout ja registrado com dados divergentes';
    end if;

    return query
    select ac.id,ac.empresa_id,ac.assinatura_id,ac.plano_id,ac.status,ac.checkout_url
    from public.assinatura_contratacoes ac
    where ac.id=v_row.id;
    return;
  end if;

  if v_row.status <> 'preparada' then
    raise exception using errcode='23514', message='Contratacao nao esta disponivel para criar checkout';
  end if;

  update public.assinatura_contratacoes
  set status='checkout_criado',
      provedor=v_provedor,
      provedor_checkout_id=v_checkout_id,
      checkout_url=v_url,
      metadata=metadata || p_metadata,
      updated_at=now()
  where id=v_row.id;

  return query
  select ac.id,ac.empresa_id,ac.assinatura_id,ac.plano_id,ac.status,ac.checkout_url
  from public.assinatura_contratacoes ac
  where ac.id=v_row.id;
end
$function$;

revoke all on function public.preparar_contratacao_server(uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.preparar_contratacao_server(uuid,uuid,text,text)
  to service_role;

revoke all on function public.registrar_checkout_assinatura_server(uuid,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.registrar_checkout_assinatura_server(uuid,text,text,text,jsonb)
  to service_role;

comment on table public.assinatura_contratacoes is
  'Intencoes de contratacao self-service independentes do provedor; checkout externo so e anexado pelo backend.';
comment on function public.preparar_contratacao_server(uuid,uuid,text,text) is
  'Prepara contratacao idempotente para owner ativo, validando plano e capacidade atual antes de qualquer checkout.';
comment on function public.registrar_checkout_assinatura_server(uuid,text,text,text,jsonb) is
  'Registra checkout criado por um adapter confiavel de pagamento; nao confirma assinatura nem concede acesso.';

reset lock_timeout;
reset statement_timeout;
