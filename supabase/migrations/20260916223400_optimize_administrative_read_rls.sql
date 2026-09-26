-- Keep the same authorization semantics while reducing per-row policy work.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Cache the JWT subject expression once per statement for the restricted helper role.
alter policy usuarios_authz_reader_proprio on public.usuarios
  using (id = (select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid));

alter policy usuario_perfis_authz_reader_proprio on public.usuario_perfis
  using (usuario_id = (select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid));

-- Merge the authenticated self-read and administrative-read paths into one permissive
-- policy per table. This preserves bootstrap self-read and same-company admin read.
alter policy usuarios_select_proprio on public.usuarios
  using (
    id = (select auth.uid())
    or empresa_id = (select private.empresa_leitura_usuarios())
  );

drop policy usuarios_select_administracao_empresa on public.usuarios;

alter policy usuario_perfis_select_proprio on public.usuario_perfis
  using (
    usuario_id = (select auth.uid())
    or exists (
      select 1
      from public.usuarios u
      join public.perfis p on p.id = usuario_perfis.perfil_id
        and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
      where u.id = usuario_perfis.usuario_id
        and u.empresa_id = (select private.empresa_leitura_usuarios())
    )
  );

drop policy usuario_perfis_select_administracao_empresa on public.usuario_perfis;

reset lock_timeout;
reset statement_timeout;
