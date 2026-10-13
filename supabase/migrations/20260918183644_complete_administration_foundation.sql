-- Complete administration foundation: invitations, company structure, custom profiles and audit read.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Granular permissions for the administration milestone.
insert into public.permissoes(codigo, modulo, acao, descricao)
values
  ('usuarios.convidar', 'usuarios', 'convidar', 'Convidar e vincular novos usuários à própria empresa'),
  ('estrutura.gerenciar', 'estrutura', 'gerenciar', 'Gerenciar empresa, unidades e setores da própria empresa'),
  ('auditoria.visualizar', 'auditoria', 'visualizar', 'Consultar a trilha de auditoria da própria empresa')
on conflict (codigo) do nothing;

-- Preserve backwards compatibility: profiles that already manage general settings receive
-- the new administration permissions. This avoids hard-coding the profile name Administrador.
insert into public.perfil_permissoes(perfil_id, permissao_id, created_by)
select distinct p.id, nova.id, p.created_by
from public.perfis p
join public.perfil_permissoes pp_base on pp_base.perfil_id = p.id
join public.permissoes base on base.id = pp_base.permissao_id and base.codigo = 'configuracoes.gerenciar'
cross join public.permissoes nova
where nova.codigo in ('usuarios.convidar', 'estrutura.gerenciar', 'auditoria.visualizar')
on conflict (perfil_id, permissao_id) do nothing;

-- Authorization-reader permission visibility is intentionally restricted to fixed codes.
alter policy permissoes_authz_reader_codigos on public.permissoes
  using (codigo in (
    'configuracoes.visualizar', 'configuracoes.gerenciar',
    'usuarios.gerenciar', 'usuarios.convidar',
    'perfis.gerenciar', 'estrutura.gerenciar', 'auditoria.visualizar'
  ));

grant bpf_authz_reader to postgres with inherit false, set true;
grant create on schema private to bpf_authz_reader;
set role bpf_authz_reader;

create function private.empresa_convite_usuarios()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo and u.status = 'ativo' and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'usuarios.gerenciar')
     and bool_or(pm.codigo = 'usuarios.convidar')
$function$;

create function private.empresa_estrutura_admin()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo and u.status = 'ativo' and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'estrutura.gerenciar')
$function$;

create function private.empresa_leitura_auditoria()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo and u.status = 'ativo' and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'auditoria.visualizar')
$function$;

reset role;
revoke create on schema private from bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false, set false;
revoke all on function private.empresa_convite_usuarios() from public, anon, authenticated, service_role;
revoke all on function private.empresa_estrutura_admin() from public, anon, authenticated, service_role;
revoke all on function private.empresa_leitura_auditoria() from public, anon, authenticated, service_role;

-- Writer receives only the table/column privileges used by the new private commands.
grant select, update (razao_social, nome_fantasia, cnpj, updated_at) on public.empresas to bpf_admin_writer;
grant insert (empresa_id, nome, codigo, ativo, created_by), update (nome, codigo, ativo, updated_at) on public.unidades to bpf_admin_writer;
grant select (id, unidade_id, nome, codigo, ativo, created_at, updated_at, created_by),
      insert (unidade_id, nome, codigo, ativo, created_by), update (nome, codigo, ativo, updated_at)
  on public.setores to bpf_admin_writer;
grant insert (empresa_id, nome, descricao, is_system, ativo, created_by), update (nome, descricao, ativo, updated_at)
  on public.perfis to bpf_admin_writer;
grant insert (perfil_id, permissao_id, created_by), delete on public.perfil_permissoes to bpf_admin_writer;

grant bpf_authz_reader to postgres with inherit false, set true;
set role bpf_authz_reader;
grant execute on function private.empresa_convite_usuarios() to bpf_admin_writer;
grant execute on function private.empresa_estrutura_admin() to bpf_admin_writer;
reset role;
grant bpf_authz_reader to postgres with inherit false, set false;

