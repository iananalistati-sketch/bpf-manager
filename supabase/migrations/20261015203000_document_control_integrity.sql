-- Revisao consolidada do Marco 2. A fundacao anterior permanece imutavel.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Nao inventar historico se a fundacao ja recebeu revisoes: os dados antigos
-- precisam de reconciliacao com a auditoria antes desta migration.
do $block$
begin
  if exists (select 1 from public.documento_versoes group by documento_id having count(*)>1) then
    raise exception using errcode='55000', message='Reconciliar metadados historicos de documentos com multiplas versoes antes da migration de integridade';
  end if;
end
$block$;

alter table public.documentos add constraint documentos_unidade_empresa_fkey
  foreign key (unidade_id,empresa_id) references public.unidades(id,empresa_id);

-- Evidencia versionada: identidade/codigo ficam em documentos; conteudo e escopo em cada versao.
alter table public.documento_versoes
  add column titulo text,
  add column tipo text,
  add column unidade_id uuid references public.unidades(id) on update no action on delete no action;
update public.documento_versoes v
set titulo=d.titulo,tipo=d.tipo,unidade_id=d.unidade_id
from public.documentos d where d.id=v.documento_id;
alter table public.documento_versoes
  alter column titulo set not null,
  alter column tipo set not null,
  add constraint documento_versoes_titulo_check check(length(btrim(titulo)) between 3 and 180),
  add constraint documento_versoes_tipo_check check(length(btrim(tipo)) between 2 and 80);

-- Retornos recebem campos novos; substituicao explicita mantem os nomes/argumentos existentes.
drop function public.documentos_listar(uuid,uuid);
drop function public.documento_historico(uuid);
-- Argumento opcional protege clientes atuais contra acoes atrasadas em outra versao.
drop function public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date);
drop function public.documento_transicionar(uuid,text,text);
drop function public.documento_iniciar_revisao(uuid,text,date);
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
    join public.empresas e on e.id=p_empresa_id and e.ativo
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
    join public.empresas e on e.id=p_empresa_id and e.ativo
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
  updated_at timestamptz,
  vigente_numero integer,
  vigente_revisao_prevista_em date
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
    d.id,d.empresa_id,v.unidade_id,d.codigo,v.titulo,v.tipo,d.ativo,
    v.id,v.numero,v.status,v.descricao,v.revisao_prevista_em,
    v.autor_id,v.revisor_id,v.aprovador_id,v.vigencia_inicio,
    greatest(d.updated_at,v.updated_at),
    vigente.numero,vigente.revisao_prevista_em
  from public.documentos d
  join lateral (
    select dv.*
    from public.documento_versoes dv
    where dv.documento_id=d.id
    order by dv.numero desc
    limit 1
  ) v on true
  left join public.documento_versoes vigente
    on vigente.documento_id=d.id and vigente.status='vigente'
  where d.empresa_id=p_empresa_id
    and d.ativo
    and (p_unidade_id is null or v.unidade_id is null or v.unidade_id=p_unidade_id
      or vigente.unidade_id is null and vigente.id is not null or vigente.unidade_id=p_unidade_id)
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
  updated_at timestamptz,
  titulo text,
  tipo text,
  unidade_id uuid
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
    dv.created_at,dv.updated_at,dv.titulo,dv.tipo,dv.unidade_id
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
    documento_id,numero,status,descricao,revisao_prevista_em,autor_id,titulo,tipo,unidade_id
  ) values (
    v_documento_id,1,'rascunho',nullif(btrim(coalesce(p_descricao,'')),''),p_revisao_prevista_em,v_subject,btrim(p_titulo),btrim(p_tipo),p_unidade_id
  ) returning id into v_versao_id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,p_unidade_id,v_subject,'documento',v_documento_id,'documento.criado',null,
    jsonb_build_object('codigo',btrim(p_codigo),'titulo',btrim(p_titulo),'tipo',btrim(p_tipo),'unidade_id',p_unidade_id,'descricao',nullif(btrim(coalesce(p_descricao,'')),''),'revisao_prevista_em',p_revisao_prevista_em,'versao',1,'status','rascunho'),
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
  p_revisao_prevista_em date,
  p_versao_id uuid default null
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
  v_antes jsonb;
begin
  select d.empresa_id into v_empresa_id
  from public.documentos d
  where d.id=p_documento_id and d.ativo
    and private.tenant_tem_permissao(d.empresa_id,'documentos.editar')
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

  if v_versao.id is null or (p_versao_id is not null and p_versao_id<>v_versao.id) then
    raise exception using errcode='40001', message='Versao desatualizada; recarregue o documento';
  end if;
  if v_versao.status <> 'rascunho' then
    raise exception using errcode='23514', message='Somente a versao em rascunho pode ser editada';
  end if;

  select jsonb_build_object(
    'unidade_id',v_versao.unidade_id,
    'titulo',v_versao.titulo,
    'tipo',v_versao.tipo,
    'descricao',v_versao.descricao,
    'revisao_prevista_em',v_versao.revisao_prevista_em
  ) into v_antes
  from public.documentos d
  where d.id=p_documento_id;

  update public.documentos
  set unidade_id=p_unidade_id,titulo=btrim(p_titulo),tipo=btrim(p_tipo),updated_at=now()
  where id=p_documento_id
    and not exists (select 1 from public.documento_versoes where documento_id=p_documento_id and status='vigente');

  update public.documento_versoes
  set titulo=btrim(p_titulo),tipo=btrim(p_tipo),unidade_id=p_unidade_id,
      descricao=nullif(btrim(coalesce(p_descricao,'')),''),
      revisao_prevista_em=p_revisao_prevista_em,
      updated_at=now()
  where id=v_versao.id;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values (
    v_empresa_id,p_unidade_id,v_subject,'documento',p_documento_id,'documento.rascunho_atualizado',
    v_antes,
    jsonb_build_object(
      'unidade_id',p_unidade_id,
      'titulo',btrim(p_titulo),
      'tipo',btrim(p_tipo),
      'descricao',nullif(btrim(coalesce(p_descricao,'')),''),
      'revisao_prevista_em',p_revisao_prevista_em,
      'versao',v_versao.numero
    ),
    'Atualizacao de rascunho',
    jsonb_build_object('versao_id',v_versao.id)
  );
