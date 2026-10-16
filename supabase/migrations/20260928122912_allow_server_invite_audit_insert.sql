-- Permite que a RPC server-only de convite conclua a escrita atomica de auditoria.
-- A superficie publica da RPC permanece executavel apenas por service_role.
set lock_timeout = '5s';
set statement_timeout = '60s';

grant insert (
  empresa_id,
  unidade_id,
  ator_id,
  entidade,
  registro_id,
  acao,
  antes,
  depois,
  justificativa,
  contexto
) on public.auditoria_eventos to service_role;

comment on function public.admin_usuario_vincular_convite_server(uuid,uuid,uuid,uuid,uuid[],text) is
  'RPC atomica de convite tenant-aware, exclusiva da Edge Function via service_role; revalida RBAC e registra auditoria no mesmo commit.';

reset lock_timeout;
reset statement_timeout;
