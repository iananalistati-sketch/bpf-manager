-- Garante que o caminho ON CONFLICT do convite tenant-aware consiga recuperar um
-- membership pendente/preexistente do mesmo alvo sem abrir UPDATE genérico ao writer.
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuario_empresas_admin_writer_invite_target_update
  on public.usuario_empresas
  for update to bpf_admin_writer
  using (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
  )
  with check (
    empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
    and usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and status = 'ativo'
  );

reset lock_timeout;
reset statement_timeout;
