-- Marco 2 / Documentos: fundacao de documentos controlados, versionamento e workflow auditavel.
set lock_timeout = '5s';
set statement_timeout = '60s';

insert into public.permissoes(codigo, modulo, acao, descricao)
values
  ('documentos.visualizar','documentos','visualizar','Consultar documentos controlados do tenant'),
  ('documentos.criar','documentos','criar','Criar documentos controlados no tenant'),
  ('documentos.editar','documentos','editar','Editar rascunhos e conduzir revisoes de documentos'),
  ('documentos.aprovar','documentos','aprovar','Aprovar, publicar e tornar obsoletos documentos controlados')
on conflict (codigo) do nothing;

create table public.documentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on update no action on delete no action,
  unidade_id uuid null references public.unidades(id) on update no action on delete no action,
  codigo text not null,
  titulo text not null,
  tipo text not null,
  ativo boolean not null default true,
  created_by uuid not null references public.usuarios(id) on update no action on delete no action,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint documentos_codigo_check check (
    length(btrim(codigo)) between 2 and 60
  ),
  constraint documentos_titulo_check check (
    length(btrim(titulo)) between 3 and 180
  ),
  constraint documentos_tipo_check check (
    length(btrim(tipo)) between 2 and 80
  )
);

create unique index idx_documentos_empresa_codigo_ativo
  on public.documentos(empresa_id, lower(btrim(codigo)))
  where ativo;
create index idx_documentos_empresa_unidade
  on public.documentos(empresa_id, unidade_id, updated_at desc);

create table public.documento_versoes (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos(id) on update no action on delete no action,
  numero integer not null check (numero > 0),
  status text not null check (
    status in ('rascunho','em_revisao','aguardando_aprovacao','aprovado','vigente','obsoleto')
  ),
  descricao text null,
  motivo_revisao text null,
  revisao_prevista_em date null,
  autor_id uuid not null references public.usuarios(id) on update no action on delete no action,
  revisor_id uuid null references public.usuarios(id) on update no action on delete no action,
  aprovador_id uuid null references public.usuarios(id) on update no action on delete no action,
  enviado_revisao_em timestamptz null,
  revisado_em timestamptz null,
  enviado_aprovacao_em timestamptz null,
  aprovado_em timestamptz null,
  vigencia_inicio timestamptz null,
  obsoleto_em timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint documento_versoes_documento_numero_key unique(documento_id, numero),
  constraint documento_versoes_descricao_check check (
    descricao is null or length(descricao) <= 10000
  ),
  constraint documento_versoes_motivo_check check (
    motivo_revisao is null or length(btrim(motivo_revisao)) between 3 and 1000
  ),
  constraint documento_versoes_status_datas_check check (
    (status <> 'vigente' or vigencia_inicio is not null)
    and (status <> 'obsoleto' or obsoleto_em is not null)
    and (status not in ('aprovado','vigente','obsoleto') or aprovado_em is not null)
  )
);

create index idx_documento_versoes_documento_numero
  on public.documento_versoes(documento_id, numero desc);
create unique index idx_documento_versoes_um_vigente
  on public.documento_versoes(documento_id)
  where status='vigente';

alter table public.documentos enable row level security;
alter table public.documento_versoes enable row level security;
revoke all on table public.documentos from public, anon, authenticated, service_role;
revoke all on table public.documento_versoes from public, anon, authenticated, service_role;

create or replace function private.tenant_tem_permissao(p_empresa_id uuid, p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue
      on ue.usuario_id=u.id
     and ue.empresa_id=p_empresa_id
     and ue.status='ativo'
    join public.usuario_empresa_perfis uep on uep.usuario_empresa_id=ue.id
    join public.perfis p
      on p.id=uep.perfil_id
     and p.ativo
     and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
    join public.perfil_permissoes pp on pp.perfil_id=p.id
    join public.permissoes pm on pm.id=pp.permissao_id
    where u.id=private.request_jwt_subject()
      and u.ativo and u.status='ativo'
      and pm.codigo=p_codigo
  )
