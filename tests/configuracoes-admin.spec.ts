import { expect, test, type Page } from '@playwright/test'

const companyId = '10000000-0000-0000-0000-000000000001'
const userId = '20000000-0000-0000-0000-000000000001'
const unitId = '30000000-0000-0000-0000-000000000001'
const profileId = '40000000-0000-0000-0000-000000000001'
const sectorId = '50000000-0000-0000-0000-000000000001'
const permissions = [
  'dashboard.visualizar', 'configuracoes.visualizar', 'configuracoes.gerenciar',
  'usuarios.gerenciar', 'usuarios.convidar', 'perfis.gerenciar', 'estrutura.gerenciar', 'auditoria.visualizar',
]
const context = { usuario_id: userId, nome: 'Admin QA', email: 'admin@example.test', ativo: true, status: 'ativo', empresa_id: companyId,
  nome_fantasia: 'Empresa QA', razao_social: 'Empresa QA Ltda', unidade_id: unitId, unidade_nome: 'Matriz', perfis: ['Administrador'], permissoes: permissions }

async function setup(page: Page) {
  const requests: { path: string; method: string; body: string | null }[] = []
  await page.addInitScript(({ userId }) => {
    const user = { id: userId, aud: 'authenticated', role: 'authenticated', email: 'admin@example.test', app_metadata: {}, user_metadata: {}, created_at: '2026-09-18T12:00:00Z' }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({ access_token: 'test-access-token', refresh_token: 'test-refresh-token', expires_at: Math.floor(Date.now() / 1000) + 3600, expires_in: 3600, token_type: 'bearer', user }))
  }, { userId })
  await page.route('https://bpf-test.supabase.co/**', async route => {
    const request = route.request()
    const url = new URL(request.url())
    requests.push({ path: url.pathname, method: request.method(), body: request.postData() })
    if (url.pathname.startsWith('/functions/v1/')) return route.fulfill({ status: 200, json: { userId: '90000000-0000-0000-0000-000000000001', email: 'novo@example.test', empresaId: companyId } })
    if (!url.pathname.startsWith('/rest/v1/')) return route.fulfill({ status: 200, json: {} })
    if (url.pathname.endsWith('/rpc/meu_plano_resumo')) return route.fulfill({ status: 200, json: [{
      plano_id: '80000000-0000-0000-0000-000000000001', plano_codigo: 'basic', plano_nome: 'Basic', origem: 'manual',
      usuarios_ativos: 1, usuarios_ativos_max: 10, unidades_ativas: 1, unidades_max: 1,
    }], headers: { 'content-type': 'application/json' } })
    if (url.pathname.endsWith('/rpc/meu_plano_entitlements')) return route.fulfill({ status: 200, json: [
      { plano_id: '80000000-0000-0000-0000-000000000001', plano_codigo: 'basic', plano_nome: 'Basic', plano_ativo: true, origem: 'manual', chave: 'usuarios_ativos.max', tipo: 'inteiro', valor_booleano: null, valor_inteiro: 10, valor_texto: null },
      { plano_id: '80000000-0000-0000-0000-000000000001', plano_codigo: 'basic', plano_nome: 'Basic', plano_ativo: true, origem: 'manual', chave: 'unidades.max', tipo: 'inteiro', valor_booleano: null, valor_inteiro: 1, valor_texto: null },
    ], headers: { 'content-type': 'application/json' } })
    if (url.pathname.includes('/rpc/')) return route.fulfill({ status: 200, json: null, headers: { 'content-type': 'application/json' } })
    const table = url.pathname.split('/').pop() ?? ''
    const data: Record<string, unknown[]> = {
      v_meu_contexto: [context],
      usuarios: [{ id: userId, nome: 'Admin QA', email: 'admin@example.test', empresa_id: companyId, unidade_id: unitId, status: 'ativo', ativo: true, created_at: '2026-09-18T12:00:00Z' }],
      empresas: [{ id: companyId, nome_fantasia: 'Empresa QA', razao_social: 'Empresa QA Ltda', cnpj: '00.000.000/0001-00', ativo: true }],
      unidades: [{ id: unitId, empresa_id: companyId, nome: 'Matriz', codigo: 'MTZ', ativo: true }],
      setores: [{ id: sectorId, unidade_id: unitId, nome: 'Qualidade', codigo: 'QLD', ativo: true }],
      perfis: [{ id: profileId, empresa_id: null, nome: 'Administrador', descricao: 'Perfil de sistema', is_system: true, ativo: true }],
      permissoes: [
        { id: '60000000-0000-0000-0000-000000000001', codigo: 'documentos.visualizar', modulo: 'documentos', acao: 'visualizar', descricao: 'Visualizar documentos' },
        { id: '60000000-0000-0000-0000-000000000002', codigo: 'auditoria.visualizar', modulo: 'auditoria', acao: 'visualizar', descricao: 'Visualizar auditoria' },
      ],
      usuario_perfis: [{ usuario_id: userId, perfil_id: profileId }],
      perfil_permissoes: [{ perfil_id: profileId, permissao_id: '60000000-0000-0000-0000-000000000002' }],
      auditoria_eventos: [{ id: '70000000-0000-0000-0000-000000000001', empresa_id: companyId, unidade_id: unitId, ator_id: userId,
        entidade: 'usuario', registro_id: userId, acao: 'usuario.status_alterado', antes: { status: 'inativo' }, depois: { status: 'ativo' },
        justificativa: 'QA reativação', contexto: { origem: 'rpc' }, created_at: '2026-09-18T12:10:00Z' }],
    }
    const rows = data[table] ?? []
    return route.fulfill({ status: 200, json: rows, headers: { 'content-type': 'application/json', 'content-range': `0-${Math.max(rows.length - 1, 0)}/${rows.length}`, 'access-control-expose-headers': 'content-range' } })
  })
  return requests
}

