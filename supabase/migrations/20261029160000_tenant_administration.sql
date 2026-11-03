-- Administration follows the selected membership, never an implicit UI tenant.
set lock_timeout='5s';
set statement_timeout='60s';

create role bpf_tenant_admin nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
grant bpf_tenant_admin to postgres with inherit false,set true;
grant usage on schema public,private to bpf_tenant_admin;
grant create on schema private to bpf_tenant_admin;

create function private.admin_permissions(p_empresa uuid,p_usuario uuid)
returns text[] language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(distinct pm.codigo),'{}'::text[])
  from public.usuarios u
  join public.usuario_empresas ue on ue.usuario_id=u.id and ue.empresa_id=p_empresa and ue.status='ativo'
  join public.empresas e on e.id=ue.empresa_id and e.ativo
  join public.usuario_empresa_perfis up on up.usuario_empresa_id=ue.id
  join public.perfis p on p.id=up.perfil_id and p.ativo and
    ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa)
  join public.perfil_permissoes pp on pp.perfil_id=p.id
  join public.permissoes pm on pm.id=pp.permissao_id
  where u.id=p_usuario and u.ativo and u.status='ativo'
$$;

create function private.admin_scope_id()
returns uuid language sql stable security definer set search_path='' as $$
  select e.id from public.empresas e
  where e.id=nullif(current_setting('bpf.admin_empresa',true),'')::uuid
    and 'configuracoes.visualizar'=any(private.admin_permissions(e.id,private.request_jwt_subject()))
$$;

create function private.admin_assert(p_empresa uuid,p_permission text,p_write boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_empresa is null or not coalesce(array['configuracoes.visualizar',p_permission]
      <@ private.admin_permissions(p_empresa,private.request_jwt_subject()),false) then
    raise exception using errcode='42501',message='Acesso administrativo nao autorizado nesta empresa';
  end if;
  if p_write then
    perform pg_advisory_xact_lock(hashtextextended(p_empresa::text,0));
    if not array['configuracoes.visualizar',p_permission]
      <@ private.admin_permissions(p_empresa,private.request_jwt_subject()) then
      raise exception using errcode='42501',message='Acesso administrativo revogado nesta empresa';
    end if;
    perform 1 from public.empresa_assinaturas where empresa_id=p_empresa for update;
    perform private.assert_tenant_workspace_write_allowed(p_empresa);
  end if;
end $$;

create function private.admin_has_other(p_empresa uuid,p_usuario uuid,p_owner boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.usuario_empresas ue
    join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
    where ue.empresa_id=p_empresa and ue.usuario_id<>p_usuario and ue.status='ativo'
      and case when p_owner then ue.is_owner else
        array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar']
          <@ private.admin_permissions(p_empresa,ue.usuario_id) end)
$$;

create function private.admin_audit(p_empresa uuid,p_unidade uuid,p_entidade text,p_id uuid,
  p_acao text,p_antes jsonb,p_depois jsonb,p_justificativa text)
returns void language plpgsql security invoker set search_path='' as $$
begin
  if length(btrim(coalesce(p_justificativa,'')))<5 then
    raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,
    acao,antes,depois,justificativa,contexto)
  values(p_empresa,p_unidade,private.request_jwt_subject(),p_entidade,p_id,p_acao,p_antes,p_depois,
    btrim(p_justificativa),jsonb_build_object('origem','tenant_admin_rpc',
      'membership_ator_id',(select id from public.usuario_empresas
        where usuario_id=private.request_jwt_subject() and empresa_id=p_empresa)));
end $$;

revoke all on function private.admin_permissions(uuid,uuid),private.admin_scope_id(),
  private.admin_assert(uuid,text,boolean),private.admin_has_other(uuid,uuid,boolean),
  private.admin_audit(uuid,uuid,text,uuid,text,jsonb,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function private.admin_permissions(uuid,uuid),private.admin_scope_id(),
  private.admin_assert(uuid,text,boolean),private.admin_has_other(uuid,uuid,boolean),
  private.admin_audit(uuid,uuid,text,uuid,text,jsonb,jsonb,text),private.request_jwt_subject() to bpf_tenant_admin;

-- This role has no write privilege on global identities or legacy profile links.
grant select on public.usuarios,public.empresas,public.unidades,public.setores,public.perfis,
  public.permissoes,public.perfil_permissoes,public.usuario_empresas,public.usuario_empresa_perfis,
  public.auditoria_eventos to bpf_tenant_admin;
grant update(razao_social,nome_fantasia,cnpj,updated_at) on public.empresas to bpf_tenant_admin;
grant insert(empresa_id,nome,codigo,ativo,created_by),update(nome,codigo,ativo,updated_at) on public.unidades to bpf_tenant_admin;
grant insert(unidade_id,nome,codigo,ativo,created_by),update(unidade_id,nome,codigo,ativo,updated_at) on public.setores to bpf_tenant_admin;
grant insert(empresa_id,nome,descricao,is_system,ativo,created_by),update(nome,descricao,ativo,updated_at) on public.perfis to bpf_tenant_admin;
grant insert(perfil_id,permissao_id,created_by),delete on public.perfil_permissoes to bpf_tenant_admin;
grant update(status,unidade_id,updated_at) on public.usuario_empresas to bpf_tenant_admin;
grant insert(usuario_empresa_id,perfil_id,created_by),delete on public.usuario_empresa_perfis to bpf_tenant_admin;
grant insert(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  on public.auditoria_eventos to bpf_tenant_admin;

create policy tenant_admin_empresas on public.empresas for all to bpf_tenant_admin
  using(id=private.admin_scope_id()) with check(id=private.admin_scope_id());
create policy tenant_admin_unidades on public.unidades for all to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id()) with check(empresa_id=private.admin_scope_id());
create policy tenant_admin_setores on public.setores for all to bpf_tenant_admin
  using(exists(select 1 from public.unidades un where un.id=setores.unidade_id and un.empresa_id=private.admin_scope_id()))
  with check(exists(select 1 from public.unidades un where un.id=setores.unidade_id and un.empresa_id=private.admin_scope_id()));
create policy tenant_admin_perfis_read on public.perfis for select to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id() or (empresa_id is null and is_system));
create policy tenant_admin_perfis_insert on public.perfis for insert to bpf_tenant_admin
  with check(empresa_id=private.admin_scope_id() and not is_system);