$function$;

create or replace function private.assert_tenant_workspace_write_allowed(p_empresa_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_status text;
  v_trial_fim timestamptz;
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
    raise exception using errcode='42501', message='Tenant indisponivel para escrita';
  end if;

  select ea.status,ea.trial_fim into v_status,v_trial_fim
  from public.empresa_assinaturas ea
  where ea.empresa_id=p_empresa_id;

  if not found then return; end if;
  if v_status='active' then return; end if;
  if v_status='trialing' and v_trial_fim is not null and v_trial_fim > now() then return; end if;

  raise exception using errcode='42501', message='Workspace em modo somente leitura';
end
$function$;

revoke all on function private.tenant_tem_permissao(uuid,text) from public,anon,authenticated,service_role;
revoke all on function private.assert_tenant_workspace_write_allowed(uuid) from public,anon,authenticated,service_role;

create or replace function public.documentos_listar(
  p_empresa_id uuid,
  p_unidade_id uuid default null
)
returns table (
  documento_id uuid,
  empresa_id uuid,
  unidade_id uuid,
  codigo text,
  titulo text,
  tipo text,
  ativo boolean,
  versao_id uuid,
  versao_numero integer,
  status text,
  descricao text,
  revisao_prevista_em date,
  autor_id uuid,
  revisor_id uuid,
  aprovador_id uuid,
  vigencia_inicio timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.tenant_tem_permissao(p_empresa_id,'documentos.visualizar') then
    raise exception using errcode='42501', message='Sem permissao para visualizar documentos';
  end if;

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades un
    where un.id=p_unidade_id and un.empresa_id=p_empresa_id
  ) then
    raise exception using errcode='42501', message='Unidade nao pertence ao tenant';
  end if;

  return query
  select
    d.id,d.empresa_id,d.unidade_id,d.codigo,d.titulo,d.tipo,d.ativo,
    v.id,v.numero,v.status,v.descricao,v.revisao_prevista_em,
    v.autor_id,v.revisor_id,v.aprovador_id,v.vigencia_inicio,
    greatest(d.updated_at,v.updated_at)
  from public.documentos d
  join lateral (
    select dv.*
    from public.documento_versoes dv
    where dv.documento_id=d.id
    order by dv.numero desc
    limit 1
  ) v on true
  where d.empresa_id=p_empresa_id
    and d.ativo
    and (p_unidade_id is null or d.unidade_id is null or d.unidade_id=p_unidade_id)
  order by d.codigo,d.titulo;
end
$function$;

create or replace function public.documento_historico(p_documento_id uuid)
returns table (
  versao_id uuid,
  numero integer,
  status text,
  descricao text,
  motivo_revisao text,
  revisao_prevista_em date,
  autor_id uuid,
  revisor_id uuid,
  aprovador_id uuid,
  enviado_revisao_em timestamptz,
  revisado_em timestamptz,
  enviado_aprovacao_em timestamptz,
  aprovado_em timestamptz,
  vigencia_inicio timestamptz,
  obsoleto_em timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_empresa_id uuid;
begin
  select d.empresa_id into v_empresa_id
  from public.documentos d
  where d.id=p_documento_id and d.ativo;

  if v_empresa_id is null
     or not private.tenant_tem_permissao(v_empresa_id,'documentos.visualizar') then
    raise exception using errcode='42501', message='Documento nao autorizado para a sessao';
  end if;

  return query
  select
    dv.id,dv.numero,dv.status,dv.descricao,dv.motivo_revisao,dv.revisao_prevista_em,
    dv.autor_id,dv.revisor_id,dv.aprovador_id,dv.enviado_revisao_em,dv.revisado_em,
    dv.enviado_aprovacao_em,dv.aprovado_em,dv.vigencia_inicio,dv.obsoleto_em,
    dv.created_at,dv.updated_at
  from public.documento_versoes dv
  where dv.documento_id=p_documento_id
  order by dv.numero desc;
end
$function$;

create or replace function public.documento_criar(
  p_empresa_id uuid,
  p_unidade_id uuid,
  p_codigo text,
  p_titulo text,
  p_tipo text,
  p_descricao text,
  p_revisao_prevista_em date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_documento_id uuid;
  v_versao_id uuid;
begin
  if not private.tenant_tem_permissao(p_empresa_id,'documentos.criar') then
    raise exception using errcode='42501', message='Sem permissao para criar documentos';
  end if;
  perform private.assert_tenant_workspace_write_allowed(p_empresa_id);

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades un
    where un.id=p_unidade_id and un.empresa_id=p_empresa_id and un.ativo
  ) then
    raise exception using errcode='23514', message='Unidade invalida para o documento';
  end if;

  if length(btrim(coalesce(p_codigo,''))) not between 2 and 60
     or length(btrim(coalesce(p_titulo,''))) not between 3 and 180
     or length(btrim(coalesce(p_tipo,''))) not between 2 and 80
     or length(coalesce(p_descricao,'')) > 10000 then
    raise exception using errcode='22023', message='Dados invalidos para o documento';
  end if;

  insert into public.documentos(
    empresa_id,unidade_id,codigo,titulo,tipo,created_by
  ) values (
    p_empresa_id,p_unidade_id,btrim(p_codigo),btrim(p_titulo),btrim(p_tipo),v_subject
  ) returning id into v_documento_id;

  insert into public.documento_versoes(
    documento_id,numero,status,descricao,revisao_prevista_em,autor_id
  ) values (
    v_documento_id,1,'rascunho',nullif(btrim(coalesce(p_descricao,'')),''),p_revisao_prevista_em,v_subject
  ) returning id into v_versao_id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,p_unidade_id,v_subject,'documento',v_documento_id,'documento.criado',null,
    jsonb_build_object('codigo',btrim(p_codigo),'titulo',btrim(p_titulo),'tipo',btrim(p_tipo),'versao',1,'status','rascunho'),
    'Criacao de documento controlado',
    jsonb_build_object('versao_id',v_versao_id)
  );

  return v_documento_id;
end
$function$;

create or replace function public.documento_rascunho_atualizar(
  p_documento_id uuid,
  p_unidade_id uuid,
  p_titulo text,
  p_tipo text,
  p_descricao text,
  p_revisao_prevista_em date
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_empresa_id uuid;
  v_versao public.documento_versoes%rowtype;
begin
  select d.empresa_id into v_empresa_id
  from public.documentos d
  where d.id=p_documento_id and d.ativo
  for update;

  if v_empresa_id is null
     or not private.tenant_tem_permissao(v_empresa_id,'documentos.editar') then
    raise exception using errcode='42501', message='Sem permissao para editar documento';
  end if;
  perform private.assert_tenant_workspace_write_allowed(v_empresa_id);

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades un
    where un.id=p_unidade_id and un.empresa_id=v_empresa_id and un.ativo
  ) then
    raise exception using errcode='23514', message='Unidade invalida para o documento';
  end if;

  if length(btrim(coalesce(p_titulo,''))) not between 3 and 180
     or length(btrim(coalesce(p_tipo,''))) not between 2 and 80
     or length(coalesce(p_descricao,'')) > 10000 then
    raise exception using errcode='22023', message='Dados invalidos para o documento';
  end if;

  select dv.* into v_versao
  from public.documento_versoes dv
  where dv.documento_id=p_documento_id
  order by dv.numero desc
  limit 1
  for update;

  if v_versao.status <> 'rascunho' then
    raise exception using errcode='23514', message='Somente a versao em rascunho pode ser editada';
  end if;

  update public.documentos
  set unidade_id=p_unidade_id,titulo=btrim(p_titulo),tipo=btrim(p_tipo),updated_at=now()
  where id=p_documento_id;

  update public.documento_versoes
  set descricao=nullif(btrim(coalesce(p_descricao,'')),''),
      revisao_prevista_em=p_revisao_prevista_em,
      updated_at=now()
  where id=v_versao.id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    v_empresa_id,p_unidade_id,v_subject,'documento',p_documento_id,'documento.rascunho_atualizado',
    jsonb_build_object('titulo',(select titulo from public.documentos where id=p_documento_id)),
    jsonb_build_object('titulo',btrim(p_titulo),'tipo',btrim(p_tipo),'versao',v_versao.numero),
    'Atualizacao de rascunho',
    jsonb_build_object('versao_id',v_versao.id)
  );
