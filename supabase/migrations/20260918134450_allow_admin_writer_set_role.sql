-- Temporarily allow the migration deployer to SET ROLE bpf_admin_writer while creating writer-owned functions.
-- The following administration migration revokes the SET option again after function creation.
set lock_timeout = '5s';
set statement_timeout = '60s';

grant bpf_admin_writer to postgres with inherit false, set true;

reset lock_timeout;
reset statement_timeout;
