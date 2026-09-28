-- Remote Supabase hardening: the restricted authorization role cannot rely on USAGE
-- over the managed auth schema. Read the trusted JWT subject setting directly instead.
set lock_timeout = '5s';
set statement_timeout = '60s';

alter policy usuarios_authz_reader_proprio on public.usuarios
  using (id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

alter policy usuario_perfis_authz_reader_proprio on public.usuario_perfis
  using (usuario_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

-- Temporarily allow the function owner to replace/comment its own function, then restore
-- the restricted membership/schema posture established by the previous migration.
grant bpf_authz_reader to postgres with inherit false, set true;
grant create on schema private to bpf_authz_reader;
set role bpf_authz_reader;

create or replace function private.empresa_leitura_usuarios()
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select u.empresa_id
  from public.usuarios u
  join public.usuario_perfis up on up.usuario_id = u.id
  join public.perfis p on p.id = up.perfil_id
    and p.ativo
    and ((p.empresa_id is null and p.is_system) or p.empresa_id = u.empresa_id)
  join public.perfil_permissoes pp on pp.perfil_id = p.id
  join public.permissoes pm on pm.id = pp.permissao_id
  where nullif(current_setting('request.jwt.claim.sub', true), '')::uuid is not null
    and u.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    and u.ativo
    and u.status = 'ativo'
    and u.empresa_id is not null
  group by u.empresa_id
  having bool_or(pm.codigo = 'configuracoes.visualizar')
     and bool_or(pm.codigo = 'usuarios.gerenciar')
$function$;

comment on function private.empresa_leitura_usuarios() is
  'Empresa autorizada para leitura administrativa: subject JWT, usuario ativo e ambas permissoes de perfis ativos validos. Owner restrito e sujeito a RLS; sem parametros nem escrita.';

reset role;
revoke create on schema private from bpf_authz_reader;
grant bpf_authz_reader to postgres with inherit false, set false;

-- The helper no longer depends on the managed auth schema/function.
revoke execute on function auth.uid() from bpf_authz_reader;

reset lock_timeout;
reset statement_timeout;
