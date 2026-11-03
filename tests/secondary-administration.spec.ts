import { expect, test, type Page } from '@playwright/test'
import { createClient } from '@supabase/supabase-js'
import { createConfiguracoesService } from '../src/modules/configuracoes/services/configuracoesService'

const A = 'a1000000-0000-0000-0000-000000000001'
const B = 'a1000000-0000-0000-0000-000000000002'
const user = 'a2000000-0000-0000-0000-000000000001'
const target = 'a2000000-0000-0000-0000-000000000002'
const unit = 'a3000000-0000-0000-0000-000000000002'
const profile = 'a4000000-0000-0000-0000-000000000002'
const sector = 'a5000000-0000-0000-0000-000000000002'
const permission = 'a6000000-0000-0000-0000-000000000002'
const perms = ['dashboard.visualizar','configuracoes.visualizar','usuarios.gerenciar','usuarios.convidar','perfis.gerenciar','estrutura.gerenciar','auditoria.visualizar']
const companyName = (id: string) => id === A ? 'Primária A' : 'BPF TESTE B'
const context = (id: string) => ({ usuario_id: user,nome:'Admin multiempresa',email:'admin@example.test',ativo:true,status:'ativo',empresa_id:id,
  membership_id:id === A ? 'a7000000-0000-0000-0000-000000000001' : 'a7000000-0000-0000-0000-000000000002',
  nome_fantasia:companyName(id),razao_social:companyName(id),unidade_id:unit,unidade_nome:'Unidade TESTE',is_owner:true,perfis:['Admin local'],permissoes:perms })
const resources = (id: string): Record<string,unknown[]> => ({
  usuarios:[{id:target,membership_id:'a7000000-0000-0000-0000-000000000003',identidade_ativa:true,identidade_status:'ativo',nome:`Membro ${companyName(id)}`,email:'membro@example.test',empresa_id:id,unidade_id:unit,status:'ativo',ativo:true,created_at:'2026-10-29T12:00:00Z'}],
  empresas:[{id,nome_fantasia:companyName(id),razao_social:companyName(id),ativo:true}],
  unidades:[{id:unit,empresa_id:id,nome:`Unidade ${companyName(id)}`,codigo:'QA',ativo:true}],
  setores:[{id:sector,unidade_id:unit,nome:`Setor ${companyName(id)}`,codigo:'QA',ativo:true}],
  perfis:[{id:profile,empresa_id:id,nome:`Perfil ${companyName(id)}`,descricao:'Local',is_system:false,ativo:true}],
  permissoes:[{id:permission,codigo:'documentos.visualizar',modulo:'documentos',acao:'visualizar',descricao:'Consultar documentos'}],
  usuario_perfis:[{usuario_id:target,perfil_id:profile}],perfil_permissoes:[{perfil_id:profile,permissao_id:permission}],
  atores_auditoria:[{id:user,nome:'Admin multiempresa',email:'admin@example.test'}],
  auditoria_eventos:[{id:'a8000000-0000-0000-0000-000000000002',empresa_id:id,unidade_id:unit,ator_id:user,entidade:'membership',registro_id:target,acao:`evento.${id===A?'primaria':'teste'}`,antes:{},depois:{},justificativa:'Validação secundária',contexto:{},created_at:'2026-10-29T12:10:00Z'}],
})
type Call = {name:string;body:Record<string,unknown>}
async function setup(page: Page, options: {initial?:string;missingReader?:boolean;beforeRead?:(empresa:string)=>Promise<void>;beforeMutation?:(empresa:string)=>Promise<void>}={}) {
  const calls:Call[]=[]
  const denied:string[]=[]
  await page.addInitScript(({user,initial})=>{
    const identity={id:user,aud:'authenticated',role:'authenticated',email:'admin@example.test',app_metadata:{},user_metadata:{},created_at:'2026-10-29T12:00:00Z'}
    localStorage.setItem('sb-bpf-test-auth-token',JSON.stringify({access_token:'test-access-token',refresh_token:'test-refresh-token',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:identity}))
    localStorage.setItem(`bpf-manager:empresa-ativa:${user}`,initial)
  },{user,initial:options.initial??B})
  await page.route('https://bpf-test.supabase.co/**',async route=>{
    const req=route.request(),path=new URL(req.url()).pathname,name=path.split('/').pop()??''
    const body=req.postData()?req.postDataJSON() as Record<string,unknown>:{}
    calls.push({name,body})
    if(path.endsWith('/v_meu_contexto'))return route.fulfill({status:200,json:[context(A)]})
    if(name==='meus_vinculos')return route.fulfill({status:200,json:[A,B].map(id=>({membership_id:context(id).membership_id,empresa_id:id,nome_fantasia:companyName(id),razao_social:companyName(id),unidade_id:unit,unidade_nome:'Unidade TESTE',status:'ativo',is_owner:true}))})
    if(name==='meu_contexto_empresa')return route.fulfill({status:200,json:[context(String(body.p_empresa_id))]})
    if(name==='meu_workspace_comercial')return route.fulfill({status:200,json:[]})
    if(name==='admin_contexto_ler'&&!options.missingReader){
      await options.beforeRead?.(String(body.p_empresa_id))
      const rows=resources(String(body.p_empresa_id))[String(body.p_recurso)]
      if(rows)return route.fulfill({status:200,json:{data:rows,count:rows.length}})
    }
    if(name==='admin_empresa_tenant'){
      await options.beforeMutation?.(String(body.p_empresa_id))
      return route.fulfill({status:200,json:null})
    }
    if(name==='meu_plano_resumo')return route.fulfill({status:200,json:[{plano_id:profile,plano_codigo:'business',plano_nome:'Business TESTE',origem:'trial',usuarios_ativos:1,usuarios_ativos_max:75,unidades_ativas:1,unidades_max:10}]})
    if(name==='meu_plano_entitlements')return route.fulfill({status:200,json:[]})
    denied.push(path)
    return route.fulfill({status:404,json:{code:'PGRST202',message:'Unsupported test route'}})
  })
  return {calls,denied}
}