-- RLS for restricted writer. Public clients still have no direct write grants.
create policy empresas_admin_writer_select on public.empresas
  for select to bpf_admin_writer
  using (id = (select private.empresa_estrutura_admin()));
create policy empresas_admin_writer_update on public.empresas
  for update to bpf_admin_writer
  using (id = (select private.empresa_estrutura_admin()))
  with check (id = (select private.empresa_estrutura_admin()));

create policy unidades_admin_writer_insert on public.unidades
  for insert to bpf_admin_writer
  with check (empresa_id = (select private.empresa_estrutura_admin()));
create policy unidades_admin_writer_update on public.unidades
  for update to bpf_admin_writer
  using (empresa_id = (select private.empresa_estrutura_admin()))
  with check (empresa_id = (select private.empresa_estrutura_admin()));

create policy setores_admin_writer_select on public.setores
  for select to bpf_admin_writer
  using (exists (
    select 1 from public.unidades un
    where un.id = setores.unidade_id and un.empresa_id = (select private.empresa_estrutura_admin())
  ));
create policy setores_admin_writer_insert on public.setores
  for insert to bpf_admin_writer
  with check (exists (
    select 1 from public.unidades un
    where un.id = setores.unidade_id and un.empresa_id = (select private.empresa_estrutura_admin())
  ));
create policy setores_admin_writer_update on public.setores
  for update to bpf_admin_writer
  using (exists (
    select 1 from public.unidades un
    where un.id = setores.unidade_id and un.empresa_id = (select private.empresa_estrutura_admin())
  ))
  with check (exists (
    select 1 from public.unidades un
    where un.id = setores.unidade_id and un.empresa_id = (select private.empresa_estrutura_admin())
  ));

create policy perfis_admin_writer_insert on public.perfis
  for insert to bpf_admin_writer
  with check (empresa_id = (select private.empresa_gestao_perfis()) and not is_system);
create policy perfis_admin_writer_update on public.perfis
  for update to bpf_admin_writer
  using (empresa_id = (select private.empresa_gestao_perfis()) and not is_system)
  with check (empresa_id = (select private.empresa_gestao_perfis()) and not is_system);

create policy perfil_permissoes_admin_writer_insert on public.perfil_permissoes
  for insert to bpf_admin_writer
  with check (exists (
    select 1 from public.perfis p
    where p.id = perfil_permissoes.perfil_id
      and p.empresa_id = (select private.empresa_gestao_perfis()) and not p.is_system
  ));
create policy perfil_permissoes_admin_writer_delete on public.perfil_permissoes
  for delete to bpf_admin_writer
  using (exists (
    select 1 from public.perfis p
    where p.id = perfil_permissoes.perfil_id
      and p.empresa_id = (select private.empresa_gestao_perfis()) and not p.is_system
  ));

-- Narrow exception for a single just-invited, still-unlinked target. The custom GUC is only
-- meaningful to bpf_admin_writer; authenticated has no direct UPDATE grant and cannot SET ROLE.
create policy usuarios_admin_writer_pending_target_select on public.usuarios
  for select to bpf_admin_writer
  using (
    empresa_id is null and status = 'pendente'
    and id = nullif(current_setting('bpf.invite_target', true), '')::uuid
  );
create policy usuarios_admin_writer_pending_target_update on public.usuarios
  for update to bpf_admin_writer
  using (
    empresa_id is null and status = 'pendente'
    and id = nullif(current_setting('bpf.invite_target', true), '')::uuid
  )
  with check (empresa_id = (select private.empresa_convite_usuarios()) and status = 'ativo' and ativo);

-- Audit becomes readable only through same-company RLS and a dedicated permission.
grant select on public.auditoria_eventos to authenticated;
create policy auditoria_eventos_select_empresa on public.auditoria_eventos
  for select to authenticated
  using (empresa_id = (select private.empresa_leitura_auditoria()));
grant execute on function private.empresa_leitura_auditoria() to authenticated;

