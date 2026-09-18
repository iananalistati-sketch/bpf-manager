-- Prevent indirect privilege escalation through profile creation/assignment.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- The restricted writer may inspect the permission catalog, but remains a NOLOGIN/NOBYPASSRLS role.
alter policy permissoes_admin_writer_select on public.permissoes using (true);

grant create on schema private to bpf_admin_writer;
set role bpf_admin_writer;

create function private.ator_possui_permissao(p_permissao_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select exists (
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
$function$;

create function private.trg_limite_delegacao_usuario_perfil()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if current_user <> 'bpf_admin_writer' then return new; end if;
  if exists (
    select 1 from public.perfil_permissoes pp
    where pp.perfil_id = new.perfil_id
      and not private.ator_possui_permissao(pp.permissao_id)
  ) then
    raise exception using errcode='42501', message='Nao e permitido delegar um perfil com permissoes superiores as do ator';
  end if;
  return new;
end
$function$;

create function private.trg_limite_delegacao_permissao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if current_user <> 'bpf_admin_writer' then return new; end if;
  if not private.ator_possui_permissao(new.permissao_id) then
    raise exception using errcode='42501', message='Nao e permitido conceder uma permissao que o ator nao possui';
  end if;
  return new;
end
$function$;

create function private.trg_protege_perfil_em_uso()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare v_perfil uuid := case when tg_op='DELETE' then old.perfil_id else new.perfil_id end;
begin
  if current_user <> 'bpf_admin_writer' then return case when tg_op='DELETE' then old else new end; end if;
  if exists (
    select 1 from public.usuario_perfis up
    join public.usuarios u on u.id = up.usuario_id
    where up.perfil_id = v_perfil and u.ativo and u.status = 'ativo'
  ) then
    raise exception using errcode='23514', message='Perfil em uso por usuarios ativos deve ser desvinculado antes de alterar permissoes';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

reset role;
revoke create on schema private from bpf_admin_writer;
grant bpf_admin_writer to postgres with inherit false, set false;

revoke all on function private.ator_possui_permissao(uuid) from public,anon,authenticated,service_role;
revoke all on function private.trg_limite_delegacao_usuario_perfil() from public,anon,authenticated,service_role;
revoke all on function private.trg_limite_delegacao_permissao() from public,anon,authenticated,service_role;
revoke all on function private.trg_protege_perfil_em_uso() from public,anon,authenticated,service_role;

create trigger trg_usuario_perfil_limite_delegacao
before insert on public.usuario_perfis
for each row execute function private.trg_limite_delegacao_usuario_perfil();

create trigger trg_perfil_permissao_limite_delegacao
before insert on public.perfil_permissoes
for each row execute function private.trg_limite_delegacao_permissao();

create trigger trg_perfil_permissao_protege_em_uso
before insert or delete on public.perfil_permissoes
for each row execute function private.trg_protege_perfil_em_uso();

reset lock_timeout;
reset statement_timeout;