end
$function$;

create or replace function public.documento_transicionar(
  p_documento_id uuid,
  p_status_destino text,
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_empresa_id uuid;
  v_unidade_id uuid;
  v_status_destino text := lower(btrim(coalesce(p_status_destino,'')));
  v_versao public.documento_versoes%rowtype;
  v_permission text;
begin
  select d.empresa_id,d.unidade_id into v_empresa_id,v_unidade_id
  from public.documentos d
  where d.id=p_documento_id and d.ativo
  for update;

  if v_empresa_id is null then
    raise exception using errcode='P0002', message='Documento nao encontrado';
  end if;

  select dv.* into v_versao
  from public.documento_versoes dv
  where dv.documento_id=p_documento_id
  order by dv.numero desc
  limit 1
  for update;

  if v_versao.status='rascunho' and v_status_destino='em_revisao' then
    v_permission := 'documentos.editar';
  elsif v_versao.status='em_revisao' and v_status_destino='aguardando_aprovacao' then
    v_permission := 'documentos.editar';
  elsif v_versao.status='aguardando_aprovacao' and v_status_destino='aprovado' then
    v_permission := 'documentos.aprovar';
  elsif v_versao.status='aprovado' and v_status_destino='vigente' then
    v_permission := 'documentos.aprovar';
  elsif v_versao.status='vigente' and v_status_destino='obsoleto' then
    v_permission := 'documentos.aprovar';
  else
    raise exception using errcode='23514',
      message=format('Transicao documental invalida: %s -> %s',v_versao.status,v_status_destino);
  end if;

  if not private.tenant_tem_permissao(v_empresa_id,v_permission) then
    raise exception using errcode='42501', message='Sem permissao para esta transicao documental';
  end if;
  perform private.assert_tenant_workspace_write_allowed(v_empresa_id);

  if length(btrim(coalesce(p_justificativa,''))) < 5
     or length(btrim(p_justificativa)) > 1000 then
    raise exception using errcode='22023', message='Justificativa documental invalida';
  end if;

  if v_status_destino='vigente' then
    update public.documento_versoes
    set status='obsoleto',obsoleto_em=now(),updated_at=now()
    where documento_id=p_documento_id
      and status='vigente'
      and id<>v_versao.id;
  end if;

  update public.documento_versoes
  set status=v_status_destino,
      revisor_id=case when v_status_destino='aguardando_aprovacao' then v_subject else revisor_id end,
      aprovador_id=case when v_status_destino in ('aprovado','vigente') then coalesce(aprovador_id,v_subject) else aprovador_id end,
      enviado_revisao_em=case when v_status_destino='em_revisao' then now() else enviado_revisao_em end,
      revisado_em=case when v_status_destino='aguardando_aprovacao' then now() else revisado_em end,
      enviado_aprovacao_em=case when v_status_destino='aguardando_aprovacao' then now() else enviado_aprovacao_em end,
      aprovado_em=case when v_status_destino='aprovado' then now() else aprovado_em end,
      vigencia_inicio=case when v_status_destino='vigente' then now() else vigencia_inicio end,
      obsoleto_em=case when v_status_destino='obsoleto' then now() else obsoleto_em end,
      updated_at=now()
  where id=v_versao.id;

  update public.documentos set updated_at=now() where id=p_documento_id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    v_empresa_id,v_unidade_id,v_subject,'documento',p_documento_id,'documento.status_alterado',
    jsonb_build_object('versao',v_versao.numero,'status',v_versao.status),
    jsonb_build_object('versao',v_versao.numero,'status',v_status_destino),
    btrim(p_justificativa),
    jsonb_build_object('versao_id',v_versao.id,'permission',v_permission)
  );