-- Create writer-owned commands.
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create function private.admin_usuario_vincular_convite(
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_empresa uuid;
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_perfil_id uuid;
begin
  v_empresa := private.empresa_convite_usuarios();
  if v_empresa is null then raise exception using errcode='42501', message='Sem permissao para convidar usuarios'; end if;
  if length(btrim(coalesce(p_justificativa,''))) < 5 then raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  if p_unidade_id is not null and not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=v_empresa and ativo) then
    raise exception using errcode='22023', message='Unidade invalida, inativa ou fora da empresa';
  end if;
  perform set_config('bpf.invite_target', p_usuario_id::text, true);
  select * into v_usuario from public.usuarios
   where id=p_usuario_id and empresa_id is null and status='pendente' for update;
  if not found then raise exception using errcode='P0002', message='Convite pendente nao encontrado'; end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then raise exception using errcode='22023', message='Selecione ao menos um perfil'; end if;
  foreach v_perfil_id in array p_perfil_ids loop
    if not exists(select 1 from public.perfis p where p.id=v_perfil_id and p.ativo and ((p.empresa_id is null and p.is_system) or p.empresa_id=v_empresa)) then
      raise exception using errcode='22023', message='Perfil invalido, inativo ou fora da empresa';
    end if;
  end loop;
  update public.usuarios set empresa_id=v_empresa, unidade_id=p_unidade_id, status='ativo', ativo=true, updated_at=now() where id=p_usuario_id;
  insert into public.usuario_perfis(usuario_id, perfil_id, created_by)
    select p_usuario_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_id, perfil_id) do nothing;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  values(v_empresa,p_unidade_id,v_ator,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object('empresa_id',v_empresa,'unidade_id',p_unidade_id,'status','ativo','perfil_ids',p_perfil_ids),
    btrim(p_justificativa),jsonb_build_object('origem','edge_function'));
end
$function$;

