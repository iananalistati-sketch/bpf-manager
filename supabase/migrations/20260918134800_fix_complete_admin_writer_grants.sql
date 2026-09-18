-- Align the restricted administration writer with every column and RLS path used by the complete administration commands.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- Invitation linkage promotes exactly one pending user into the actor's company.
-- authenticated still has no direct UPDATE grant and bpf_admin_writer is NOLOGIN/NOBYPASSRLS.
grant update (empresa_id) on public.usuarios to bpf_admin_writer;

-- Unit update uses a full row snapshot for atomic audit before/after values.
grant select (codigo, created_at, updated_at, created_by) on public.unidades to bpf_admin_writer;

-- Sector editing supports moving a sector between units of the same company.
grant update (unidade_id) on public.setores to bpf_admin_writer;

-- Structure administration must not implicitly require usuarios.gerenciar merely to read its
-- own units or to verify whether a unit still has active users before deactivation.
create policy unidades_admin_writer_structure_select on public.unidades
  for select to bpf_admin_writer
  using (empresa_id = (select private.empresa_estrutura_admin()));

create policy usuarios_admin_writer_structure_select on public.usuarios
  for select to bpf_admin_writer
  using (empresa_id = (select private.empresa_estrutura_admin()));

reset lock_timeout;
reset statement_timeout;
