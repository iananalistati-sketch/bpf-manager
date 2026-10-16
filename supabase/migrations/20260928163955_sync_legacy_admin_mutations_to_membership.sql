-- Marco 1.5: mantém as mutações administrativas legadas sincronizadas com o
-- modelo canônico de memberships enquanto a camada antiga ainda existe.
-- O vínculo legado representa somente a empresa primária; memberships secundários
-- não são alterados por esta ponte.
set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function private.sync_legacy_usuario_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- A ponte só acompanha memberships primários já existentes. Convites e
  -- provisionamento continuam responsáveis pela criação inicial do vínculo.
  if new.empresa_id is null then
    return new;
  end if;

  update public.usuario_empresas
  set unidade_id = new.unidade_id,
      status = new.status,
      updated_at = now()
  where usuario_id = new.id
    and empresa_id = new.empresa_id;

  return new;
end
$function$;

revoke all on function private.sync_legacy_usuario_membership() from public, anon, authenticated, service_role;

create or replace function private.sync_legacy_usuario_perfil_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_usuario_id uuid;
  v_perfil_id uuid;
  v_created_by uuid;
  v_empresa_id uuid;
  v_membership_id uuid;
begin
  if tg_op = 'INSERT' then
    v_usuario_id := new.usuario_id;
    v_perfil_id := new.perfil_id;
    v_created_by := new.created_by;
  elsif tg_op = 'DELETE' then
    v_usuario_id := old.usuario_id;
    v_perfil_id := old.perfil_id;
    v_created_by := old.created_by;
  else
    return null;
  end if;

  select u.empresa_id
    into v_empresa_id
  from public.usuarios u
  where u.id = v_usuario_id;

  if v_empresa_id is null then
    return null;
  end if;

  select ue.id
    into v_membership_id
  from public.usuario_empresas ue
  where ue.usuario_id = v_usuario_id
    and ue.empresa_id = v_empresa_id;

  -- Não cria membership implicitamente. Isso evita interferência com convite,
  -- limites comerciais e provisionamento, que possuem fluxos transacionais próprios.
  if v_membership_id is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    insert into public.usuario_empresa_perfis(usuario_empresa_id, perfil_id, created_by)
    values(v_membership_id, v_perfil_id, v_created_by)
    on conflict (usuario_empresa_id, perfil_id) do nothing;
  else
    delete from public.usuario_empresa_perfis
    where usuario_empresa_id = v_membership_id
      and perfil_id = v_perfil_id;
  end if;

  return null;
end
$function$;

revoke all on function private.sync_legacy_usuario_perfil_membership() from public, anon, authenticated, service_role;

drop trigger if exists trg_sync_legacy_usuario_membership on public.usuarios;
create trigger trg_sync_legacy_usuario_membership
after update of unidade_id, status, ativo on public.usuarios
for each row
when (
  old.unidade_id is distinct from new.unidade_id
  or old.status is distinct from new.status
  or old.ativo is distinct from new.ativo
)
execute function private.sync_legacy_usuario_membership();

drop trigger if exists trg_sync_legacy_usuario_perfil_membership on public.usuario_perfis;
create trigger trg_sync_legacy_usuario_perfil_membership
after insert or delete on public.usuario_perfis
for each row execute function private.sync_legacy_usuario_perfil_membership();

comment on function private.sync_legacy_usuario_membership() is
  'Ponte transitória Marco 1.5: sincroniza status/unidade do vínculo legado com o membership primário existente sem tocar memberships secundários.';
comment on function private.sync_legacy_usuario_perfil_membership() is
  'Ponte transitória Marco 1.5: sincroniza perfis legados com o membership primário existente sem tocar memberships secundários.';

reset lock_timeout;
reset statement_timeout;