create function private.admin_empresa_atualizar(p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text)
returns void language plpgsql security definer set search_path='' as $function$
declare v_empresa uuid; v_ator uuid:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; v_old public.empresas%rowtype;
begin
  v_empresa:=private.empresa_estrutura_admin();
  if v_empresa is null then raise exception using errcode='42501',message='Sem permissao para gerenciar estrutura'; end if;
  if length(btrim(coalesce(p_razao_social,'')))<2 then raise exception using errcode='22023',message='Razao social invalida'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<5 then raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  select * into v_old from public.empresas where id=v_empresa for update;
  update public.empresas set razao_social=btrim(p_razao_social),nome_fantasia=nullif(btrim(coalesce(p_nome_fantasia,'')),''),cnpj=nullif(btrim(coalesce(p_cnpj,'')),''),updated_at=now() where id=v_empresa;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  values(v_empresa,null,v_ator,'empresa',v_empresa,'empresa.atualizada',to_jsonb(v_old)-'created_at'-'updated_at'-'created_by',
    jsonb_build_object('razao_social',btrim(p_razao_social),'nome_fantasia',nullif(btrim(coalesce(p_nome_fantasia,'')) ,''),'cnpj',nullif(btrim(coalesce(p_cnpj,'')),'')),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
end $function$;

create function private.admin_unidade_salvar(p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $function$
declare v_empresa uuid; v_ator uuid:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; v_id uuid; v_old public.unidades%rowtype;
begin
  v_empresa:=private.empresa_estrutura_admin();
  if v_empresa is null then raise exception using errcode='42501',message='Sem permissao para gerenciar estrutura'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome da unidade invalido'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<5 then raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  if p_unidade_id is null then
    insert into public.unidades(empresa_id,nome,codigo,ativo,created_by) values(v_empresa,btrim(p_nome),nullif(btrim(coalesce(p_codigo,'')),''),coalesce(p_ativo,true),v_ator) returning id into v_id;
    insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
    values(v_empresa,v_id,v_ator,'unidade',v_id,'unidade.criada',null,jsonb_build_object('nome',btrim(p_nome),'codigo',nullif(btrim(coalesce(p_codigo,'')),''),'ativo',coalesce(p_ativo,true)),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
  else
    select * into v_old from public.unidades where id=p_unidade_id and empresa_id=v_empresa for update;
    if not found then raise exception using errcode='P0002',message='Unidade nao encontrada no escopo autorizado'; end if;
    if not coalesce(p_ativo,true) and exists(select 1 from public.usuarios where unidade_id=p_unidade_id and ativo and status='ativo') then
      raise exception using errcode='23514',message='Unidade possui usuarios ativos vinculados'; end if;
    v_id:=p_unidade_id;
    update public.unidades set nome=btrim(p_nome),codigo=nullif(btrim(coalesce(p_codigo,'')),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
    insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
    values(v_empresa,v_id,v_ator,'unidade',v_id,'unidade.atualizada',to_jsonb(v_old)-'created_at'-'updated_at'-'created_by',jsonb_build_object('nome',btrim(p_nome),'codigo',nullif(btrim(coalesce(p_codigo,'')),''),'ativo',coalesce(p_ativo,true)),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
  end if;
  return v_id;
end $function$;

create function private.admin_setor_salvar(p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $function$
declare v_empresa uuid; v_ator uuid:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; v_id uuid; v_old public.setores%rowtype;
begin
  v_empresa:=private.empresa_estrutura_admin();
  if v_empresa is null then raise exception using errcode='42501',message='Sem permissao para gerenciar estrutura'; end if;
  if not exists(select 1 from public.unidades where id=p_unidade_id and empresa_id=v_empresa) then raise exception using errcode='22023',message='Unidade fora do escopo autorizado'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do setor invalido'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<5 then raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  if p_setor_id is null then
    insert into public.setores(unidade_id,nome,codigo,ativo,created_by) values(p_unidade_id,btrim(p_nome),nullif(btrim(coalesce(p_codigo,'')),''),coalesce(p_ativo,true),v_ator) returning id into v_id;
    insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
    values(v_empresa,p_unidade_id,v_ator,'setor',v_id,'setor.criado',null,jsonb_build_object('unidade_id',p_unidade_id,'nome',btrim(p_nome),'codigo',nullif(btrim(coalesce(p_codigo,'')),''),'ativo',coalesce(p_ativo,true)),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
  else
    select s.* into v_old from public.setores s join public.unidades u on u.id=s.unidade_id where s.id=p_setor_id and u.empresa_id=v_empresa for update of s;
    if not found then raise exception using errcode='P0002',message='Setor nao encontrado no escopo autorizado'; end if;
    v_id:=p_setor_id;
    update public.setores set unidade_id=p_unidade_id,nome=btrim(p_nome),codigo=nullif(btrim(coalesce(p_codigo,'')),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=v_id;
    insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
    values(v_empresa,p_unidade_id,v_ator,'setor',v_id,'setor.atualizado',to_jsonb(v_old)-'created_at'-'updated_at'-'created_by',jsonb_build_object('unidade_id',p_unidade_id,'nome',btrim(p_nome),'codigo',nullif(btrim(coalesce(p_codigo,'')),''),'ativo',coalesce(p_ativo,true)),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
  end if;
  return v_id;
end $function$;

create function private.admin_perfil_criar(p_nome text,p_descricao text,p_permissao_ids uuid[],p_justificativa text)
returns uuid language plpgsql security definer set search_path='' as $function$
declare v_empresa uuid; v_ator uuid:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; v_id uuid; v_perm uuid;
begin
  v_empresa:=private.empresa_gestao_perfis();
  if v_empresa is null then raise exception using errcode='42501',message='Sem permissao para gerir perfis de usuarios'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do perfil invalido'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<5 then raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  insert into public.perfis(empresa_id,nome,descricao,is_system,ativo,created_by) values(v_empresa,btrim(p_nome),nullif(btrim(coalesce(p_descricao,'')),''),false,true,v_ator) returning id into v_id;
  foreach v_perm in array coalesce(p_permissao_ids,'{}'::uuid[]) loop
    if not exists(select 1 from public.permissoes where id=v_perm) then raise exception using errcode='22023',message='Permissao invalida'; end if;
    insert into public.perfil_permissoes(perfil_id,permissao_id,created_by) values(v_id,v_perm,v_ator) on conflict do nothing;
  end loop;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  values(v_empresa,null,v_ator,'perfil',v_id,'perfil.criado',null,jsonb_build_object('nome',btrim(p_nome),'descricao',nullif(btrim(coalesce(p_descricao,'')),''),'permissao_ids',coalesce(p_permissao_ids,'{}'::uuid[])),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
  return v_id;
end $function$;

create function private.admin_perfil_atualizar(p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text)
returns void language plpgsql security definer set search_path='' as $function$
declare v_empresa uuid; v_ator uuid:=nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; v_old public.perfis%rowtype; v_old_perms uuid[]; v_perm uuid;
begin
  v_empresa:=private.empresa_gestao_perfis();
  if v_empresa is null then raise exception using errcode='42501',message='Sem permissao para gerir perfis de usuarios'; end if;
  if length(btrim(coalesce(p_nome,'')))<2 then raise exception using errcode='22023',message='Nome do perfil invalido'; end if;
  if length(btrim(coalesce(p_justificativa,'')))<5 then raise exception using errcode='22023',message='Justificativa deve possuir ao menos 5 caracteres'; end if;
  select * into v_old from public.perfis where id=p_perfil_id and empresa_id=v_empresa and not is_system for update;
  if not found then raise exception using errcode='42501',message='Perfil de sistema ou fora do escopo nao pode ser alterado'; end if;
  select coalesce(array_agg(permissao_id order by permissao_id),'{}'::uuid[]) into v_old_perms from public.perfil_permissoes where perfil_id=p_perfil_id;
  if not coalesce(p_ativo,true) and exists(select 1 from public.usuario_perfis up join public.usuarios u on u.id=up.usuario_id where up.perfil_id=p_perfil_id and u.ativo and u.status='ativo') then
    raise exception using errcode='23514',message='Perfil possui usuarios ativos vinculados'; end if;
  update public.perfis set nome=btrim(p_nome),descricao=nullif(btrim(coalesce(p_descricao,'')),''),ativo=coalesce(p_ativo,true),updated_at=now() where id=p_perfil_id;
  delete from public.perfil_permissoes where perfil_id=p_perfil_id;
  foreach v_perm in array coalesce(p_permissao_ids,'{}'::uuid[]) loop
    if not exists(select 1 from public.permissoes where id=v_perm) then raise exception using errcode='22023',message='Permissao invalida'; end if;
    insert into public.perfil_permissoes(perfil_id,permissao_id,created_by) values(p_perfil_id,v_perm,v_ator) on conflict do nothing;
  end loop;
  insert into public.auditoria_eventos(empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto)
  values(v_empresa,null,v_ator,'perfil',p_perfil_id,'perfil.atualizado',jsonb_build_object('nome',v_old.nome,'descricao',v_old.descricao,'ativo',v_old.ativo,'permissao_ids',v_old_perms),jsonb_build_object('nome',btrim(p_nome),'descricao',nullif(btrim(coalesce(p_descricao,'')),''),'ativo',coalesce(p_ativo,true),'permissao_ids',coalesce(p_permissao_ids,'{}'::uuid[])),btrim(p_justificativa),jsonb_build_object('origem','rpc'));
end $function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

-- Private command execution only through authenticated wrappers.
revoke all on function private.admin_usuario_vincular_convite(uuid,uuid,uuid[],text) from public,anon,service_role;
revoke all on function private.admin_empresa_atualizar(text,text,text,text) from public,anon,service_role;
revoke all on function private.admin_unidade_salvar(uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function private.admin_setor_salvar(uuid,uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function private.admin_perfil_criar(text,text,uuid[],text) from public,anon,service_role;
revoke all on function private.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) from public,anon,service_role;
grant execute on function private.admin_usuario_vincular_convite(uuid,uuid,uuid[],text) to authenticated;
grant execute on function private.admin_empresa_atualizar(text,text,text,text) to authenticated;
grant execute on function private.admin_unidade_salvar(uuid,text,text,boolean,text) to authenticated;
grant execute on function private.admin_setor_salvar(uuid,uuid,text,text,boolean,text) to authenticated;
grant execute on function private.admin_perfil_criar(text,text,uuid[],text) to authenticated;
grant execute on function private.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) to authenticated;

create function public.admin_usuario_vincular_convite(p_usuario_id uuid,p_unidade_id uuid,p_perfil_ids uuid[],p_justificativa text)
returns void language sql security invoker set search_path='' as $function$ select private.admin_usuario_vincular_convite(p_usuario_id,p_unidade_id,p_perfil_ids,p_justificativa) $function$;
create function public.admin_empresa_atualizar(p_razao_social text,p_nome_fantasia text,p_cnpj text,p_justificativa text)
returns void language sql security invoker set search_path='' as $function$ select private.admin_empresa_atualizar(p_razao_social,p_nome_fantasia,p_cnpj,p_justificativa) $function$;
create function public.admin_unidade_salvar(p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language sql security invoker set search_path='' as $function$ select private.admin_unidade_salvar(p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $function$;
create function public.admin_setor_salvar(p_setor_id uuid,p_unidade_id uuid,p_nome text,p_codigo text,p_ativo boolean,p_justificativa text)
returns uuid language sql security invoker set search_path='' as $function$ select private.admin_setor_salvar(p_setor_id,p_unidade_id,p_nome,p_codigo,p_ativo,p_justificativa) $function$;
create function public.admin_perfil_criar(p_nome text,p_descricao text,p_permissao_ids uuid[],p_justificativa text)
returns uuid language sql security invoker set search_path='' as $function$ select private.admin_perfil_criar(p_nome,p_descricao,p_permissao_ids,p_justificativa) $function$;
create function public.admin_perfil_atualizar(p_perfil_id uuid,p_nome text,p_descricao text,p_ativo boolean,p_permissao_ids uuid[],p_justificativa text)
returns void language sql security invoker set search_path='' as $function$ select private.admin_perfil_atualizar(p_perfil_id,p_nome,p_descricao,p_ativo,p_permissao_ids,p_justificativa) $function$;

revoke all on function public.admin_usuario_vincular_convite(uuid,uuid,uuid[],text) from public,anon,service_role;
revoke all on function public.admin_empresa_atualizar(text,text,text,text) from public,anon,service_role;
revoke all on function public.admin_unidade_salvar(uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function public.admin_setor_salvar(uuid,uuid,text,text,boolean,text) from public,anon,service_role;
revoke all on function public.admin_perfil_criar(text,text,uuid[],text) from public,anon,service_role;
revoke all on function public.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) from public,anon,service_role;
grant execute on function public.admin_usuario_vincular_convite(uuid,uuid,uuid[],text) to authenticated;
grant execute on function public.admin_empresa_atualizar(text,text,text,text) to authenticated;
grant execute on function public.admin_unidade_salvar(uuid,text,text,boolean,text) to authenticated;
grant execute on function public.admin_setor_salvar(uuid,uuid,text,text,boolean,text) to authenticated;
grant execute on function public.admin_perfil_criar(text,text,uuid[],text) to authenticated;
grant execute on function public.admin_perfil_atualizar(uuid,text,text,boolean,uuid[],text) to authenticated;

-- Helpful indexes for new administration/audit access paths.
create index if not exists idx_auditoria_eventos_ator on public.auditoria_eventos(ator_id);
create index if not exists idx_auditoria_eventos_unidade on public.auditoria_eventos(unidade_id);
create index if not exists idx_usuarios_unidade_empresa on public.usuarios(unidade_id, empresa_id);

reset lock_timeout;
reset statement_timeout;
