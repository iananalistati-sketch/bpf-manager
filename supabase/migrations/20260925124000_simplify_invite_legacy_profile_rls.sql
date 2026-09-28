-- Simplifica a policy de INSERT legado em usuario_perfis no fluxo de convite tenant-aware.
-- A autorizacao do tenant, a compatibilidade/atividade dos perfis e o teto de delegacao ja sao
-- validados dentro de private.admin_usuario_vincular_convite_tenant antes deste INSERT.
-- Aqui a RLS cumpre apenas a funcao de impedir que bpf_admin_writer insira para outro alvo
-- fora do convite corrente. Isso evita depender de GUC de array/created_by na expressao RLS.
set lock_timeout = '5s';
set statement_timeout = '60s';

drop policy if exists usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis;

create policy usuario_perfis_admin_writer_tenant_insert on public.usuario_perfis
  for insert to bpf_admin_writer
  with check (
    usuario_id = nullif(current_setting('bpf.invite_target', true), '')::uuid
    and nullif(current_setting('bpf.active_empresa', true), '')::uuid is not null
  );

reset lock_timeout;
reset statement_timeout;
