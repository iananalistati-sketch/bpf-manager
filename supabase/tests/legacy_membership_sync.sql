begin;

create temp table qa_sync_ids(name text primary key, id uuid not null default gen_random_uuid());
insert into qa_sync_ids(name) values
  ('company_primary'), ('company_secondary'), ('unit_p1'), ('unit_p2'),
  ('user'), ('profile_primary'), ('profile_secondary');

create function pg_temp.sync_id(key text) returns uuid language sql stable
as $$ select id from pg_temp.qa_sync_ids where name = key $$;
create function pg_temp.sync_assert(ok boolean, label text) returns void language plpgsql
as $$ begin if ok is distinct from true then raise exception 'QA legacy sync failed: %', label; end if; end $$;

insert into public.empresas(id, razao_social, nome_fantasia) values
  (pg_temp.sync_id('company_primary'), 'QA Primary', 'QA Primary'),
  (pg_temp.sync_id('company_secondary'), 'QA Secondary', 'QA Secondary');

insert into public.unidades(id, empresa_id, nome) values
  (pg_temp.sync_id('unit_p1'), pg_temp.sync_id('company_primary'), 'QA P1'),
  (pg_temp.sync_id('unit_p2'), pg_temp.sync_id('company_primary'), 'QA P2');

insert into auth.users(id, email, raw_user_meta_data) values
  (pg_temp.sync_id('user'), 'legacy-sync@example.invalid', '{"nome":"Legacy Sync"}'::jsonb);

update public.usuarios
set empresa_id = pg_temp.sync_id('company_primary'),
    unidade_id = pg_temp.sync_id('unit_p1'),
    status = 'ativo',
    ativo = true
where id = pg_temp.sync_id('user');

insert into public.usuario_empresas(id, usuario_id, empresa_id, unidade_id, status, is_owner) values
  (gen_random_uuid(), pg_temp.sync_id('user'), pg_temp.sync_id('company_primary'), pg_temp.sync_id('unit_p1'), 'ativo', false),
  (gen_random_uuid(), pg_temp.sync_id('user'), pg_temp.sync_id('company_secondary'), null, 'ativo', false);

insert into public.perfis(id, empresa_id, nome, is_system, ativo) values
  (pg_temp.sync_id('profile_primary'), pg_temp.sync_id('company_primary'), 'QA Primary Profile', false, true),
  (pg_temp.sync_id('profile_secondary'), pg_temp.sync_id('company_secondary'), 'QA Secondary Profile', false, true);

-- Status/unidade legados sincronizam somente o membership da empresa primária.
update public.usuarios
set unidade_id = pg_temp.sync_id('unit_p2'), status = 'bloqueado', ativo = false
where id = pg_temp.sync_id('user');

select pg_temp.sync_assert(
  (select unidade_id = pg_temp.sync_id('unit_p2') and status = 'bloqueado'
   from public.usuario_empresas
   where usuario_id = pg_temp.sync_id('user') and empresa_id = pg_temp.sync_id('company_primary')),
  'primary membership follows legacy status/unit'
);
select pg_temp.sync_assert(
  (select unidade_id is null and status = 'ativo'
   from public.usuario_empresas
   where usuario_id = pg_temp.sync_id('user') and empresa_id = pg_temp.sync_id('company_secondary')),
  'secondary membership remains untouched'
);

-- Perfil legado entra e sai somente do membership primário.
insert into public.usuario_perfis(usuario_id, perfil_id)
values(pg_temp.sync_id('user'), pg_temp.sync_id('profile_primary'));

select pg_temp.sync_assert(
  (select count(*) = 1
   from public.usuario_empresa_perfis uep
   join public.usuario_empresas ue on ue.id = uep.usuario_empresa_id
   where ue.usuario_id = pg_temp.sync_id('user')
     and ue.empresa_id = pg_temp.sync_id('company_primary')
     and uep.perfil_id = pg_temp.sync_id('profile_primary')),
  'legacy profile insert syncs primary membership'
);
select pg_temp.sync_assert(
  (select count(*) = 0
   from public.usuario_empresa_perfis uep
   join public.usuario_empresas ue on ue.id = uep.usuario_empresa_id
   where ue.usuario_id = pg_temp.sync_id('user')
     and ue.empresa_id = pg_temp.sync_id('company_secondary')),
  'legacy profile insert does not touch secondary membership'
);

delete from public.usuario_perfis
where usuario_id = pg_temp.sync_id('user')
  and perfil_id = pg_temp.sync_id('profile_primary');

select pg_temp.sync_assert(
  (select count(*) = 0
   from public.usuario_empresa_perfis uep
   join public.usuario_empresas ue on ue.id = uep.usuario_empresa_id
   where ue.usuario_id = pg_temp.sync_id('user')
     and ue.empresa_id = pg_temp.sync_id('company_primary')
     and uep.perfil_id = pg_temp.sync_id('profile_primary')),
  'legacy profile delete syncs primary membership'
);

-- Usuário legado sem membership não recebe vínculo implicitamente: convite/provisionamento
-- continuam donos da criação inicial e dos limites comerciais.
delete from public.usuario_empresas
where usuario_id = pg_temp.sync_id('user') and empresa_id = pg_temp.sync_id('company_primary');
update public.usuarios
set status = 'ativo', ativo = true, unidade_id = pg_temp.sync_id('unit_p1')
where id = pg_temp.sync_id('user');
select pg_temp.sync_assert(
  (select count(*) = 0 from public.usuario_empresas
   where usuario_id = pg_temp.sync_id('user') and empresa_id = pg_temp.sync_id('company_primary')),
  'bridge never creates missing membership implicitly'
);

select 'PASS: legacy admin mutations synchronize only the primary existing membership and preserve secondary memberships' as result;
rollback;
