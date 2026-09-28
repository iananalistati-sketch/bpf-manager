-- Permite ao writer restrito ler a propria identidade durante checagens tenant-aware,
-- mesmo quando a empresa primaria legada difere do tenant ativo.
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuarios_admin_writer_actor_select on public.usuarios
  for select to bpf_admin_writer
  using (
    id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and ativo and status='ativo'
  );

reset lock_timeout;
reset statement_timeout;
