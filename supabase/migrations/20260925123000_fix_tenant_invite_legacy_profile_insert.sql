-- Corrige o INSERT legado em usuario_perfis durante convite tenant-aware.
-- A policy anterior dependia de reler o usuario-alvo depois da transicao pendente -> ativo,
-- acoplando a escrita a uma segunda cadeia de RLS em usuarios. Para o fluxo de convite,
-- o alvo e o tenant ja foram validados pela funcao SECURITY DEFINER e registrados em GUCs
-- locais da transacao. Mantemos o escopo minimo: somente invite_target, tenant ativo,
-- perfil ativo/compativel e created_by igual ao subject autenticado.
set lock_timeout = '5s';
set statement_timeout = '60s';

drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and created_by = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and nullif(current_setting('bpf.active_empresa', true), '')::uuid is not null
    and exists (
      select 1
      from public.perfis p
      where p.id = usuario_perfis.perfil_id
        and p.ativo
        and (
          (p.empresa_id is null and p.is_system)
          or p.empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
        )
    )
  );

reset lock_timeout;
reset statement_timeout;