test('Configurações lê todos os recursos na TESTE B mantendo contexto primário A distinto',async({page})=>{
  const fixture=await setup(page)
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(B)
  await expect(page.getByRole('heading',{name:'Membro BPF TESTE B'})).toBeVisible()
  await page.getByRole('button',{name:'Perfis e Permissões',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Perfil BPF TESTE B'})).toBeVisible()
  await page.getByRole('button',{name:'Estrutura',exact:true}).click()
  await expect(page.getByLabel('Razão social')).toHaveValue('BPF TESTE B')
  await page.getByRole('button',{name:'Auditoria',exact:true}).click()
  await expect(page.getByText('evento.teste',{exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Plano e uso',exact:true}).click()
  await expect(page.getByText('Business TESTE',{exact:true})).toBeVisible()
  const readers=fixture.calls.filter(c=>c.name==='admin_contexto_ler')
  expect(new Set(readers.map(c=>c.body.p_recurso))).toEqual(new Set(Object.keys(resources(B))))
  expect(readers.every(c=>c.body.p_empresa_id===B)).toBe(true)
  expect(fixture.calls.filter(c=>c.name.startsWith('meu_plano_')).every(c=>c.body.p_empresa_id===B)).toBe(true)
  expect(fixture.denied).toEqual([])
})

test('RPC administrativa ausente mostra erro sem recorrer a tabelas ou comandos antigos',async({page})=>{
  const fixture=await setup(page,{missingReader:true})
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByRole('alert')).toContainText('Não foi possível carregar os dados administrativos')
  expect(fixture.denied.length).toBeGreaterThan(0)
  expect(fixture.denied.every(path=>path.endsWith('/rpc/admin_contexto_ler'))).toBe(true)
})

test('resposta administrativa atrasada da empresa A não substitui os dados de B após troca',async({page})=>{
  let release:()=>void=()=>{}
  const pending=new Promise<void>(resolve=>{release=resolve})
  const fixture=await setup(page,{initial:A,beforeRead:async empresa=>{if(empresa===A)await pending}})
  await page.goto('/configuracoes?secao=usuarios')
  await expect.poll(()=>fixture.calls.some(c=>c.name==='admin_contexto_ler'&&c.body.p_empresa_id===A)).toBe(true)
  await page.getByLabel('Empresa ativa').selectOption(B)
  await expect(page.getByRole('heading',{name:'Membro BPF TESTE B'})).toBeVisible()
  release()
  await expect(page.getByRole('heading',{name:'Membro Primária A'})).toHaveCount(0)
  await expect(page.getByRole('heading',{name:'Membro BPF TESTE B'})).toBeVisible()
  expect(fixture.denied).toEqual([])
})

test('todas as mutations enviam explicitamente tenant B após revalidação canônica',async()=>{
  const calls:Call[]=[]
  const client=createClient('https://bpf-test.supabase.co','test-key',{auth:{persistSession:false},global:{fetch:async(input,init)=>{
    const name=String(input).split('/').pop()??''
    const body=JSON.parse(typeof init?.body==='string'?init.body:'{}') as Record<string,unknown>
    calls.push({name,body})
    let result:unknown
    if(name==='meu_contexto_empresa')result=[context(B)]
    else if(['admin_usuario_status_tenant','admin_usuario_unidade_tenant','admin_usuario_perfil_tenant','admin_empresa_tenant'].includes(name))result=null
    else if(['admin_perfil_tenant','admin_unidade_tenant','admin_setor_tenant'].includes(name))result=profile
    else if(name==='admin-invite-user')result={userId:target,email:'novo@example.test',empresaId:B}
    else return new Response(JSON.stringify({code:'PGRST202'}),{status:404,headers:{'content-type':'application/json'}})
    return new Response(JSON.stringify(result),{headers:{'content-type':'application/json'}})
  }}})
  const svc=createConfiguracoesService(client),scope={usuarioId:user,empresaId:B},reason='Validação em empresa secundária'
  await svc.alterarStatus(scope,target,'bloqueado',reason)
  await svc.alterarUnidade(scope,target,unit,reason)
  await svc.alterarPerfil(scope,target,profile,'atribuir',reason)
  await svc.alterarPerfil(scope,target,profile,'remover',reason)
  await svc.perfilCriar(scope,'Perfil QA','Local',[permission],reason)
  await svc.perfilAtualizar(scope,profile,'Perfil QA','Local',true,[permission],reason)
  await svc.empresaAtualizar(scope,'BPF TESTE B','TESTE','',reason)
  await svc.unidadeSalvar(scope,null,'Segunda unidade','QA2',true,reason)
  await svc.unidadeSalvar(scope,unit,'Unidade QA','QA',true,reason)
  await svc.setorSalvar(scope,null,unit,'Setor QA','QA',true,reason)
  await svc.setorSalvar(scope,sector,unit,'Setor QA','QA',true,reason)
  await svc.convidarUsuario(scope,{email:'novo@example.test',nome:'Convidado',unidadeId:unit,perfilIds:[profile],justificativa:reason})
  expect(calls.filter(c=>c.name==='meu_contexto_empresa')).toHaveLength(12)
  const mutations=calls.filter(c=>c.name!=='meu_contexto_empresa')
  expect(mutations).toHaveLength(12)
  expect(mutations.every(c=>(c.name==='admin-invite-user'?c.body.empresaId:c.body.p_empresa_id)===B)).toBe(true)
  for(let i=0;i<calls.length;i+=2){expect(calls[i].name).toBe('meu_contexto_empresa');expect(calls[i].body.p_empresa_id).toBe(B)}
})


test('sucesso tardio de mutation A desmontada não atualiza contexto nem apaga edição em B',async({page})=>{
  let release:()=>void=()=>{}
  const pending=new Promise<void>(resolve=>{release=resolve})
  const fixture=await setup(page,{initial:A,beforeMutation:async empresa=>{if(empresa===A)await pending}})
  await page.goto('/configuracoes?secao=estrutura')
  await page.getByLabel('Razão social').fill('Alteração da Primária A')
  await page.getByLabel('Justificativa',{exact:true}).fill('Alteração autorizada na primária')
  await page.getByRole('button',{name:'Salvar empresa',exact:true}).click()
  await expect.poll(()=>fixture.calls.some(c=>c.name==='admin_empresa_tenant'&&c.body.p_empresa_id===A)).toBe(true)
  await page.getByLabel('Empresa ativa').selectOption(B)
  await expect(page.getByLabel('Razão social')).toHaveValue('BPF TESTE B')
  await page.getByLabel('Razão social').fill('Edição ainda não salva em B')
  const bootstrapCount=fixture.calls.filter(c=>c.name==='v_meu_contexto').length
  const response=page.waitForResponse(r=>r.url().endsWith('/rpc/admin_empresa_tenant'))
  release()
  await (await response).finished()
  await page.evaluate(()=>new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve()))))
  await expect(page.getByLabel('Razão social')).toHaveValue('Edição ainda não salva em B')
  expect(fixture.calls.filter(c=>c.name==='v_meu_contexto')).toHaveLength(bootstrapCount)
  expect(fixture.denied).toEqual([])
})