end
$function$;

create or replace function public.documento_iniciar_revisao(
  p_documento_id uuid,
  p_motivo_revisao text,
  p_revisao_prevista_em date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subject uuid := private.request_jwt_subject();
  v_empresa_id uuid;
  v_unidade_id uuid;
  v_ultima public.documento_versoes%rowtype;
  v_nova_id uuid;
begin
  select d.empresa_id,d.unidade_id into v_empresa_id,v_unidade_id
  from public.documentos d
  where d.id=p_documento_id and d.ativo
  for update;

  if v_empresa_id is null
     or not private.tenant_tem_permissao(v_empresa_id,'documentos.editar') then
    raise exception using errcode='42501', message='Sem permissao para revisar documento';
  end if;
  perform private.assert_tenant_workspace_write_allowed(v_empresa_id);

  if length(btrim(coalesce(p_motivo_revisao,''))) not between 3 and 1000 then
    raise exception using errcode='22023', message='Motivo de revisao invalido';
  end if;

  select dv.* into v_ultima
  from public.documento_versoes dv
  where dv.documento_id=p_documento_id
  order by dv.numero desc
  limit 1
  for update;

  if v_ultima.status <> 'vigente' then
    raise exception using errcode='23514', message='Nova revisao so pode partir da versao vigente mais recente';
  end if;

  insert into public.documento_versoes(
    documento_id,numero,status,descricao,motivo_revisao,revisao_prevista_em,autor_id
  ) values (
    p_documento_id,v_ultima.numero+1,'rascunho',v_ultima.descricao,btrim(p_motivo_revisao),
    coalesce(p_revisao_prevista_em,v_ultima.revisao_prevista_em),v_subject
  ) returning id into v_nova_id;

  update public.documentos set updated_at=now() where id=p_documento_id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    v_empresa_id,v_unidade_id,v_subject,'documento',p_documento_id,'documento.revisao_iniciada',
    jsonb_build_object('versao',v_ultima.numero,'status',v_ultima.status),
    jsonb_build_object('versao',v_ultima.numero+1,'status','rascunho'),
    btrim(p_motivo_revisao),
    jsonb_build_object('versao_anterior_id',v_ultima.id,'nova_versao_id',v_nova_id)
  );

  return v_nova_id;
