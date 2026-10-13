-- Marco 1.5 / Assinatura: ciclo comercial provider-neutral e processamento idempotente de eventos confiaveis.
set lock_timeout = '5s';
set statement_timeout = '60s';

alter table public.empresa_assinaturas
  add column status_changed_at timestamptz not null default now(),
  add column provedor_ultimo_evento_em timestamptz null,
  add column provedor_preco_id text null;

alter table public.empresa_assinaturas
  add constraint empresa_assinaturas_periodo_check check (
    periodo_inicio is null
    or periodo_fim is null
    or periodo_fim > periodo_inicio
  );

create table public.assinatura_eventos (
  id uuid primary key default gen_random_uuid(),
  assinatura_id uuid not null references public.empresa_assinaturas(id) on update no action on delete cascade,
  empresa_id uuid not null references public.empresas(id) on update no action on delete no action,
  provedor text not null,
  provedor_evento_id text not null,
  provedor_cliente_id text null,
  provedor_assinatura_id text null,
  provedor_preco_id text null,
  tipo_evento text not null,
  status_anterior text null check (status_anterior is null or status_anterior in ('trialing','active','past_due','paused','canceled','expired')),
  status_novo text not null check (status_novo in ('trialing','active','past_due','paused','canceled','expired')),
  plano_codigo_solicitado text null,
  plano_anterior_id uuid null references public.planos(id) on update no action on delete no action,
  plano_novo_id uuid null references public.planos(id) on update no action on delete no action,
  periodo_inicio timestamptz null,
  periodo_fim timestamptz null,
  ocorrido_em timestamptz not null,
  aplicado boolean not null,
  motivo text null,
  metadata jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now(),
  constraint assinatura_eventos_provedor_check check (
    length(btrim(provedor)) between 2 and 60
    and provedor = lower(provedor)
    and provedor ~ '^[a-z0-9][a-z0-9._-]*$'
  ),
  constraint assinatura_eventos_evento_id_check check (length(btrim(provedor_evento_id)) between 3 and 255),
  constraint assinatura_eventos_tipo_check check (length(btrim(tipo_evento)) between 2 and 120),
  constraint assinatura_eventos_periodo_check check (
    periodo_inicio is null
    or periodo_fim is null
    or periodo_fim > periodo_inicio
  ),
  constraint assinatura_eventos_provider_event_key unique (provedor, provedor_evento_id)
);

create index idx_assinatura_eventos_empresa_data
  on public.assinatura_eventos(empresa_id, ocorrido_em desc);
create index idx_assinatura_eventos_assinatura_data
  on public.assinatura_eventos(assinatura_id, ocorrido_em desc);

alter table public.assinatura_eventos enable row level security;
revoke all on table public.assinatura_eventos from public, anon, authenticated, service_role;

