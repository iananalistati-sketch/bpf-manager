-- Corrige a transicao RLS do usuario convidado: durante o UPDATE, o writer restrito
-- precisa continuar enxergando o mesmo alvo tanto no estado pendente (antes) quanto
-- no estado ja vinculado ao tenant ativo (depois).
set lock_timeout = '5s';
set statement_timeout = '60s';

create policy usuarios_admin_writer_invite_target_select_tenant on public.usuarios
  for select to bpf_admin_writer
  using (
    id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and (
      (empresa_id is null and status = 'pendente')
      or (
        empresa_id = nullif(current_setting('bpf.active_empresa', true), '')::uuid
        and ativo and status = 'ativo'
      )
    )
  );

reset lock_timeout;
reset statement_timeout;