end
$function$;

revoke all on function public.documentos_listar(uuid,uuid) from public,anon,service_role;
revoke all on function public.documento_historico(uuid) from public,anon,service_role;
revoke all on function public.documento_criar(uuid,uuid,text,text,text,text,date) from public,anon,service_role;
revoke all on function public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date) from public,anon,service_role;
revoke all on function public.documento_transicionar(uuid,text,text) from public,anon,service_role;
revoke all on function public.documento_iniciar_revisao(uuid,text,date) from public,anon,service_role;

grant execute on function public.documentos_listar(uuid,uuid) to authenticated;
grant execute on function public.documento_historico(uuid) to authenticated;
grant execute on function public.documento_criar(uuid,uuid,text,text,text,text,date) to authenticated;
grant execute on function public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date) to authenticated;
grant execute on function public.documento_transicionar(uuid,text,text) to authenticated;
grant execute on function public.documento_iniciar_revisao(uuid,text,date) to authenticated;

comment on table public.documentos is
  'Cadastro tenant-aware de documentos controlados; codigo e identidade permanecem estaveis entre revisoes.';
comment on table public.documento_versoes is
  'Historico imutavel por numero de versao com workflow rascunho -> revisao -> aprovacao -> vigente -> obsoleto.';
comment on function private.tenant_tem_permissao(uuid,text) is
  'Autorizacao tenant-aware baseada no subject JWT, membership ativo e perfis do membership.';
comment on function private.assert_tenant_workspace_write_allowed(uuid) is
  'Gate comercial tenant-aware para novas mutacoes operacionais; active ou trial valido escrevem, legados sem assinatura permanecem compativeis.';

reset lock_timeout;
reset statement_timeout;
