-- Permite ao smoke server-side verificar apenas os metadados mínimos do evento de auditoria.
-- Não expõe payloads sensíveis (antes/depois/contexto) nem amplia acesso de authenticated/anon.
set lock_timeout = '5s';
set statement_timeout = '60s';

grant select (
  id,
  empresa_id,
  registro_id,
  acao,
  created_at
) on public.auditoria_eventos to service_role;

reset lock_timeout;
reset statement_timeout;