create policy tenant_admin_perfis_update on public.perfis for update to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id() and not is_system)
  with check(empresa_id=private.admin_scope_id() and not is_system);
create policy tenant_admin_permissions on public.permissoes for select to bpf_tenant_admin using(true);
create policy tenant_admin_profile_permissions_read on public.perfil_permissoes for select to bpf_tenant_admin
  using(exists(select 1 from public.perfis p where p.id=perfil_id));
create policy tenant_admin_profile_permissions_insert on public.perfil_permissoes for insert to bpf_tenant_admin
  with check(exists(select 1 from public.perfis p where p.id=perfil_id and p.empresa_id=private.admin_scope_id() and not p.is_system));
create policy tenant_admin_profile_permissions_delete on public.perfil_permissoes for delete to bpf_tenant_admin
  using(exists(select 1 from public.perfis p where p.id=perfil_id and p.empresa_id=private.admin_scope_id() and not p.is_system));
create policy tenant_admin_memberships on public.usuario_empresas for all to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id()) with check(empresa_id=private.admin_scope_id());
create policy tenant_admin_users_read on public.usuarios for select to bpf_tenant_admin
  using(exists(select 1 from public.usuario_empresas ue where ue.usuario_id=usuarios.id and ue.empresa_id=private.admin_scope_id()));
create policy tenant_admin_membership_profiles on public.usuario_empresa_perfis for all to bpf_tenant_admin
  using(exists(select 1 from public.usuario_empresas ue where ue.id=usuario_empresa_id and ue.empresa_id=private.admin_scope_id()))
  with check(exists(select 1 from public.usuario_empresas ue where ue.id=usuario_empresa_id and ue.empresa_id=private.admin_scope_id())
    and exists(select 1 from public.perfis p where p.id=perfil_id and ((p.empresa_id is null and p.is_system) or p.empresa_id=private.admin_scope_id())));
create policy tenant_admin_audit_read on public.auditoria_eventos for select to bpf_tenant_admin
  using(empresa_id=private.admin_scope_id());
create policy tenant_admin_audit_insert on public.auditoria_eventos for insert to bpf_tenant_admin
  with check(empresa_id=private.admin_scope_id() and ator_id=private.request_jwt_subject());

