-- Allow each restricted administrative capability to insert its own audit event.
set lock_timeout = '5s';
set statement_timeout = '60s';

alter policy auditoria_eventos_admin_writer_insert on public.auditoria_eventos
  with check (
    ator_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and empresa_id in (
      select x from unnest(array[
        private.empresa_leitura_usuarios(),
        private.empresa_gestao_perfis(),
        private.empresa_convite_usuarios(),
        private.empresa_estrutura_admin()
      ]) as t(x)
      where x is not null
    )
  );

reset lock_timeout;
reset statement_timeout;