test('administrador pode abrir convite e envia tenant ativo pela Edge Function', async ({ page }) => {
  const requests = await setup(page)
  await page.goto('/configuracoes?secao=usuarios')
  await page.getByRole('button', { name: 'Convidar usuário' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Nome').fill('Novo Usuário')
  await dialog.getByLabel('E-mail').fill('novo@example.test')
  await dialog.getByRole('checkbox', { name: /Administrador/ }).check()
  await dialog.getByLabel('Justificativa').fill('Convite para equipe QA')
  await dialog.getByRole('button', { name: 'Enviar convite' }).click()
  await expect(dialog).toHaveCount(0)
  const invite = requests.find(item => item.path.endsWith('/functions/v1/admin-invite-user') && item.method === 'POST')
  expect(invite).toBeTruthy()
  expect(invite?.body).toContain(companyId)
})

test('plano e uso ficam visíveis com limites e consumo da empresa', async ({ page }) => {
  const requests = await setup(page)
  await page.goto('/configuracoes?secao=plano')
  await expect(page.getByRole('heading', { name: 'Plano e uso' })).toBeVisible()
  await expect(page.getByText('Basic', { exact: true })).toBeVisible()
  await expect(page.getByText('1 / 10', { exact: true })).toBeVisible()
  await expect(page.getByText('1 / 1', { exact: true })).toBeVisible()
  expect(requests.some(item => item.path.endsWith('/rest/v1/rpc/meu_plano_resumo'))).toBe(true)
  expect(requests.some(item => item.path.endsWith('/rest/v1/rpc/meu_plano_entitlements'))).toBe(true)
})

test('perfil customizado usa RPC e perfil de sistema permanece somente leitura', async ({ page }) => {
  const requests = await setup(page)
  await page.goto('/configuracoes?secao=perfis')
  await page.getByRole('button', { name: 'Novo perfil' }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Nome').fill('Qualidade Local')
  await dialog.getByLabel('Justificativa').fill('Perfil específico da unidade')
  await dialog.getByRole('button', { name: 'Criar perfil' }).click()
  await expect(dialog).toHaveCount(0)
  expect(requests.some(item => item.path.endsWith('/rest/v1/rpc/admin_perfil_criar') && item.method === 'POST')).toBe(true)
  await page.getByRole('button', { name: 'Ver permissões de Administrador' }).click()
  await expect(page.getByRole('button', { name: 'Salvar permissões' })).toBeDisabled()
})

test('estrutura e auditoria aparecem somente com permissões e carregam dados da empresa', async ({ page }) => {
  const requests = await setup(page)
  await page.goto('/configuracoes?secao=estrutura')
  await expect(page.getByRole('heading', { name: 'Estrutura organizacional' })).toBeVisible()
  await expect(page.getByText('Qualidade', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Auditoria', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Auditoria', exact: true })).toBeVisible()
  await expect(page.getByText('usuario.status_alterado')).toBeVisible()
  expect(requests.some(item => item.path.endsWith('/rest/v1/setores'))).toBe(true)
  expect(requests.some(item => item.path.endsWith('/rest/v1/auditoria_eventos'))).toBe(true)
})
