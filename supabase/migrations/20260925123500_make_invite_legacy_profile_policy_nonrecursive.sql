-- Remove a cadeia RLS indireta do INSERT legado em usuario_perfis durante convite tenant-aware.
-- O conjunto de perfis ja e validado dentro da funcao SECURITY DEFINER antes da mutacao.
-- A policy passa a conferir somente os valores previamente validados e gravados em GUCs
-- locais da transacao, evitando uma subconsulta em perfis sujeita a outra RLS.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Mantem a mesma assinatura/owner/ACL e adiciona apenas o contexto validado de perfis.
grant bpf_admin_writer to postgres with inherit false, set true;
grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create or replace function private.admin_usuario_vincular_convite_tenant(
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

  -- So depois de validar todos os perfis o conjunto e exposto a policies da mesma transacao.
  perform set_config('bpf.invite_profiles', p_perfil_ids::text, true);

  select * into v_usuario
  from public.usuarios
  where id=p_usuario_id and empresa_id is null and status='pendente'
  for update;
  if not found then
    raise exception using errcode='P0002', message='Convite pendente nao encontrado';
  end if;

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

-- Elimina a dependencia da policy de INSERT em usuario_perfis de SELECTs sujeitos a RLS.
drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;
create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and created_by = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and perfil_id = any(
      coalesce(
        nullif(current_setting('bpf.invite_profiles', true), '')::uuid[],
        array[]::uuid[]
      )
    )
  );

reset lock_timeout;
reset statement_timeout;