create or replace function public.processar_evento_assinatura_server(
  p_empresa_id uuid,
  p_provedor text,
  p_provedor_evento_id text,
  p_tipo_evento text,
  p_status_novo text,
  p_plano_codigo text default null,
  p_provedor_cliente_id text default null,
  p_provedor_assinatura_id text default null,
  p_provedor_preco_id text default null,
  p_periodo_inicio timestamptz default null,
  p_periodo_fim timestamptz default null,
  p_ocorrido_em timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns table (
  assinatura_id uuid,
  empresa_id uuid,
  status text,
  plano_id uuid,
  evento_id uuid,
  aplicado boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provedor text := lower(btrim(coalesce(p_provedor,'')));
  v_evento_ref text := btrim(coalesce(p_provedor_evento_id,''));
  v_tipo text := btrim(coalesce(p_tipo_evento,''));
  v_status_novo text := lower(btrim(coalesce(p_status_novo,'')));
  v_plano_codigo text := nullif(lower(btrim(coalesce(p_plano_codigo,''))),'');
  v_cliente_ref text := nullif(btrim(coalesce(p_provedor_cliente_id,'')),'');
  v_assinatura_ref text := nullif(btrim(coalesce(p_provedor_assinatura_id,'')),'');
  v_preco_ref text := nullif(btrim(coalesce(p_provedor_preco_id,'')),'');
  v_ocorrido_em timestamptz := coalesce(p_ocorrido_em, now());
  v_assinatura public.empresa_assinaturas%rowtype;
  v_evento public.assinatura_eventos%rowtype;
  v_plano_id uuid;
  v_evento_id uuid;
  v_limite_usuarios bigint;
  v_limite_unidades bigint;
  v_consumo_usuarios bigint;
  v_consumo_unidades bigint;
  v_transicao_valida boolean;
  v_troca_provedor boolean;
begin
  if p_empresa_id is null
     or length(v_provedor) < 2 or length(v_provedor) > 60
     or v_provedor !~ '^[a-z0-9][a-z0-9._-]*$'
     or length(v_evento_ref) < 3 or length(v_evento_ref) > 255
     or length(v_tipo) < 2 or length(v_tipo) > 120
     or v_status_novo not in ('trialing','active','past_due','paused','canceled','expired') then
    raise exception using errcode='22023', message='Evento comercial invalido';
  end if;

  if (v_cliente_ref is not null and length(v_cliente_ref) > 255)
     or (v_assinatura_ref is not null and length(v_assinatura_ref) > 255)
     or (v_preco_ref is not null and length(v_preco_ref) > 255)
     or (v_plano_codigo is not null and (
       length(v_plano_codigo) > 120
       or v_plano_codigo !~ '^[a-z0-9][a-z0-9._-]*$'
     )) then
    raise exception using errcode='22023', message='Referencias comerciais invalidas';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' or pg_column_size(p_metadata) > 65536 then
    raise exception using errcode='22023', message='Metadata comercial invalida';
  end if;

  if (p_periodo_inicio is null) <> (p_periodo_fim is null)
     or (p_periodo_inicio is not null and p_periodo_fim <= p_periodo_inicio) then
    raise exception using errcode='22023', message='Periodo comercial invalido';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_provedor || ':' || v_evento_ref, 0));

  select ae.* into v_evento
  from public.assinatura_eventos ae
  where ae.provedor=v_provedor and ae.provedor_evento_id=v_evento_ref
  for update;

  if found then
    if v_evento.empresa_id <> p_empresa_id
       or v_evento.tipo_evento <> v_tipo
       or v_evento.status_novo <> v_status_novo
       or v_evento.plano_codigo_solicitado is distinct from v_plano_codigo
       or v_evento.provedor_cliente_id is distinct from v_cliente_ref
       or v_evento.provedor_assinatura_id is distinct from v_assinatura_ref
       or v_evento.provedor_preco_id is distinct from v_preco_ref
       or v_evento.periodo_inicio is distinct from p_periodo_inicio
       or v_evento.periodo_fim is distinct from p_periodo_fim
       or v_evento.metadata is distinct from p_metadata then
      raise exception using errcode='23505', message='Evento do provedor reutilizado com payload divergente';
    end if;

    return query
    select ea.id, ea.empresa_id, ea.status, ea.plano_id, v_evento.id, false
    from public.empresa_assinaturas ea
    where ea.id=v_evento.assinatura_id;
    return;
  end if;

  select ea.* into v_assinatura
  from public.empresa_assinaturas ea
  where ea.empresa_id=p_empresa_id
  for update;

  if not found then
    raise exception using errcode='P0002', message='Assinatura do workspace nao encontrada';
  end if;

  if v_plano_codigo is not null then
    select p.id into v_plano_id
    from public.planos p
    where p.codigo=v_plano_codigo and p.ativo;
    if v_plano_id is null then
      raise exception using errcode='22023', message='Plano comercial invalido ou inativo';
    end if;
  else
    v_plano_id := v_assinatura.plano_id;
  end if;

  -- Webhooks podem chegar fora de ordem. Eventos mais antigos sao preservados no historico,
  -- mas nunca podem retroceder o estado comercial corrente, mesmo que sua transicao hoje
  -- ja nao seja valida.
  if v_assinatura.provedor_ultimo_evento_em is not null
     and v_ocorrido_em < v_assinatura.provedor_ultimo_evento_em then
    insert into public.assinatura_eventos(
      assinatura_id,empresa_id,provedor,provedor_evento_id,
      provedor_cliente_id,provedor_assinatura_id,provedor_preco_id,tipo_evento,
      status_anterior,status_novo,plano_codigo_solicitado,plano_anterior_id,plano_novo_id,
      periodo_inicio,periodo_fim,ocorrido_em,aplicado,motivo,metadata
    ) values (
      v_assinatura.id,p_empresa_id,v_provedor,v_evento_ref,
      v_cliente_ref,v_assinatura_ref,v_preco_ref,v_tipo,
      v_assinatura.status,v_status_novo,v_plano_codigo,v_assinatura.plano_id,v_plano_id,
      p_periodo_inicio,p_periodo_fim,v_ocorrido_em,false,'evento_fora_de_ordem',p_metadata
    ) returning id into v_evento_id;

    return query select v_assinatura.id,p_empresa_id,v_assinatura.status,v_assinatura.plano_id,v_evento_id,false;
    return;
  end if;

  v_troca_provedor := v_assinatura.provedor is not null and v_assinatura.provedor <> v_provedor;

  if v_troca_provedor
     and v_assinatura.status not in ('canceled','expired') then
    raise exception using errcode='23514', message='Provedor da assinatura nao pode ser alterado neste estado';
  end if;

  if v_assinatura.provedor_assinatura_id is not null
     and v_assinatura_ref is not null
     and v_assinatura.provedor_assinatura_id <> v_assinatura_ref
     and v_assinatura.status not in ('canceled','expired') then
    raise exception using errcode='23514', message='Referencia da assinatura do provedor nao pode ser alterada neste estado';
  end if;

  if v_status_novo <> 'active'
     and v_plano_id is distinct from v_assinatura.plano_id then
    raise exception using errcode='23514', message='Mudanca de plano exige confirmacao de assinatura ativa';
  end if;

  v_transicao_valida := (
    v_assinatura.status = v_status_novo
    or (v_assinatura.status='trialing' and v_status_novo in ('active','canceled','expired'))
    or (v_assinatura.status='active' and v_status_novo in ('past_due','paused','canceled','expired'))
    or (v_assinatura.status='past_due' and v_status_novo in ('active','paused','canceled','expired'))
    or (v_assinatura.status='paused' and v_status_novo in ('active','canceled','expired'))
    or (v_assinatura.status='canceled' and v_status_novo in ('active','expired'))
    or (v_assinatura.status='expired' and v_status_novo='active')
  );

  if not v_transicao_valida then
    raise exception using errcode='23514',
      message=format('Transicao comercial invalida: %s -> %s',v_assinatura.status,v_status_novo);
  end if;

  if v_status_novo='active' then
    if v_plano_id is null then
      raise exception using errcode='22023', message='Assinatura ativa exige plano valido';
    end if;
    if coalesce(p_periodo_inicio,v_assinatura.periodo_inicio) is null
       or coalesce(p_periodo_fim,v_assinatura.periodo_fim) is null
       or coalesce(p_periodo_fim,v_assinatura.periodo_fim) <= coalesce(p_periodo_inicio,v_assinatura.periodo_inicio) then
      raise exception using errcode='22023', message='Assinatura ativa exige periodo de vigencia valido';
    end if;
    if coalesce(
         v_assinatura_ref,
         case when v_troca_provedor then null else v_assinatura.provedor_assinatura_id end
       ) is null then
      raise exception using errcode='22023', message='Assinatura ativa exige referencia no provedor';
    end if;

    select pe.valor_inteiro into v_limite_usuarios
    from public.plano_entitlements pe
    where pe.plano_id=v_plano_id and pe.chave='usuarios_ativos.max' and pe.tipo='inteiro';

    select pe.valor_inteiro into v_limite_unidades
    from public.plano_entitlements pe
    where pe.plano_id=v_plano_id and pe.chave='unidades.max' and pe.tipo='inteiro';

    select count(*) into v_consumo_unidades
    from public.unidades u
    where u.empresa_id=p_empresa_id and u.ativo;

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
  end if;

  update public.empresa_assinaturas ea
  set plano_id=v_plano_id,
      status=v_status_novo,
      periodo_inicio=coalesce(p_periodo_inicio,ea.periodo_inicio),
      periodo_fim=coalesce(p_periodo_fim,ea.periodo_fim),
      provedor=v_provedor,
      provedor_cliente_id=case when v_troca_provedor then v_cliente_ref else coalesce(v_cliente_ref,ea.provedor_cliente_id) end,
      provedor_assinatura_id=case when v_troca_provedor then v_assinatura_ref else coalesce(v_assinatura_ref,ea.provedor_assinatura_id) end,
      provedor_preco_id=case when v_troca_provedor then v_preco_ref else coalesce(v_preco_ref,ea.provedor_preco_id) end,
      metadata=ea.metadata || p_metadata || jsonb_build_object('ultimo_tipo_evento',v_tipo,'ultimo_evento_id',v_evento_ref),
      converted_at=case when v_status_novo='active' then coalesce(ea.converted_at,v_ocorrido_em) else ea.converted_at end,
      status_changed_at=case when ea.status is distinct from v_status_novo then v_ocorrido_em else ea.status_changed_at end,
      provedor_ultimo_evento_em=v_ocorrido_em,
      updated_at=now()
  where ea.id=v_assinatura.id;

  if v_status_novo='active' then
    insert into public.empresa_planos(empresa_id,plano_id,origem,assigned_at,assigned_by,updated_at)
    values(p_empresa_id,v_plano_id,'assinatura',now(),null,now())
    on conflict (empresa_id) do update
      set plano_id=excluded.plano_id,
          origem='assinatura',
          assigned_at=excluded.assigned_at,
          assigned_by=null,
          updated_at=excluded.updated_at;
  end if;

  insert into public.assinatura_eventos(
    assinatura_id,empresa_id,provedor,provedor_evento_id,
    provedor_cliente_id,provedor_assinatura_id,provedor_preco_id,tipo_evento,
    status_anterior,status_novo,plano_codigo_solicitado,plano_anterior_id,plano_novo_id,
    periodo_inicio,periodo_fim,ocorrido_em,aplicado,motivo,metadata
  ) values (
    v_assinatura.id,p_empresa_id,v_provedor,v_evento_ref,
    v_cliente_ref,v_assinatura_ref,v_preco_ref,v_tipo,
    v_assinatura.status,v_status_novo,v_plano_codigo,v_assinatura.plano_id,v_plano_id,
    p_periodo_inicio,p_periodo_fim,v_ocorrido_em,true,null,p_metadata
  ) returning id into v_evento_id;

  return query
  select ea.id,ea.empresa_id,ea.status,ea.plano_id,v_evento_id,true
  from public.empresa_assinaturas ea
  where ea.id=v_assinatura.id;
end
$function$;

revoke all on function public.processar_evento_assinatura_server(
  uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb
) from public, anon, authenticated;
grant execute on function public.processar_evento_assinatura_server(
  uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb
) to service_role;

comment on table public.assinatura_eventos is
  'Historico imutavel de eventos comerciais confiaveis; chave do provedor garante idempotencia e eventos fora de ordem nao retrocedem o workspace.';
comment on function public.processar_evento_assinatura_server(
  uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,timestamptz,jsonb
) is
  'Contrato provider-neutral exclusivo do backend para aplicar eventos de assinatura de forma idempotente, ordenada e com validacao de transicoes/limites.';

reset lock_timeout;
reset statement_timeout;
