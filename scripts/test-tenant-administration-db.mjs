import assert from 'node:assert/strict'
import { administrationChecks,classifySecondary,secondarySql,verifyAdministration } from './supabase-setup-secondary-qa.mjs'
import { repositoryRoot } from './supabase-preflight.mjs'
import { readFile,readdir } from 'node:fs/promises'

export async function testTenantAdministration(db) {
  const A='ab100000-0000-0000-0000-000000000001',B='ab100000-0000-0000-0000-000000000002'
  const actor='ab000000-0000-0000-0000-000000000001',target='ab000000-0000-0000-0000-000000000002',outsider='ab000000-0000-0000-0000-000000000003'
  const unitA='ab200000-0000-0000-0000-000000000001',unitB='ab200000-0000-0000-0000-000000000002'
  const profileA='ab300000-0000-0000-0000-000000000001',profileB='ab300000-0000-0000-0000-000000000002'
  const memberB='ab400000-0000-0000-0000-000000000002',targetB='ab400000-0000-0000-0000-000000000004'
  const query=(sql,args=[])=>db.query(sql,args)
  const snapshot=async()=> (await query(`select jsonb_build_object(
    'identities',(select jsonb_agg(to_jsonb(u) order by id) from public.usuarios u),
    'legacy',(select jsonb_agg(to_jsonb(up) order by usuario_id,perfil_id) from public.usuario_perfis up),
    'company',(select to_jsonb(e) from public.empresas e where id=$1),
    'members',(select jsonb_agg(to_jsonb(ue) order by id) from public.usuario_empresas ue where empresa_id=$1),
    'profiles',(select jsonb_agg(to_jsonb(p) order by id) from public.perfis p where empresa_id=$1)) as value`,[A])).rows[0].value
  const auth=async()=>{await query("select set_config('request.jwt.claim.sub',$2,true),set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor,role:'authenticated'}),actor]);await db.exec('SET LOCAL ROLE authenticated')}
  const fails=async(sql,args=[],code='42501')=>{
    await db.exec('SAVEPOINT denied')
    try{await assert.rejects(query(sql,args),e=>e.code===code)}
    finally{await db.exec('ROLLBACK TO SAVEPOINT denied; RELEASE SAVEPOINT denied')}
  }
  await db.exec('BEGIN')
  try {
    await query(`insert into public.empresas(id,razao_social) values($1,'PRIMARY preserved'),($2,'TESTE')`,[A,B])
    await query(`insert into public.unidades(id,empresa_id,nome) values($1,$2,'Primary unit'),($3,$4,'TESTE unit')`,[unitA,A,unitB,B])
    for(const [id,email] of [[actor,'admin@test.invalid'],[target,'target@test.invalid'],[outsider,'outside@test.invalid']]) {
      await query('insert into auth.users(id,email) values($1,$2)',[id,email])
      await query("update public.usuarios set empresa_id=$1,unidade_id=$2,status='ativo' where id=$3",[A,unitA,id])
    }
    await query(`insert into public.perfis(id,empresa_id,nome) values($1,$2,'Primary Admin'),($3,$4,'TESTE Admin')`,[profileA,A,profileB,B])
    await query('insert into public.perfil_permissoes(perfil_id,permissao_id) select p,pm.id from unnest($1::uuid[]) p cross join public.permissoes pm',[[profileA,profileB]])
    await query('insert into public.usuario_perfis(usuario_id,perfil_id) values($1,$3),($2,$3)',[actor,target,profileA])
    await query(`insert into public.usuario_empresas(id,usuario_id,empresa_id,unidade_id,status,is_owner) values
      ('ab400000-0000-0000-0000-000000000001',$1,$3,$5,'ativo',true),($7,$1,$4,$6,'ativo',true),
      ('ab400000-0000-0000-0000-000000000003',$2,$3,$5,'ativo',false),($8,$2,$4,$6,'ativo',false),
      ('ab400000-0000-0000-0000-000000000005',$9,$3,$5,'ativo',false)`,[actor,target,A,B,unitA,unitB,memberB,targetB,outsider])
    await query('insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) select id,case when empresa_id=$1 then $2::uuid else $3::uuid end from public.usuario_empresas',[A,profileA,profileB])
    await query(`insert into public.empresa_planos(empresa_id,plano_id,origem) select $1,id,'trial' from public.planos where codigo='business'`,[B])
    await query(`insert into public.empresa_assinaturas(empresa_id,plano_id,status,trial_inicio,trial_fim)
      select $1,id,'trialing',now(),now()+interval '14 days' from public.planos where codigo='business'`,[B])
    // Executable PoCs run independently by Ag09; insert after fixtures and before primary snapshot.
    await db.exec('SAVEPOINT adversarial_09')
    const weak='ab300000-0000-0000-0000-000000000009'
    await query("insert into public.perfis(id,empresa_id,nome) values($1,$2,'Weak actor')",[weak,B])
    await query("insert into public.perfil_permissoes(perfil_id,permissao_id) select $1,id from public.permissoes where codigo in('configuracoes.visualizar','usuarios.gerenciar')",[weak])
    await query('delete from public.usuario_empresa_perfis where usuario_empresa_id=$1',[memberB])
    await query('insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values($1,$2)',[memberB,weak])
    await auth()
    await fails("select public.admin_usuario_status_tenant($1,$2,'inativo','09 last admin attempt')",[B,target])
    await fails("select public.admin_contexto_ler($1,'permissoes')",[B])
    await fails("select public.admin_perfil_tenant($1,null,'forbidden',null,true,'{}'::uuid[],'09 permission removed')",[B])
    await db.exec('RESET ROLE;ROLLBACK TO SAVEPOINT adversarial_09;RELEASE SAVEPOINT adversarial_09')

    await db.exec('SAVEPOINT adversarial_09')
    await query('update public.usuario_empresas set is_owner=false where id=$1',[memberB])
    await query('update public.usuario_empresas set is_owner=true where id=$1',[targetB])
    await auth()
    await fails("select public.admin_usuario_status_tenant($1,$2,'inativo','09 last owner attempt')",[B,target])
    await db.exec('RESET ROLE;ROLLBACK TO SAVEPOINT adversarial_09;RELEASE SAVEPOINT adversarial_09')

    await db.exec('SAVEPOINT adversarial_09')
    await query("insert into public.perfis(id,empresa_id,nome) values($1,$2,'Weak profile admin')",[weak,B])
    await query("insert into public.perfil_permissoes(perfil_id,permissao_id) select $1,id from public.permissoes where codigo in('configuracoes.visualizar','perfis.gerenciar')",[weak])
    await query('delete from public.usuario_empresa_perfis where usuario_empresa_id=$1',[memberB])
    await query('insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values($1,$2)',[memberB,weak])
    const approve=(await query("select id from public.permissoes where codigo='documentos.aprovar'")).rows[0].id
    await auth()
    await fails("select public.admin_perfil_tenant($1,null,'forbidden',null,true,array[$2::uuid],'09 ceiling exceeded')",[B,approve])
    await fails("select public.admin_usuario_perfil_tenant($1,$2,$3,'atribuir','09 ceiling exceeded')",[B,target,profileB])
    await db.exec('RESET ROLE;ROLLBACK TO SAVEPOINT adversarial_09;RELEASE SAVEPOINT adversarial_09')

    await auth()
    await query("select set_config('bpf.admin_empresa',$1,true)",[A])
    await query("select public.admin_contexto_ler($1,'usuarios')",[B])
    assert.equal((await query("select current_setting('bpf.admin_empresa') as value")).rows[0].value,A)
    await fails("select public.admin_usuario_unidade_tenant($1,$2,$3,'09 mixed tenant scope')",[B,target,unitA])
    assert.equal((await query("select current_setting('bpf.admin_empresa') as value")).rows[0].value,A)
    await fails("update public.usuario_empresas set is_owner=false where id=$1",[memberB])
    await db.exec('RESET ROLE')

    await db.exec('SAVEPOINT adversarial_09')
    await query("update public.empresa_assinaturas set trial_inicio=now()-interval '20 days',trial_fim=now()-interval '6 days' where empresa_id=$1",[B])
    await auth()
    for (const [sql,args] of [
      ["select public.admin_usuario_status_tenant($1,$2,'inativo','09 readonly status')",[B,target]],
      ["select public.admin_usuario_unidade_tenant($1,$2,null,'09 readonly unit')",[B,target]],
      ["select public.admin_usuario_perfil_tenant($1,$2,$3,'remover','09 readonly profiles')",[B,target,profileB]],
      ["select public.admin_empresa_tenant($1,'changed',null,null,'09 readonly company')",[B]],
      ["select public.admin_unidade_tenant($1,null,'changed',null,true,'09 readonly unit')",[B]],
      ["select public.admin_setor_tenant($1,null,$2,'changed',null,true,'09 readonly sector')",[B,unitB]],
      ["select public.admin_perfil_tenant($1,null,'changed',null,true,'{}'::uuid[],'09 readonly profile')",[B]],
    ]) await fails(sql,args)
    await db.exec('RESET ROLE;ROLLBACK TO SAVEPOINT adversarial_09;RELEASE SAVEPOINT adversarial_09')
    console.log('PASS09: last admin/owner, missing permissions, canonical ceiling, GUC restoration, direct DML and complete readonly matrix')

    // Ag09: each mutation must deny removed permission and roll back every table on audit failure.
    const securitySnapshot=async()=>{
      const result={}
      for(const table of ['usuarios','usuario_perfis','empresas','unidades','setores','perfis','permissoes','perfil_permissoes','usuario_empresas','usuario_empresa_perfis','auditoria_eventos','empresa_planos','empresa_assinaturas','empresa_onboarding','saas_provisionamentos']) {
        result[table]=(await query(`select coalesce(jsonb_agg(row order by row::text),'[]'::jsonb) as value from (select to_jsonb(t) as row from public.${table} t) rows`)).rows[0].value
      }
      return result
    }
    await db.exec('SAVEPOINT security_matrix')
    const testSector='ab500000-0000-0000-0000-000000000009'
    const unusedProfile='ab300000-0000-0000-0000-000000000008'
    const noPermission='ab300000-0000-0000-0000-000000000007'
    await query("insert into public.setores(id,unidade_id,nome) values($1,$2,'Ag09 sector')",[testSector,unitB])
    await query("insert into public.perfis(id,empresa_id,nome) values($1,$3,'Ag09 unused'),($2,$3,'Ag09 removed permission')",[unusedProfile,noPermission,B])
    await query("insert into public.perfil_permissoes(perfil_id,permissao_id) select $1,id from public.permissoes where codigo='configuracoes.visualizar'",[noPermission])
    const writeCases=[
      ["select public.admin_usuario_status_tenant($1,$2,'inativo','Ag09 mutation status')",[B,target]],
      ["select public.admin_usuario_unidade_tenant($1,$2,null,'Ag09 mutation membership unit')",[B,target]],
      ["select public.admin_usuario_perfil_tenant($1,$2,$3,'remover','Ag09 mutation profile removal')",[B,target,profileB]],
      ["select public.admin_usuario_perfil_tenant($1,$2,$3,'atribuir','Ag09 mutation profile assignment')",[B,target,unusedProfile]],
      ["select public.admin_empresa_tenant($1,'Ag09 company update',null,null,'Ag09 mutation company')",[B]],
      ["select public.admin_unidade_tenant($1,null,'Ag09 created',null,true,'Ag09 mutation unit create')",[B]],
      ["select public.admin_unidade_tenant($1,$2,'Ag09 updated',null,true,'Ag09 mutation unit update')",[B,unitB]],
      ["select public.admin_setor_tenant($1,null,$2,'Ag09 created',null,true,'Ag09 mutation sector create')",[B,unitB]],
      ["select public.admin_setor_tenant($1,$2,$3,'Ag09 updated',null,true,'Ag09 mutation sector update')",[B,testSector,unitB]],
      ["select public.admin_perfil_tenant($1,null,'Ag09 created',null,true,'{}'::uuid[],'Ag09 mutation profile create')",[B]],
      ["select public.admin_perfil_tenant($1,$2,'Ag09 updated',null,true,'{}'::uuid[],'Ag09 mutation profile update')",[B,unusedProfile]],
    ]
    await db.exec('SAVEPOINT permission_removed')
    await query('delete from public.usuario_empresa_perfis where usuario_empresa_id=$1',[memberB])
    await query('insert into public.usuario_empresa_perfis(usuario_empresa_id,perfil_id) values($1,$2)',[memberB,noPermission])
    const deniedBaseline=await securitySnapshot()
    for(const [sql,args] of writeCases) {
      await auth();await fails(sql,args);await db.exec('RESET ROLE')
      assert.deepEqual(await securitySnapshot(),deniedBaseline)
    }
    await db.exec('ROLLBACK TO SAVEPOINT permission_removed;RELEASE SAVEPOINT permission_removed')
    const auditBaseline=await securitySnapshot()
    await db.exec(`CREATE FUNCTION pg_temp.fail_each_tenant_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Ag09 injected audit failure'; END $$;
      CREATE TRIGGER fail_each_tenant_audit BEFORE INSERT ON public.auditoria_eventos FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_each_tenant_audit()`)
    for(const [sql,args] of writeCases) {
      await auth();await fails(sql,args,'P0001');await db.exec('RESET ROLE')
      assert.deepEqual(await securitySnapshot(),auditBaseline)
    }
    await db.exec('ROLLBACK TO SAVEPOINT security_matrix;RELEASE SAVEPOINT security_matrix')
    console.log('PASS09: all seven tenant writes plus create/update branches reject removed permission and atomically roll back identity, legacy, membership, profile, structure, commercial and audit state')

    // The service-only invitation must revalidate membership/RBAC and trial after locking.
    await db.exec('SAVEPOINT invitation_security')
    const invitee='ab000000-0000-0000-0000-000000000009'
    await query('insert into auth.users(id,email) values($1,$2)',[invitee,'invitee09@test.invalid'])
    const inviteSql='select public.admin_usuario_vincular_convite_server($1,$2,$3,$4,$5,$6)'
    const inviteArgs=[actor,B,invitee,unitB,[profileB],'Ag09 direct server invitation']
    const inviteBaseline=await securitySnapshot()
    await auth();await fails(inviteSql,inviteArgs);await db.exec('RESET ROLE')
    assert.deepEqual(await securitySnapshot(),inviteBaseline)
    for(const change of [
      "update public.empresa_assinaturas set trial_inicio=now()-interval '20 days',trial_fim=now()-interval '6 days' where empresa_id=$1",
      "update public.usuario_empresas set status='bloqueado' where usuario_id=$2 and empresa_id=$1",
      "delete from public.usuario_empresa_perfis where usuario_empresa_id in(select id from public.usuario_empresas where usuario_id=$2 and empresa_id=$1)",
    ]) {
      await db.exec('SAVEPOINT invitation_denied')
      await query(change,change.includes('$2')?[B,actor]:[B])
      const before=await securitySnapshot()
      await db.exec('SET LOCAL ROLE service_role');await fails(inviteSql,inviteArgs);await db.exec('RESET ROLE')
      assert.deepEqual(await securitySnapshot(),before)
      await db.exec('ROLLBACK TO SAVEPOINT invitation_denied;RELEASE SAVEPOINT invitation_denied')
    }
    await db.exec(`CREATE FUNCTION pg_temp.fail_server_invite_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Ag09 injected server invite audit'; END $$;
      CREATE TRIGGER fail_server_invite_audit BEFORE INSERT ON public.auditoria_eventos FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_server_invite_audit()`)
    await db.exec('SET LOCAL ROLE service_role');await fails(inviteSql,inviteArgs,'P0001');await db.exec('RESET ROLE')
    assert.deepEqual(await securitySnapshot(),inviteBaseline)
    await db.exec('ROLLBACK TO SAVEPOINT invitation_security;RELEASE SAVEPOINT invitation_security')
    console.log('PASS09: authenticated server invite denied; expired trial, revoked membership/profile and failed audit leave pending identity and every relationship unchanged')

    const primary=await snapshot()
    const privileges=(await query(`select has_table_privilege('bpf_tenant_admin','public.usuarios','UPDATE') as global_write,
      has_table_privilege('bpf_tenant_admin','public.usuario_perfis','INSERT') as legacy_write,
      pg_has_role('authenticated','bpf_tenant_admin','SET') as set_role`)).rows[0]
    assert.deepEqual(privileges,{global_write:false,legacy_write:false,set_role:false})
    await auth()
    assert.equal((await query('select * from public.v_meu_contexto')).rows[0].empresa_id,A)
    const page=(await query("select public.admin_contexto_ler($1,'usuarios',0,1) as page",[B])).rows[0].page
    assert.equal(page.count,2);assert.equal(page.data.length,1)
    assert.equal(page.data[0].empresa_id,B);assert.ok(page.data[0].membership_id)
    const second=(await query("select public.admin_contexto_ler($1,'usuarios',1,1) as page",[B])).rows[0].page
    assert.notEqual(page.data[0].id,second.data[0].id)
    for(const resource of ['empresas','unidades','setores','perfis','permissoes','usuario_perfis','perfil_permissoes','auditoria_eventos','atores_auditoria']) {
      assert.ok(Array.isArray((await query('select public.admin_contexto_ler($1,$2) as page',[B,resource])).rows[0].page.data))
    }
    await fails("select public.admin_contexto_ler($1,'auth.users')",[B],'22023')
    await fails("select public.admin_contexto_ler($1,'usuarios',0,501)",[B],'22023')
    await fails("select public.admin_contexto_ler($1,'usuarios')",['ab100000-0000-0000-0000-000000000099'])
    await query("select public.admin_usuario_status_tenant($1,$2,'inativo','TESTE inativar vinculo')",[B,target])
    await query("select public.admin_usuario_status_tenant($1,$2,'ativo','TESTE reativar vinculo')",[B,target])
    const newUnit=(await query("select public.admin_unidade_tenant($1,null,'TESTE second','QA2',true,'TESTE criar unidade') as id",[B])).rows[0].id
    await query("select public.admin_usuario_unidade_tenant($1,$2,$3,'TESTE unidade do vinculo')",[B,target,newUnit])
    const sector=(await query("select public.admin_setor_tenant($1,null,$2,'TESTE quality','QLD',true,'TESTE criar setor') as id",[B,newUnit])).rows[0].id
    await query("select public.admin_setor_tenant($1,$2,$3,'TESTE updated','QLD',false,'TESTE editar setor')",[B,sector,newUnit])
    await query("select public.admin_empresa_tenant($1,'TESTE updated','TESTE',null,'TESTE editar empresa')",[B])
    const perm=(await query("select (public.admin_contexto_ler($1,'permissoes')->'data'->0->>'id')::uuid as id",[B])).rows[0].id
    await query("select public.admin_perfil_tenant($1,$2,'TESTE Admin renamed',null,true,array(select id from public.permissoes),'TESTE renomear perfil em uso')",[B,profileB])
    const profile=(await query("select public.admin_perfil_tenant($1,null,'TESTE consulta',null,true,array[$2::uuid],'TESTE criar perfil') as id",[B,perm])).rows[0].id
    await query("select public.admin_perfil_tenant($1,$2,'TESTE perfil renomeado',null,true,array[$3::uuid],'TESTE editar perfil')",[B,profile,perm])
    await query("select public.admin_usuario_perfil_tenant($1,$2,$3,'atribuir','TESTE atribuir perfil')",[B,target,profile])
    await query("select public.admin_usuario_perfil_tenant($1,$2,$3,'remover','TESTE remover perfil')",[B,target,profile])
    for(const [sql,args] of [
      ["select public.admin_usuario_status_tenant($1,$2,'inativo','Tentativa tenant adulterado')",[B,outsider]],
      ["select public.admin_usuario_unidade_tenant($1,$2,$3,'Tentativa unidade externa')",[B,target,unitA]],
      ["select public.admin_usuario_perfil_tenant($1,$2,$3,'atribuir','Tentativa perfil externo')",[B,target,profileA]],
      ["select public.admin_unidade_tenant($1,$2,'external',null,true,'Tentativa alvo externo')",[B,unitA]],
      ["select public.admin_setor_tenant($1,$2,$3,'external',null,true,'Tentativa setor externo')",[A,sector,unitA]],
      ["select public.admin_perfil_tenant($1,$2,'external',null,true,'{}'::uuid[],'Tentativa perfil externo')",[B,profileA]],
      ["select public.admin_usuario_status_tenant($1,$2,'bloqueado','Tentativa auto bloqueio')",[B,actor]],
      ["select public.admin_usuario_perfil_tenant($1,$2,$3,'remover','Tentativa proprio perfil')",[B,actor,profileB]],
    ]) await fails(sql,args)
    await fails("select public.admin_unidade_tenant($1,$2,'TESTE second',null,false,'TESTE unidade em uso')",[B,newUnit],'23514')
    await fails("select public.admin_perfil_tenant($1,$2,'TESTE Admin',null,false,'{}'::uuid[],'TESTE perfil em uso')",[B,profileB],'23514')
    await db.exec('RESET ROLE')
    assert.deepEqual(await snapshot(),primary)
    console.log('PASS: tenant admin readers/pagination and all mutations affect TESTE memberships only; role cannot write identities/legacy; cross-tenant and self changes denied')

    await db.exec('SAVEPOINT revoke_secondary')
    await query("update public.usuario_empresas set status='bloqueado' where id=$1",[memberB])
    await auth()
    await fails("select public.admin_contexto_ler($1,'usuarios')",[B])
    await fails("select public.admin_empresa_tenant($1,'forbidden',null,null,'Revogacao de membership')",[B])
    assert.ok((await query("select public.admin_contexto_ler($1,'usuarios') as page",[A])).rows[0].page.count>0)
    await db.exec('RESET ROLE; ROLLBACK TO SAVEPOINT revoke_secondary; RELEASE SAVEPOINT revoke_secondary')

    await db.exec('SAVEPOINT revoke_primary')
    await query("update public.usuario_empresas set status='bloqueado' where usuario_id=$1 and empresa_id=$2",[actor,A])
    await auth()
    await fails("select public.admin_usuario_alterar_status($1,'inativo','Legacy bypass denied')",[target])
    await fails("select private.admin_usuario_alterar_status($1,'inativo','Private legacy bypass denied')",[target])
    assert.equal((await query('select * from public.v_meu_contexto')).rows.length,0)
    assert.equal((await query('select id from public.usuarios where id=$1',[target])).rows.length,0)
    for(const table of ['empresas','unidades','perfis']) assert.equal((await query(`select id from public.${table} where ${table==='empresas'?'id':'empresa_id'}=$1`,[A])).rows.length,0)
    assert.equal((await query("select public.admin_contexto_ler($1,'usuarios') as page",[B])).rows[0].page.count,2)
    await db.exec('RESET ROLE; ROLLBACK TO SAVEPOINT revoke_primary; RELEASE SAVEPOINT revoke_primary')

    await db.exec('SAVEPOINT expired_trial')
    await query("update public.empresa_assinaturas set trial_inicio=now()-interval '20 days',trial_fim=now()-interval '6 days' where empresa_id=$1",[B])
    await auth()
    await fails("select public.admin_usuario_status_tenant($1,$2,'inativo','Trial readonly denied')",[B,target])
    assert.equal((await query("select public.admin_contexto_ler($1,'usuarios') as page",[B])).rows[0].page.count,2)
    await db.exec('RESET ROLE; ROLLBACK TO SAVEPOINT expired_trial; RELEASE SAVEPOINT expired_trial')

    await db.exec(`SAVEPOINT audit_failure; CREATE FUNCTION pg_temp.fail_tenant_admin_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected audit failure'; END $$;
      CREATE TRIGGER fail_tenant_admin_audit BEFORE INSERT ON public.auditoria_eventos FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_tenant_admin_audit()`)
    await auth()
    await fails("select public.admin_usuario_status_tenant($1,$2,'inativo','Rollback audit failure')",[B,target],'P0001')
    await db.exec('RESET ROLE')
    assert.equal((await query('select status from public.usuario_empresas where id=$1',[targetB])).rows[0].status,'ativo')
    await db.exec('ROLLBACK TO SAVEPOINT audit_failure; RELEASE SAVEPOINT audit_failure')
    assert.deepEqual(await snapshot(),primary)
    console.log('PASS: membership revocation closes public/private legacy bypass and primary view/reads; secondary remains independent, trial readonly and audit rollback enforced')

    const rpcCases=[
      ["admin_usuario_alterar_status($1,'inativo','Legacy status valid')",[target]],
      ["admin_usuario_alterar_unidade($1,null,'Legacy unit valid')",[target]],
      ["admin_usuario_alterar_perfil($1,$2,'remover','Legacy profile valid')",[target,profileA]],
      ["admin_empresa_atualizar('Primary edited',null,null,'Legacy company valid')",[]],
      ["admin_unidade_salvar(null,'Legacy unit',null,true,'Legacy unit valid')",[]],
      ["admin_setor_salvar(null,$1,'Legacy sector',null,true,'Legacy sector valid')",[unitA]],
      ["admin_perfil_criar('Legacy profile',null,'{}'::uuid[],'Legacy profile valid')",[]],
      ["admin_perfil_atualizar($1,'Primary renamed',null,true,array(select id from public.permissoes),'Legacy profile valid')",[profileA]],
    ];
    for(const [expr,args] of rpcCases)for(const schema of ['public','private']){
      await db.exec('SAVEPOINT legacy_valid'); const before=await snapshot();await auth(); await query('select '+schema+'.'+expr,args);await db.exec('RESET ROLE');
      const after=await snapshot();assert.deepEqual(after.identities,before.identities);assert.deepEqual(after.legacy,before.legacy);
      await db.exec('ROLLBACK TO SAVEPOINT legacy_valid;RELEASE SAVEPOINT legacy_valid');
    }
    console.log('PASS08: all8 public/private legacy wrappers execute valid operations through canonical DML; global identity and legacy links remain unchanged');
    await db.exec('SAVEPOINT all_legacy_revoke');await query("update public.usuario_empresas set status='bloqueado' where usuario_id=$1 and empresa_id=$2",[actor,A]);await auth();
    for(const [expr,args] of rpcCases)for(const schema of ['public','private'])await fails('select '+schema+'.'+expr,args);
    await db.exec('RESET ROLE;ROLLBACK TO SAVEPOINT all_legacy_revoke;RELEASE SAVEPOINT all_legacy_revoke');
    console.log('PASS08: all8 public/private legacy wrappers deny canonical primary revocation');
    await db.exec('SAVEPOINT quota08');
    assert.equal(Number((await query('select usuarios_ativos from private.consumo_plano_empresa($1)',[A])).rows[0].usuarios_ativos),3);
    await auth();await query("select public.admin_usuario_alterar_status($1,'inativo','Canonical quota deactivation')",[target]);await db.exec('RESET ROLE');
    assert.equal(Number((await query('select usuarios_ativos from private.consumo_plano_empresa($1)',[A])).rows[0].usuarios_ativos),2);
    assert.equal(Number((await query('select usuarios_ativos from private.consumo_plano_empresa($1)',[B])).rows[0].usuarios_ativos),2);
    assert.equal((await query('select status from public.usuarios where id=$1',[target])).rows[0].status,'ativo');
    await db.exec('ROLLBACK TO SAVEPOINT quota08;RELEASE SAVEPOINT quota08');console.log('PASS08: canonical primary deactivation releases quota despite active legacy identity; secondary quota unchanged');

    // Exact deployed metadata verifier, exercised against the cumulative 32-state.
    await db.exec('CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text primary key)')
    for(const file of(await readdir(new URL('../supabase/migrations',import.meta.url))).sort()) {
      await query('insert into supabase_migrations.schema_migrations(version) values($1)',[file.slice(0,14)])
    }
    const metadata=(await query(await readFile(new URL('./sql/verify-tenant-admin.sql',import.meta.url),'utf8'))).rows
    assert.deepEqual(metadata[0],Object.fromEntries(administrationChecks.map(name=>[name,true])))
    verifyAdministration(metadata)
    assert.equal(Object.keys(metadata[0]).length,administrationChecks.length)
    for(const [change,check] of [
      ['GRANT UPDATE(status) ON public.usuarios TO bpf_tenant_admin','administracao_role'],
      ['GRANT INSERT(usuario_id) ON public.usuario_perfis TO bpf_tenant_admin','administracao_role'],
      ['GRANT bpf_tenant_admin TO postgres WITH INHERIT FALSE,SET TRUE;SET LOCAL ROLE bpf_tenant_admin;GRANT EXECUTE ON FUNCTION private.admin_empresa_tenant(uuid,text,text,text,text) TO PUBLIC;RESET ROLE','administracao_contratos'],
      ['ALTER TABLE public.usuario_empresas DISABLE ROW LEVEL SECURITY','administracao_rls'],
    ]) {
      await db.exec('SAVEPOINT metadata_drift')
      await db.exec(change)
      assert.equal((await query(await readFile(new URL('./sql/verify-tenant-admin.sql',import.meta.url),'utf8'))).rows[0][check],false)
      await db.exec('ROLLBACK TO SAVEPOINT metadata_drift;RELEASE SAVEPOINT metadata_drift')
    }

    await db.exec(`ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;
      ALTER TABLE auth.users ADD COLUMN banned_until timestamptz;
      ALTER TABLE auth.users ADD COLUMN deleted_at timestamptz;
      UPDATE auth.users SET email_confirmed_at=now()`)
    const qaSql=await secondarySql(repositoryRoot,'scripts/sql/provision-secondary-qa.sql','admin@test.invalid')
    const inspectSql=await secondarySql(repositoryRoot,'scripts/sql/inspect-secondary-qa.sql','admin@test.invalid')
    assert.equal(classifySecondary((await query(inspectSql)).rows).kind,'eligible')
    await db.exec(`SAVEPOINT secondary_audit;
      CREATE FUNCTION pg_temp.fail_secondary_audit() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF new.acao='workspace.qa_secundario_preparado' THEN RAISE EXCEPTION 'injected secondary audit'; END IF; RETURN new; END $$;
      CREATE TRIGGER fail_secondary_audit BEFORE INSERT ON public.auditoria_eventos FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_secondary_audit()`)
    await fails(qaSql,[],'P0001')
    assert.equal(classifySecondary((await query(inspectSql)).rows).kind,'eligible')
    await db.exec('ROLLBACK TO SAVEPOINT secondary_audit; RELEASE SAVEPOINT secondary_audit')
    const preservedPrimary=await snapshot()
    await db.exec(qaSql)
    const secondary=classifySecondary((await query(inspectSql)).rows)
    assert.equal(secondary.kind,'ready')
    assert.deepEqual(await snapshot(),preservedPrimary)
    const beforeReplay=(await query("select to_jsonb(q) as ledger from public.saas_provisionamentos q where chave_idempotencia='bpf:qa-secondary:v1'")).rows[0].ledger
    await db.exec(qaSql)
    assert.deepEqual((await query("select to_jsonb(q) as ledger from public.saas_provisionamentos q where chave_idempotencia='bpf:qa-secondary:v1'")).rows[0].ledger,beforeReplay)
    await auth()
    assert.equal((await query('select * from public.meu_contexto_empresa($1)',[secondary.row.empresa_id])).rows[0].empresa_id,secondary.row.empresa_id)
    assert.equal((await query("select public.admin_contexto_ler($1,'usuarios') as page",[secondary.row.empresa_id])).rows[0].page.count,1)
    await query("select public.admin_unidade_tenant($1,null,'SECONDARY TESTE',null,true,'Secondary unit validation')",[secondary.row.empresa_id])
    await db.exec('RESET ROLE')
    assert.deepEqual(await snapshot(),preservedPrimary)
    console.log('PASS: exact 32 metadata verifier, secondary QA atomic rollback/idempotency, canonical UI context and primary/identity/legacy preservation')
  } finally {await db.exec('ROLLBACK')}
}
