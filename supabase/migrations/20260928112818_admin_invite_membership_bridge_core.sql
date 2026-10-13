-- Marco 1.5 / checkpoint de testabilidade: convite tenant-aware e resumo comercial visivel.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- O writer administrativo passa a enxergar/escrever somente o necessario para manter
-- o modelo legado e memberships consistentes durante a transicao.
grant select (id, usuario_id, empresa_id, unidade_id, status, is_owner, created_by),
      insert (usuario_id, empresa_id, unidade_id, status, is_owner, created_by),
      update (unidade_id, status, updated_at)
  on public.usuario_empresas to bpf_admin_writer;
grant select (usuario_empresa_id, perfil_id),
      insert (usuario_empresa_id, perfil_id, created_by)
  on public.usuario_empresa_perfis to bpf_admin_writer;

-- O writer pode consultar o contexto tenant-aware, mas nao recebe acesso ao catalogo por fora do helper.
grant bpf_tenant_reader to postgres with inherit false, set true;
set role bpf_tenant_reader;
grant execute on function private.meu_contexto_empresa(uuid) to bpf_admin_writer;
reset role;
grant bpf_tenant_reader to postgres with inherit false, set false;

-- Politicas adicionais sao permissivas somente para o tenant explicitamente validado dentro
-- do SECURITY DEFINER. authenticated continua sem SET ROLE para bpf_admin_writer.
create policy unidades_admin_writer_tenant_select on public.unidades
  for select to bpf_admin_writer
  using (empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid);

create policy perfis_admin_writer_tenant_select on public.perfis
  for select to bpf_admin_writer
  using (
    (empresa_id is null and is_system)
    or empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
  );

create policy usuarios_admin_writer_pending_target_update_tenant on public.usuarios
  for update to bpf_admin_writer
  using (
    empresa_id is null and status = 'pendente'
    and id = nullif(current_setting('bpf.invite_target', true), '')::uuid
  )
  with check (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and status = 'ativo' and ativo
  );

create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (exists (
    select 1
    from public.usuarios u
    join public.perfis p on p.id = usuario_perfis.perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system)
        or p.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid)
    where u.id = usuario_perfis.usuario_id
      and u.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
  ));

create policy usuario_empresas_admin_writer_tenant_select on public.usuario_empresas
  for select to bpf_admin_writer
  using (empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid);

create policy usuario_empresas_admin_writer_tenant_insert on public.usuario_empresas
  for insert to bpf_admin_writer
  with check (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and created_by = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  );

create policy usuario_empresa_perfis_admin_writer_tenant_select on public.usuario_empresa_perfis
  for select to bpf_admin_writer
  using (exists (
    select 1 from public.usuario_empresas ue
    where ue.id = usuario_empresa_perfis.usuario_empresa_id
      and ue.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
  ));

create policy usuario_empresa_perfis_admin_writer_tenant_insert on public.usuario_empresa_perfis
  for insert to bpf_admin_writer
  with check (exists (
    select 1
    from public.usuario_empresas ue
    join public.perfis p on p.id = usuario_empresa_perfis.perfil_id
      and p.ativo
      and ((p.empresa_id is null and p.is_system) or p.empresa_id = ue.empresa_id)
    where ue.id = usuario_empresa_perfis.usuario_empresa_id
      and ue.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
  ));

create policy auditoria_eventos_admin_writer_tenant_insert on public.auditoria_eventos
  for insert to bpf_admin_writer
  with check (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and ator_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  );

-- Torna a checagem de teto de delegacao consciente do tenant ativo quando a operacao
-- explicitamente define bpf.active_empresa. Fora desse fluxo, preserva o comportamento legado.
grant bpf_admin_writer to postgres with inherit false, set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create or replace function private.ator_possui_permissao(p_permissao_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select case
    when nullif(current_setting('bpf.active_empresa', true), '')::uuid is not null then exists (
      select 1
      from public.usuarios u
      join public.usuario_empresas ue
        on ue.usuario_id = u.id
       and ue.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
       and ue.status = 'ativo'
      join public.usuario_empresa_perfis uep on uep.usuario_empresa_id = ue.id
      join public.perfis p on p.id = uep.perfil_id
        and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id = ue.empresa_id)
      join public.perfil_permissoes pp on pp.perfil_id = p.id
      where u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
        and u.ativo and u.status = 'ativo'
        and pp.permissao_id = p_permissao_id
    )
    else exists (
      select 1
      from public.usuarios u
      join public.usuario_perfis up on up.usuario_id = u.id
      join public.perfis p on p.id = up.perfil_id
        and p.ativo
        and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
      join public.perfil_permissoes pp on pp.perfil_id = p.id
      where u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
        and u.ativo and u.status = 'ativo'
        and pp.permissao_id = p_permissao_id
    )
  end
$function$;

