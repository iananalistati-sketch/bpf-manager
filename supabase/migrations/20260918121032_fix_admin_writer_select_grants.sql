-- Align restricted writer read grants with the rowtype reads used by admin commands.
set lock_timeout = '5s';
set statement_timeout = '60s';

grant select (created_at)
  on public.usuarios to bpf_admin_writer;

grant select (descricao, created_at, updated_at, created_by)
  on public.perfis to bpf_admin_writer;

reset lock_timeout;
reset statement_timeout;