create function private.admin_contexto_ler(p_empresa_id uuid,p_recurso text,p_offset integer default 0,p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_permission text; v_result jsonb;
begin
  v_permission:=case p_recurso
    when 'usuarios' then 'usuarios.gerenciar' when 'usuario_perfis' then 'usuarios.gerenciar'
    when 'perfis' then 'configuracoes.visualizar' when 'permissoes' then 'perfis.gerenciar'
    when 'perfil_permissoes' then 'perfis.gerenciar' when 'empresas' then 'configuracoes.visualizar'
    when 'unidades' then 'configuracoes.visualizar' when 'setores' then 'estrutura.gerenciar'
    when 'auditoria_eventos' then 'auditoria.visualizar' when 'atores_auditoria' then 'auditoria.visualizar' end;
  if v_permission is null or p_offset is null or p_offset<0 or p_limit is null or p_limit<1 or p_limit>500 then
    raise exception using errcode='22023',message='Consulta administrativa invalida';
  end if;
  perform private.admin_assert(p_empresa_id,v_permission,false);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  with registros as materialized (
    select u.id::text as chave,jsonb_build_object('id',u.id,'membership_id',ue.id,'nome',u.nome,'email',u.email,
      'empresa_id',ue.empresa_id,'unidade_id',ue.unidade_id,'status',ue.status,'ativo',ue.status='ativo',
      'identidade_ativa',u.ativo,'identidade_status',u.status,'created_at',ue.created_at) as registro
      from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id where p_recurso='usuarios' and ue.empresa_id=p_empresa_id
    union all select e.id::text,jsonb_build_object('id',e.id,'nome_fantasia',e.nome_fantasia,'razao_social',e.razao_social,'cnpj',e.cnpj,'ativo',e.ativo)
      from public.empresas e where p_recurso='empresas' and e.id=p_empresa_id
    union all select un.id::text,jsonb_build_object('id',un.id,'empresa_id',un.empresa_id,'nome',un.nome,'codigo',un.codigo,'ativo',un.ativo)
      from public.unidades un where p_recurso='unidades' and un.empresa_id=p_empresa_id
    union all select s.id::text,jsonb_build_object('id',s.id,'unidade_id',s.unidade_id,'nome',s.nome,'codigo',s.codigo,'ativo',s.ativo)
      from public.setores s join public.unidades un on un.id=s.unidade_id where p_recurso='setores' and un.empresa_id=p_empresa_id
    union all select p.id::text,jsonb_build_object('id',p.id,'empresa_id',p.empresa_id,'nome',p.nome,'descricao',p.descricao,'is_system',p.is_system,'ativo',p.ativo)
      from public.perfis p where p_recurso='perfis' and (p.empresa_id=p_empresa_id or (p.empresa_id is null and p.is_system))
    union all select pm.id::text,jsonb_build_object('id',pm.id,'codigo',pm.codigo,'modulo',pm.modulo,'acao',pm.acao,'descricao',pm.descricao)
      from public.permissoes pm where p_recurso='permissoes'
    union all select ue.usuario_id::text||up.perfil_id::text,jsonb_build_object('usuario_id',ue.usuario_id,'perfil_id',up.perfil_id)
      from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id
      where p_recurso='usuario_perfis' and ue.empresa_id=p_empresa_id
    union all select p.id::text||pp.permissao_id::text,jsonb_build_object('perfil_id',p.id,'permissao_id',pp.permissao_id)
      from public.perfil_permissoes pp join public.perfis p on p.id=pp.perfil_id
      where p_recurso='perfil_permissoes' and (p.empresa_id=p_empresa_id or (p.empresa_id is null and p.is_system))
    union all select ae.created_at::text||ae.id::text,jsonb_build_object('id',ae.id,'empresa_id',ae.empresa_id,'unidade_id',ae.unidade_id,'ator_id',ae.ator_id,
      'entidade',ae.entidade,'registro_id',ae.registro_id,'acao',ae.acao,'antes',ae.antes,'depois',ae.depois,'justificativa',ae.justificativa,'contexto',ae.contexto,'created_at',ae.created_at)
      from public.auditoria_eventos ae where p_recurso='auditoria_eventos' and ae.empresa_id=p_empresa_id
    union all select u.id::text,jsonb_build_object('id',u.id,'nome',u.nome,'email',u.email)
      from public.usuarios u where p_recurso='atores_auditoria'
      and exists(select 1 from public.auditoria_eventos ae where ae.empresa_id=p_empresa_id and ae.ator_id=u.id)
  ), pagina as(select registro from registros order by chave limit p_limit offset p_offset)
  select jsonb_build_object('data',coalesce((select jsonb_agg(registro) from pagina),'[]'::jsonb),
    'count',(select count(*) from registros)) into v_result;
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_result;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_status_tenant(p_empresa_id uuid,p_usuario_id uuid,p_status text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.usuario_empresas%rowtype; v_admin boolean;
begin
  perform private.admin_assert(p_empresa_id,'usuarios.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  select * into v_old from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  if v_old.status='pendente' or p_status is null or p_status not in('ativo','inativo','bloqueado') then
    raise exception using errcode='22023',message='Status administrativo invalido'; end if;
  if p_usuario_id=private.request_jwt_subject() and p_status<>'ativo' then
    raise exception using errcode='42501',message='Nao e permitido inativar ou bloquear o proprio usuario'; end if;
  if v_old.status=p_status then raise exception using errcode='22023',message='Nenhuma alteracao de status identificada'; end if;
  v_admin:=array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id);
  if p_status<>'ativo' and ((v_admin and not private.admin_has_other(p_empresa_id,p_usuario_id,false))
      or (v_old.is_owner and not private.admin_has_other(p_empresa_id,p_usuario_id,true))) then
    raise exception using errcode='42501',message='Operacao removeria o ultimo administrador ou owner efetivo da empresa'; end if;
  update public.usuario_empresas set status=p_status,updated_at=now() where id=v_old.id;
  perform private.admin_audit(p_empresa_id,v_old.unidade_id,'usuario',p_usuario_id,'usuario.status_alterado',
    to_jsonb(v_old),to_jsonb(v_old)||jsonb_build_object('status',p_status),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_unidade_tenant(p_empresa_id uuid,p_usuario_id uuid,p_unidade_id uuid,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.usuario_empresas%rowtype;
begin
  perform private.admin_assert(p_empresa_id,'usuarios.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  select * into v_old from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  if v_old.status='pendente' then raise exception using errcode='42501',message='Usuario pendente exige fluxo de vinculacao/aprovacao dedicado'; end if;
  if p_unidade_id is not null and not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id and ativo) then
    raise exception using errcode='42501',message='Unidade invalida, inativa ou fora da empresa'; end if;
  if v_old.unidade_id is not distinct from p_unidade_id then raise exception using errcode='22023',message='Nenhuma alteracao de unidade identificada'; end if;
  update public.usuario_empresas set unidade_id=p_unidade_id,updated_at=now() where id=v_old.id;
  perform private.admin_audit(p_empresa_id,p_unidade_id,'usuario',p_usuario_id,'usuario.unidade_alterada',
    to_jsonb(v_old),to_jsonb(v_old)||jsonb_build_object('unidade_id',p_unidade_id),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_usuario_perfil_tenant(p_empresa_id uuid,p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_member public.usuario_empresas%rowtype; v_profile public.perfis%rowtype; v_admin boolean; v_exists boolean;
begin
  perform private.admin_assert(p_empresa_id,'perfis.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if p_usuario_id=private.request_jwt_subject() then raise exception using errcode='42501',message='Nao e permitido alterar o proprio perfil administrativo'; end if;
  if p_acao is null or p_acao not in('atribuir','remover') then raise exception using errcode='22023',message='Acao de perfil invalida'; end if;
  select * into v_member from public.usuario_empresas where usuario_id=p_usuario_id and empresa_id=p_empresa_id for update;
  if not found or v_member.status='pendente' then raise exception using errcode='42501',message='Usuario fora do escopo autorizado'; end if;
  select * into v_profile from public.perfis where id=p_perfil_id and ((empresa_id is null and is_system) or empresa_id=p_empresa_id);
  if not found or (p_acao='atribuir' and not v_profile.ativo) then raise exception using errcode='42501',message='Perfil fora do escopo autorizado'; end if;
  if p_acao='atribuir' and exists(select 1 from public.perfil_permissoes pp join public.permissoes pm on pm.id=pp.permissao_id
    where pp.perfil_id=p_perfil_id and not pm.codigo=any(private.admin_permissions(p_empresa_id,private.request_jwt_subject()))) then
    raise exception using errcode='42501',message='Nao e permitido delegar um perfil com permissoes superiores as do ator'; end if;
  select exists(select 1 from public.usuario_empresa_perfis where usuario_empresa_id=v_member.id and perfil_id=p_perfil_id) into v_exists;
  if v_exists=(p_acao='atribuir') then raise exception using errcode='22023',message='Atribuicao de perfil sem alteracao'; end if;
  v_admin:=array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id);
  if p_acao='atribuir' then
    insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by) values(v_member.id,p_perfil_id,private.request_jwt_subject());
  else
    delete from public.usuario_empresa_perfis where usuario_empresa_id=v_member.id and perfil_id=p_perfil_id;
  end if;
  if v_admin and not array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id)
    and not private.admin_has_other(p_empresa_id,p_usuario_id,false) then
    raise exception using errcode='42501',message='Operacao removeria o ultimo administrador efetivo da empresa'; end if;
  perform private.admin_audit(p_empresa_id,v_member.unidade_id,'usuario',p_usuario_id,
    case when p_acao='atribuir' then 'usuario.perfil_atribuido' else 'usuario.perfil_removido' end,
    jsonb_build_object('membership_id',v_member.id,'perfil_id',p_perfil_id,'atribuido',v_exists),
    jsonb_build_object('membership_id',v_member.id,'perfil_id',p_perfil_id,'atribuido',not v_exists),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_empresa_tenant(p_empresa_id uuid,p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.empresas%rowtype;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_razao_social,'')))<2 then raise exception using errcode='22023',message='Razao social invalida'; end if;
  select * into v_old from public.empresas where id=p_empresa_id for update;
  update public.empresas set razao_social=btrim(p_razao_social),nome_fantasia=nullif(btrim(p_nome_fantasia),''),cnpj=nullif(btrim(p_cnpj),''),updated_at=now() where id=p_empresa_id;
  perform private.admin_audit(p_empresa_id,null,'empresa',p_empresa_id,'empresa.atualizada',
    jsonb_build_object('razao_social',v_old.razao_social,'nome_fantasia',v_old.nome_fantasia,'cnpj',v_old.cnpj),
    jsonb_build_object('razao_social',btrim(p_razao_social),'nome_fantasia',nullif(btrim(p_nome_fantasia),''),'cnpj',nullif(btrim(p_cnpj),'')),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_unidade_tenant(p_empresa_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.unidades%rowtype; v_id uuid;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome da unidade invalido'; end if;
  if p_unidade_id is null then
    insert into public.unidades(empresa_id,nome,codigo,ativo,created_by)
      values(p_empresa_id,btrim(p_nome),nullif(btrim(p_codigo),''),coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select * into v_old from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id for update;
    if not found then raise exception using errcode='42501',message='Unidade fora do escopo autorizado'; end if;
    if not coalesce(p_ativo,true) and exists(select 1 from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id
      where ue.unidade_id=p_unidade_id and ue.status='ativo' and u.ativo and u.status='ativo') then
      raise exception using errcode='23514',message='Unidade possui usuarios ativos vinculados'; end if;
    v_id:=p_unidade_id;
    update public.unidades set nome=btrim(p_nome),codigo=nullif(btrim(p_codigo),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
  end if;
  perform private.admin_audit(p_empresa_id,v_id,'unidade',v_id,case when p_unidade_id is null then 'unidade.criada' else 'unidade.atualizada' end,
    case when p_unidade_id is null then null else to_jsonb(v_old) end,jsonb_build_object('nome',btrim(p_nome),'codigo',nullif(btrim(p_codigo),''),'ativo',coalesce(p_ativo,true)),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_setor_tenant(p_empresa_id uuid,p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.setores%rowtype; v_id uuid;
begin
  perform private.admin_assert(p_empresa_id,'estrutura.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=p_empresa_id and ativo) then
    raise exception using errcode='42501',message='Unidade fora do escopo autorizado'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do setor invalido'; end if;
  if p_setor_id is null then
    insert into public.setores(unidade_id,nome,codigo,ativo,created_by)
      values(p_unidade_id,btrim(p_nome),nullif(btrim(p_codigo),''),coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select s.* into v_old from public.setores s join public.unidades un on un.id=s.unidade_id
      where s.id=p_setor_id and un.empresa_id=p_empresa_id for update of s;
    if not found then raise exception using errcode='42501',message='Setor fora do escopo autorizado'; end if;
    v_id:=p_setor_id;
    update public.setores set unidade_id=p_unidade_id,nome=btrim(p_nome),codigo=nullif(btrim(p_codigo),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
  end if;
  perform private.admin_audit(p_empresa_id,p_unidade_id,'setor',v_id,case when p_setor_id is null then 'setor.criado' else 'setor.atualizado' end,
    case when p_setor_id is null then null else to_jsonb(v_old) end,jsonb_build_object('unidade_id',p_unidade_id,'nome',btrim(p_nome),'codigo',nullif(btrim(p_codigo),''),'ativo',coalesce(p_ativo,true)),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

create function private.admin_perfil_tenant(p_empresa_id uuid,p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_previous_scope text:=current_setting('bpf.admin_empresa',true); v_old public.perfis%rowtype; v_id uuid; v_perm uuid; v_old_permissions uuid[];
begin
  perform private.admin_assert(p_empresa_id,'perfis.gerenciar',true);
  perform set_config('bpf.admin_empresa',p_empresa_id::text,true);
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do perfil invalido'; end if;
  foreach v_perm in array coalesce(p_permissao_ids,'{}'::uuid[]) loop
    if not exists(select 1 from public.permissoes pm where pm.id=v_perm and pm.codigo=any(private.admin_permissions(p_empresa_id,private.request_jwt_subject()))) then
      raise exception using errcode='42501',message='Nao e permitido conceder uma permissao que o ator nao possui'; end if;
  end loop;
  if p_perfil_id is null then
    insert into public.perfis(empresa_id,nome,descricao,is_system,ativo,created_by)
      values(p_empresa_id,btrim(p_nome),nullif(btrim(p_descricao),''),false,coalesce(p_ativo,true),private.request_jwt_subject()) returning id into v_id;
  else
    select * into v_old from public.perfis where id=p_perfil_id and empresa_id=p_empresa_id and not is_system for update;
    if not found then raise exception using errcode='42501',message='Perfil de sistema ou fora do escopo nao pode ser alterado'; end if;
    select coalesce(array_agg(permissao_id order by permissao_id),'{}'::uuid[]) into v_old_permissions from public.perfil_permissoes where perfil_id=p_perfil_id;
    if exists(select 1 from public.usuario_empresa_perfis up join public.usuario_empresas ue on ue.id=up.usuario_empresa_id
      join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
      where up.perfil_id=p_perfil_id and ue.status='ativo') and
      (not coalesce(p_ativo,true) or v_old_permissions is distinct from
        array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x)) then
      raise exception using errcode='23514',message='Perfil em uso por usuarios ativos deve ser desvinculado antes de alterar permissoes'; end if;
    v_id:=p_perfil_id;
    update public.perfis set nome=btrim(p_nome),descricao=nullif(btrim(p_descricao),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
    if v_old_permissions is distinct from array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x) then
      delete from public.perfil_permissoes where perfil_id=v_id;
    end if;
  end if;
  if p_perfil_id is null or v_old_permissions is distinct from array(select distinct x from unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x order by x) then
    insert into public.perfil_permissoes(perfil_id,permissao_id,created_by)
      select v_id,x,private.request_jwt_subject() from (select distinct unnest(coalesce(p_permissao_ids,'{}'::uuid[])) x) a;
  end if;
  perform private.admin_audit(p_empresa_id,null,'perfil',v_id,case when p_perfil_id is null then 'perfil.criado' else 'perfil.atualizado' end,
    case when p_perfil_id is null then null else to_jsonb(v_old)||jsonb_build_object('permissao_ids',v_old_permissions) end,
    jsonb_build_object('nome',btrim(p_nome),'descricao',nullif(btrim(p_descricao),''),'ativo',coalesce(p_ativo,true),'permissao_ids',coalesce(p_permissao_ids,'{}'::uuid[])),p_justificativa);
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  return v_id;
exception when others then
  perform set_config('bpf.admin_empresa',coalesce(v_previous_scope,''),true);
  raise;
end $$;

-- Narrow owners/ACLs; authenticated cannot SET this role or call its private helpers.
do $acl$ declare r record; begin
  for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in('admin_contexto_ler','admin_usuario_status_tenant','admin_usuario_unidade_tenant',
      'admin_usuario_perfil_tenant','admin_empresa_tenant','admin_unidade_tenant','admin_setor_tenant','admin_perfil_tenant') loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',r.signature);
    execute format('grant execute on function %s to authenticated,bpf_admin_writer',r.signature);
    execute format('alter function %s owner to bpf_tenant_admin',r.signature);
  end loop;
end $acl$;
create function public.admin_contexto_ler(p_empresa_id uuid,p_recurso text,p_offset integer default 0,p_limit integer default 500) returns jsonb
language sql security invoker set search_path='' as $$ select private.admin_contexto_ler(p_empresa_id,p_recurso,p_offset,p_limit) $$;
revoke all on function public.admin_contexto_ler(uuid,text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_contexto_ler(uuid,text,integer,integer) to authenticated,bpf_admin_writer;
create function public.admin_usuario_status_tenant(p_empresa_id uuid,p_usuario_id uuid,p_status text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_status_tenant(p_empresa_id,p_usuario_id,p_status,p_justificativa) $$;
revoke all on function public.admin_usuario_status_tenant(uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_status_tenant(uuid,uuid,text,text) to authenticated,bpf_admin_writer;
create function public.admin_usuario_unidade_tenant(p_empresa_id uuid,p_usuario_id uuid,p_unidade_id uuid,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_unidade_tenant(p_empresa_id,p_usuario_id,p_unidade_id,p_justificativa) $$;
revoke all on function public.admin_usuario_unidade_tenant(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_unidade_tenant(uuid,uuid,uuid,text) to authenticated,bpf_admin_writer;
create function public.admin_usuario_perfil_tenant(p_empresa_id uuid,p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_usuario_perfil_tenant(p_empresa_id,p_usuario_id,p_perfil_id,p_acao,p_justificativa) $$;
revoke all on function public.admin_usuario_perfil_tenant(uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_usuario_perfil_tenant(uuid,uuid,uuid,text,text) to authenticated,bpf_admin_writer;
create function public.admin_empresa_tenant(p_empresa_id uuid,p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text) returns void
language sql security invoker set search_path='' as $$ select private.admin_empresa_tenant(p_empresa_id,p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa) $$;
revoke all on function public.admin_empresa_tenant(uuid,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_empresa_tenant(uuid,text,text,text,text) to authenticated,bpf_admin_writer;
create function public.admin_unidade_tenant(p_empresa_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_unidade_tenant(p_empresa_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $$;
revoke all on function public.admin_unidade_tenant(uuid,uuid,text,text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_unidade_tenant(uuid,uuid,text,text,boolean,text) to authenticated,bpf_admin_writer;
create function public.admin_setor_tenant(p_empresa_id uuid,p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_setor_tenant(p_empresa_id,p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $$;
revoke all on function public.admin_setor_tenant(uuid,uuid,uuid,text,text,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_setor_tenant(uuid,uuid,uuid,text,text,boolean,text) to authenticated,bpf_admin_writer;
create function public.admin_perfil_tenant(p_empresa_id uuid,p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text) returns uuid
language sql security invoker set search_path='' as $$ select private.admin_perfil_tenant(p_empresa_id,p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa) $$;
revoke all on function public.admin_perfil_tenant(uuid,uuid,text,text,boolean,uuid[],text) from public,anon,authenticated,service_role;
grant execute on function public.admin_perfil_tenant(uuid,uuid,text,text,boolean,uuid[],text) to authenticated,bpf_admin_writer;

revoke create on schema private from bpf_tenant_admin;
grant bpf_tenant_admin to postgres with inherit false,set false;


-- Compatibility uses the primary company only as routing; authorization is canonical.
create function private.admin_primary_empresa() returns uuid language sql stable security definer set search_path='' as $$
  select empresa_id from public.usuarios where id=private.request_jwt_subject() and ativo and status='ativo'
$$;
revoke all on function private.admin_primary_empresa() from public,anon,authenticated,service_role;
grant execute on function private.admin_primary_empresa(),private.admin_permissions(uuid,uuid),private.admin_has_other(uuid,uuid,boolean),private.request_jwt_subject() to bpf_admin_writer,bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false,set true;
grant create on schema private to bpf_authz_reader;
set role bpf_authz_reader;
create or replace function private.empresa_leitura_usuarios() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','usuarios.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_gestao_perfis() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','perfis.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_convite_usuarios() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_estrutura_admin() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','estrutura.gerenciar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
create or replace function private.empresa_leitura_auditoria() returns uuid language sql stable security definer set search_path='' as $$
  select private.admin_primary_empresa() where array['configuracoes.visualizar','auditoria.visualizar'] <@ private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())
$$;
reset role;
revoke create on schema private from bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false,set false;
grant bpf_admin_writer to postgres with inherit false,set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;
create or replace function private.ator_possui_permissao(p_permissao_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.permissoes where id=p_permissao_id
   and codigo=any(private.admin_permissions(private.admin_primary_empresa(),private.request_jwt_subject())))
$$;
create or replace function private.usuario_admin_efetivo(p_usuario_id uuid,p_empresa_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select array['configuracoes.visualizar','usuarios.gerenciar','perfis.gerenciar'] <@ private.admin_permissions(p_empresa_id,p_usuario_id)
$$;
create or replace function private.existe_outro_admin_efetivo(p_usuario_id uuid,p_empresa_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select private.admin_has_other(p_empresa_id,p_usuario_id,false)
$$;
create or replace function private.admin_usuario_alterar_status(p_usuario_id uuid,p_status text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_status_tenant(private.admin_primary_empresa(),p_usuario_id,p_status,p_justificativa)
$$;
create or replace function private.admin_usuario_alterar_unidade(p_usuario_id uuid,p_unidade_id uuid,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_unidade_tenant(private.admin_primary_empresa(),p_usuario_id,p_unidade_id,p_justificativa)
$$;
create or replace function private.admin_usuario_alterar_perfil(p_usuario_id uuid,p_perfil_id uuid,p_acao text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_usuario_perfil_tenant(private.admin_primary_empresa(),p_usuario_id,p_perfil_id,p_acao,p_justificativa)
$$;
create or replace function private.admin_empresa_atualizar(p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_empresa_tenant(private.admin_primary_empresa(),p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa)
$$;
create or replace function private.admin_unidade_salvar(p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_unidade_tenant(private.admin_primary_empresa(),p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa)
$$;
create or replace function private.admin_setor_salvar(p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_setor_tenant(private.admin_primary_empresa(),p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa)
$$;
create or replace function private.admin_perfil_criar(p_nome text,p_descricao text,p_permissao_ids uuid[],p_justificativa text) returns uuid
language sql security definer set search_path='' as $$
 select public.admin_perfil_tenant(private.admin_primary_empresa(),null,p_nome,p_descricao,true,p_permissao_ids,p_justificativa)
$$;
create or replace function private.admin_perfil_atualizar(p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text) returns void
language sql security definer set search_path='' as $$
 select public.admin_perfil_tenant(private.admin_primary_empresa(),p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa)
$$;
reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false,set false;
-- Old invitation path is retired; the tenant-aware server invitation remains unchanged.
revoke execute on function public.admin_usuario_vincular_convite(uuid,uuid,uuid[],text),
 private.admin_usuario_vincular_convite(uuid,uuid,uuid[],text) from authenticated;

create or replace view public.v_meu_contexto with(security_invoker=true) as
select c.usuario_id,c.nome,c.email,c.ativo,c.status,c.empresa_id,c.nome_fantasia,c.razao_social,
 c.unidade_id,c.unidade_nome,c.perfis,c.permissoes
from public.usuarios u cross join lateral public.meu_contexto_empresa(u.empresa_id) c
where u.id=private.request_jwt_subject();


grant bpf_plan_enforcer to postgres with inherit false,set true;
grant create on schema private to bpf_plan_enforcer;
set role bpf_plan_enforcer;
create or replace function private.consumo_plano_empresa(p_empresa_id uuid)
returns table(usuarios_ativos bigint,unidades_ativas bigint)
language sql stable security definer set search_path='' as $$
 select (select count(*) from (
   select ue.usuario_id from public.usuario_empresas ue join public.usuarios u on u.id=ue.usuario_id
     where ue.empresa_id=p_empresa_id and ue.status='ativo' and u.ativo and u.status='ativo'
   union
   select u.id from public.usuarios u where u.empresa_id=p_empresa_id and u.ativo and u.status='ativo'
     and not exists(select 1 from public.usuario_empresas ue where ue.usuario_id=u.id and ue.empresa_id=p_empresa_id)
 ) ativos), (select count(*) from public.unidades where empresa_id=p_empresa_id and ativo)
$$;
create or replace function private.validar_limite_usuario_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.empresa_id is null or not new.ativo or new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.ativo
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and not exists(select 1 from public.usuario_empresas canonical where canonical.usuario_id=u.id and canonical.empresa_id=new.empresa_id)
      and u.id <> new.id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    join public.usuarios identity_user on identity_user.id=ue.usuario_id and identity_user.ativo and identity_user.status='ativo'
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;
create or replace function private.validar_limite_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limite bigint;
  v_consumo bigint;
begin
  if new.status <> 'ativo' then return new; end if;
  if tg_op = 'UPDATE'
     and old.empresa_id is not distinct from new.empresa_id
     and old.usuario_id = new.usuario_id
     and old.status = 'ativo' then
    return new;
  end if;

  v_limite := private.limite_inteiro_empresa(new.empresa_id, 'usuarios_ativos.max');
  if v_limite is null then return new; end if;

  select count(*) into v_consumo
  from (
    select u.id as usuario_id
    from public.usuarios u
    where u.empresa_id = new.empresa_id
      and u.ativo and u.status = 'ativo'
      and not exists(select 1 from public.usuario_empresas canonical where canonical.usuario_id=u.id and canonical.empresa_id=new.empresa_id)
      and u.id <> new.usuario_id
    union
    select ue.usuario_id
    from public.usuario_empresas ue
    join public.usuarios identity_user on identity_user.id=ue.usuario_id and identity_user.ativo and identity_user.status='ativo'
    where ue.empresa_id = new.empresa_id
      and ue.status = 'ativo'
      and ue.usuario_id <> new.usuario_id
  ) ativos;

  if v_consumo + 1 > v_limite then
    raise exception using
      errcode = '23514',
      message = 'Limite de usuarios ativos do plano atingido';
  end if;
  return new;
end
$function$;

grant execute on function private.consumo_plano_empresa(uuid) to postgres;
reset role;
revoke create on schema private from bpf_plan_enforcer;
grant bpf_plan_enforcer to postgres with inherit false,set false;


-- Direct legacy reads also lose tenant visibility after canonical revocation.
create function private.primary_visible_empresa() returns uuid language sql stable security definer set search_path='' as $$
 select u.empresa_id from public.usuarios u
 join public.usuario_empresas ue on ue.usuario_id=u.id and ue.empresa_id=u.empresa_id and ue.status='ativo'
 join public.empresas e on e.id=ue.empresa_id and e.ativo
 where u.id=private.request_jwt_subject() and u.ativo and u.status='ativo'
$$;
revoke all on function private.primary_visible_empresa() from public,anon,authenticated,service_role;
grant execute on function private.primary_visible_empresa() to authenticated;
alter policy empresas_select_empresa on public.empresas using(id=private.primary_visible_empresa());
alter policy unidades_select_empresa on public.unidades using(empresa_id=private.primary_visible_empresa());
alter policy setores_select_empresa on public.setores using(exists(select 1 from public.unidades un
 where un.id=setores.unidade_id and un.empresa_id=private.primary_visible_empresa()));
alter policy perfis_select_empresa on public.perfis using((empresa_id is null and is_system) or empresa_id=private.primary_visible_empresa());


-- The trusted invitation channel shares the same locks and commercial checks.
create function private.assert_invite_tenant_write(p_ator uuid,p_empresa uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_subscription public.empresa_assinaturas%rowtype;
begin
 if not array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(p_empresa,p_ator) then
   raise exception using errcode='42501',message='Convite nao autorizado neste tenant'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_empresa::text,0));
 select * into v_subscription from public.empresa_assinaturas where empresa_id=p_empresa for update;
 if not array['configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar'] <@ private.admin_permissions(p_empresa,p_ator) then
   raise exception using errcode='42501',message='Acesso de convite revogado neste tenant'; end if;
 if v_subscription.id is not null and not (v_subscription.status='active' or
   (v_subscription.status='trialing' and v_subscription.trial_fim>now())) then
   raise exception using errcode='42501',message='Workspace em modo somente leitura'; end if;
end $$;
revoke all on function private.assert_invite_tenant_write(uuid,uuid) from public,anon,authenticated,service_role;
grant usage on schema private to service_role;
grant execute on function private.assert_invite_tenant_write(uuid,uuid) to service_role;

create or replace function public.admin_usuario_vincular_convite_server(
  p_ator_id uuid,
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  if p_ator_id is null or p_empresa_id is null or p_usuario_id is null then
    raise exception using errcode='22023', message='Parametros obrigatorios ausentes';
  end if;
  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  perform private.assert_invite_tenant_write(p_ator_id,p_empresa_id);

  -- O ator precisa permanecer ativo globalmente e no tenant informado.
  if not exists (
    select 1
    from public.usuarios u
    join public.usuario_empresas ue
      on ue.usuario_id=u.id
     and ue.empresa_id=p_empresa_id
     and ue.status='ativo'
    where u.id=p_ator_id and u.ativo and u.status='ativo'
  ) then
    raise exception using errcode='42501', message='Ator sem membership ativo no tenant selecionado';
  end if;

  select coalesce(array_agg(distinct pm.codigo), array[]::text[])
    into v_permissoes
  from public.usuario_empresas ue
  join public.usuario_empresa_perfis uep on uep.usuario_empresa_id=ue.id
  join public.perfis p on p.id=uep.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id=p.id
  join public.permissoes pm on pm.id=pp.permissao_id
  where ue.usuario_id=p_ator_id
    and ue.empresa_id=p_empresa_id
    and ue.status='ativo';

  if not ('configuracoes.visualizar'=any(v_permissoes))
     or not ('usuarios.gerenciar'=any(v_permissoes))
     or not ('usuarios.convidar'=any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  -- Lock already acquired before authorization and commercial checks above.

  if p_unidade_id is not null and not exists (
    select 1 from public.unidades
    where id=p_unidade_id and empresa_id=p_empresa_id and ativo
  ) then
    raise exception using errcode='22023', message='Unidade invalida, inativa ou fora da empresa';
  end if;

  foreach v_perfil_id in array p_perfil_ids loop
    if not exists (
      select 1 from public.perfis p
      where p.id=v_perfil_id and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id=p_empresa_id)
    ) then
      raise exception using errcode='22023', message='Perfil invalido, inativo ou fora da empresa';
    end if;

    if exists (
      select 1
      from public.perfil_permissoes pp
      join public.permissoes pm on pm.id=pp.permissao_id
      where pp.perfil_id=v_perfil_id
        and not (pm.codigo=any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  perform 1
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  update public.usuarios
  set empresa_id=p_empresa_id,
      unidade_id=p_unidade_id,
      status='ativo',
      ativo=true,
      updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id,perfil_id,created_by)
  select p_usuario_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_id,perfil_id) do nothing;

  insert into public.usuario_empresas(usuario_id,empresa_id,unidade_id,status,is_owner,created_by)
  values(p_usuario_id,p_empresa_id,p_unidade_id,'ativo',false,p_ator_id)
  on conflict (usuario_id,empresa_id) do update
    set unidade_id=excluded.unidade_id,
        status='ativo',
        updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id,created_by)
  select v_membership_id,x,p_ator_id from unnest(p_perfil_ids) x
  on conflict (usuario_empresa_id,perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,
    antes,depois,justificativa,contexto
  ) values (
    p_empresa_id,p_unidade_id,p_ator_id,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object(
      'empresa_id',p_empresa_id,
      'unidade_id',p_unidade_id,
      'status','ativo',
      'perfil_ids',p_perfil_ids,
      'membership_id',v_membership_id
    ),
    btrim(p_justificativa),
    jsonb_build_object('origem','edge_function','modelo','membership','executor','service_role')
  );
end
$function$;

-- Keep the trusted billing/checkout counters identical to the canonical summary.
-- Fixed function names and a checked replacement of the immutable pre-32 body.
do $billing$
declare r record; v_source text; v_definition text;
begin
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in('processar_evento_assinatura_server','preparar_contratacao_server'))<>2 then
   raise exception using errcode='55000',message='Contratos comerciais anteriores ausentes ou ambiguos';
 end if;
 for r in select p.oid,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in('processar_evento_assinatura_server','preparar_contratacao_server') loop
   v_source:=regexp_replace(r.prosrc,
     'select count\(\*\) into v_consumo_usuarios\s+from \(.*?\) ativos;',
     'select c.usuarios_ativos into v_consumo_usuarios from private.consumo_plano_empresa(p_empresa_id) c;', 'is');
   if v_source=r.prosrc then raise exception using errcode='55000',message='Contrato comercial anterior diverge da revisao'; end if;
   v_definition:=replace(pg_get_functiondef(r.oid),r.prosrc,v_source);
   execute v_definition;
 end loop;
end $billing$;

reset lock_timeout;
reset statement_timeout;