create function private.admin_usuario_vincular_convite_tenant(
  p_empresa_id uuid,
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
  v_ator uuid := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  v_usuario public.usuarios%rowtype;
  v_membership_id uuid;
  v_perfil_id uuid;
  v_permissoes text[];
begin
  select c.permissoes into v_permissoes
  from private.meu_contexto_empresa(p_empresa_id) c
  where c.usuario_id = v_ator;

  if v_permissoes is null
     or not ('configuracoes.visualizar' = any(v_permissoes))
     or not ('usuarios.gerenciar' = any(v_permissoes))
     or not ('usuarios.convidar' = any(v_permissoes)) then
    raise exception using errcode='42501', message='Sem permissao para convidar usuarios no tenant selecionado';
  end if;

  if length(btrim(coalesce(p_justificativa,''))) < 5 then
    raise exception using errcode='22023', message='Justificativa deve possuir ao menos 5 caracteres';
  end if;
  if coalesce(array_length(p_perfil_ids,1),0) = 0 then
    raise exception using errcode='22023', message='Selecione ao menos um perfil';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_empresa_id::text, 0));
  perform set_config('bpf.active_empresa', p_empresa_id::text, true);
  perform set_config('bpf.invite_target', p_usuario_id::text, true);

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
        and not (pm.codigo = any(v_permissoes))
    ) then
      raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
    end if;
  end loop;

  select * into v_usuario
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

  -- Compatibilidade: o usuario convidado recebe este tenant como empresa primaria legada.
  update public.usuarios
  set empresa_id=p_empresa_id, unidade_id=p_unidade_id, status='ativo', ativo=true, updated_at=now()
  where id=p_usuario_id;

  insert into public.usuario_perfis(usuario_id, perfil_id, created_by)
    select p_usuario_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_id, perfil_id) do nothing;

  insert into public.usuario_empresas(usuario_id, empresa_id, unidade_id, status, is_owner, created_by)
  values(p_usuario_id, p_empresa_id, p_unidade_id, 'ativo', false, v_ator)
  on conflict (usuario_id, empresa_id) do update
    set unidade_id=excluded.unidade_id, status='ativo', updated_at=now()
  returning id into v_membership_id;

  insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id, created_by)
    select v_membership_id, x, v_ator from unnest(p_perfil_ids) x
    on conflict (usuario_empresa_id, perfil_id) do nothing;

  insert into public.auditoria_eventos(
    empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto
  ) values(
    p_empresa_id,p_unidade_id,v_ator,'usuario',p_usuario_id,'usuario.convidado_vinculado',
    jsonb_build_object('empresa_id',null,'status','pendente'),
    jsonb_build_object('empresa_id',p_empresa_id,'unidade_id',p_unidade_id,'status','ativo','perfil_ids',p_perfil_ids,'membership_id',v_membership_id),
    btrim(p_justificativa),jsonb_build_object('origem','edge_function','modelo','membership')
  );
end
$function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

revoke all on function private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)
  from public,anon,service_role;
grant execute on function private.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)
  to authenticated;

create function public.admin_usuario_vincular_convite_tenant(
  p_empresa_id uuid,
  p_usuario_id uuid,
  p_unidade_id uuid,
  p_perfil_ids uuid[],
  p_justificativa text
)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_usuario_vincular_convite_tenant(
    p_empresa_id,p_usuario_id,p_unidade_id,p_perfil_ids,p_justificativa
  )
$function$;

revoke all on function public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)
  from public,anon,service_role;
grant execute on function public.admin_usuario_vincular_convite_tenant(uuid,uuid,uuid,uuid[],text)
  to authenticated;

-- Resumo de plano/consumo para a area administrativa. Mesmo sem plano atribuido,
-- um membership valido recebe uma linha com consumo atual e limites nulos.
grant select (empresa_id) on public.usuarios to bpf_entitlement_reader;
grant select (id, empresa_id, ativo) on public.unidades to bpf_entitlement_reader;
create policy unidades_entitlement_reader_vinculos on public.unidades
  for select to bpf_entitlement_reader
  using (exists (
    select 1 from public.usuario_empresas ue
    where ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      and ue.empresa_id = unidades.empresa_id
      and ue.status = 'ativo'
  ));

grant bpf_entitlement_reader to postgres with inherit false, set true;
grant create on schema private to bpf_entitlement_reader;
set role bpf_entitlement_reader;

create function private.meu_plano_resumo(p_empresa_id uuid)
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
    (
      select count(*) from (
        select u2.id as usuario_id
        from public.usuarios u2
        where u2.empresa_id = p_empresa_id and u2.ativo and u2.status='ativo'
        union
        select ue2.usuario_id
        from public.usuario_empresas ue2
        where ue2.empresa_id = p_empresa_id and ue2.status='ativo'
      ) ativos
    )::bigint,
    (select pe.valor_inteiro from public.plano_entitlements pe
      where pe.plano_id=p.id and pe.chave='usuarios_ativos.max' and pe.tipo='inteiro'),
    (select count(*) from public.unidades un where un.empresa_id=p_empresa_id and un.ativo)::bigint,
    (select pe.valor_inteiro from public.plano_entitlements pe
      where pe.plano_id=p.id and pe.chave='unidades.max' and pe.tipo='inteiro')
  from public.usuario_empresas ue
  join public.usuarios u on u.id=ue.usuario_id and u.ativo and u.status='ativo'
  left join public.empresa_planos ep on ep.empresa_id=ue.empresa_id
  left join public.planos p on p.id=ep.plano_id
  where ue.usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and ue.empresa_id=p_empresa_id and ue.status='ativo'
  limit 1
$function$;

revoke all on function private.meu_plano_resumo(uuid) from public,anon,authenticated,service_role;
grant execute on function private.meu_plano_resumo(uuid) to authenticated;

reset role;
revoke create on schema private from bpf_entitlement_reader;
grant bpf_entitlement_reader to postgres with inherit false, set false;

create function public.meu_plano_resumo(p_empresa_id uuid)
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
security invoker
set search_path = ''
as $function$
  select * from private.meu_plano_resumo(p_empresa_id)
$function$;

revoke all on function public.meu_plano_resumo(uuid) from public,anon,service_role;
grant execute on function public.meu_plano_resumo(uuid) to authenticated;

reset lock_timeout;
reset statement_timeout;