end
$function$;

create or replace function public.documento_transicionar(
  p_documento_id uuid,
  p_status_destino text,
  p_justificativa text,
  p_versao_id uuid default null
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
    and (private.tenant_tem_permissao(d.empresa_id,'documentos.editar') or private.tenant_tem_permissao(d.empresa_id,'documentos.aprovar'))
  for update;

  if v_empresa_id is null or not (
    private.tenant_tem_permissao(v_empresa_id,'documentos.editar')
    or private.tenant_tem_permissao(v_empresa_id,'documentos.aprovar')
  ) then
    raise exception using errcode='42501', message='Documento nao autorizado para a sessao';
  end if;

  select dv.* into v_versao
  from public.documento_versoes dv
  where dv.documento_id=p_documento_id
  order by dv.numero desc
  limit 1
  for update;

  if v_versao.id is null or (p_versao_id is not null and p_versao_id<>v_versao.id) then
    raise exception using errcode='40001', message='Versao desatualizada; recarregue o documento';
  end if;
  v_unidade_id := v_versao.unidade_id;

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
    -- A obsolescencia da versao anterior tem evidencia propria na mesma transacao.
    with anteriores as (
      update public.documento_versoes
      set status='obsoleto',obsoleto_em=now(),updated_at=now()
      where documento_id=p_documento_id and status='vigente' and id<>v_versao.id
      returning id,numero,unidade_id
    )
    insert into public.auditoria_eventos(
      empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
    ) select v_empresa_id,a.unidade_id,v_subject,'documento',p_documento_id,'documento.versao_substituida',
      jsonb_build_object('versao',a.numero,'status','vigente'),
      jsonb_build_object('versao',a.numero,'status','obsoleto'),btrim(p_justificativa),
      jsonb_build_object('versao_id',a.id,'substituida_por',v_versao.id)
    from anteriores a;
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

  update public.documentos
  set updated_at=now(),
      titulo=case when v_status_destino='vigente' then v_versao.titulo else titulo end,
      tipo=case when v_status_destino='vigente' then v_versao.tipo else tipo end,
      unidade_id=case when v_status_destino='vigente' then v_versao.unidade_id else unidade_id end
  where id=p_documento_id;

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
  p_revisao_prevista_em date default null,
  p_versao_id uuid default null
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
    and private.tenant_tem_permissao(d.empresa_id,'documentos.editar')
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

  if v_ultima.id is null or (p_versao_id is not null and p_versao_id<>v_ultima.id) then
    raise exception using errcode='40001', message='Versao desatualizada; recarregue o documento';
  end if;
  if v_ultima.status <> 'vigente' then
    raise exception using errcode='23514', message='Nova revisao so pode partir da versao vigente mais recente';
  end if;

  insert into public.documento_versoes(
    documento_id,numero,status,descricao,motivo_revisao,revisao_prevista_em,autor_id,titulo,tipo,unidade_id
  ) values (
    p_documento_id,v_ultima.numero+1,'rascunho',v_ultima.descricao,btrim(p_motivo_revisao),
    coalesce(p_revisao_prevista_em,v_ultima.revisao_prevista_em),v_subject,
    v_ultima.titulo,v_ultima.tipo,v_ultima.unidade_id
  ) returning id into v_nova_id;

  v_unidade_id := v_ultima.unidade_id;
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

revoke all on function public.documentos_listar(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.documentos_listar(uuid,uuid) to authenticated;
revoke all on function public.documento_historico(uuid) from public,anon,authenticated,service_role;
grant execute on function public.documento_historico(uuid) to authenticated;
revoke all on function public.documento_criar(uuid,uuid,text,text,text,text,date) from public,anon,authenticated,service_role;
grant execute on function public.documento_criar(uuid,uuid,text,text,text,text,date) to authenticated;
revoke all on function public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date,uuid) from public,anon,authenticated,service_role;
grant execute on function public.documento_rascunho_atualizar(uuid,uuid,text,text,text,date,uuid) to authenticated;
revoke all on function public.documento_transicionar(uuid,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.documento_transicionar(uuid,text,text,uuid) to authenticated;
revoke all on function public.documento_iniciar_revisao(uuid,text,date,uuid) from public,anon,authenticated,service_role;
grant execute on function public.documento_iniciar_revisao(uuid,text,date,uuid) to authenticated;
revoke all on function private.tenant_tem_permissao(uuid,text) from public,anon,authenticated,service_role;
revoke all on function private.assert_tenant_workspace_write_allowed(uuid) from public,anon,authenticated,service_role;

comment on table public.documento_versoes is 'Snapshots de conteudo e escopo por versao; revisoes preservam evidencia vigente e historica. Arquivos Storage futuros devem referenciar o ID da versao.';
reset lock_timeout;
reset statement_timeout;
