import { expect, test, type Page } from '@playwright/test'

const user = { id: 'c1000000-0000-0000-0000-000000000001', aud: 'authenticated', role: 'authenticated', email: 'docs@example.test', app_metadata: {}, user_metadata: {}, created_at: '2026-10-15T12:00:00Z' }
const companyA = 'c2000000-0000-0000-0000-000000000001'
const companyB = 'c2000000-0000-0000-0000-000000000002'
const currentUnit = 'c3000000-0000-0000-0000-000000000001'
const otherUnit = 'c3000000-0000-0000-0000-000000000002'
const allPermissions = ['dashboard.visualizar', 'documentos.visualizar', 'documentos.criar', 'documentos.editar', 'documentos.aprovar']
const document = {
  documento_id: 'c4000000-0000-0000-0000-000000000001', empresa_id: companyA, unidade_id: otherUnit,
  codigo: 'POP-OUTRA', titulo: 'Documento de outra unidade', tipo: 'POP', ativo: true,
  versao_id: 'c5000000-0000-0000-0000-000000000001', versao_numero: 1, status: 'rascunho',
  descricao: 'Texto original preservado', revisao_prevista_em: '2027-01-01', autor_id: user.id,
  revisor_id: null, aprovador_id: null, vigencia_inicio: null, updated_at: '2026-10-15T12:00:00Z',
  vigente_numero: null as number | null, vigente_revisao_prevista_em: null as string | null,
}
const historyVersion = (doc: typeof document) => ({ ...doc, numero: doc.versao_numero, motivo_revisao: null, revisado_em: null, enviado_revisao_em: null, enviado_aprovacao_em: null, aprovado_em: null, obsoleto_em: null })

type MockOptions = { permissions?: string[]; readonly?: boolean; commercialError?: boolean; multi?: boolean }
async function setup(page: Page, options: MockOptions = {}) {
  await page.addInitScript(user => {
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({ access_token: 'test-token', refresh_token: 'test-refresh', expires_at: Math.floor(Date.now() / 1000) + 3600, expires_in: 3600, token_type: 'bearer', user }))
  }, user)
  const state = {
    documents: [{ ...document }], versions: [historyVersion(document)],
    calls: [] as { name: string; body: Record<string, unknown> }[],
    failList: false, failHistory: false, failWrite: false, failCommercial: options.commercialError ?? false,
    delayHistory: null as Promise<void> | null, delayList: null as Promise<void> | null,
    delayTenant: null as Promise<void> | null,
  }
  const context = (company: string) => ({ usuario_id: user.id, membership_id: `membership-${company}`, nome: 'Qualidade', email: user.email, ativo: true, status: 'ativo', empresa_id: company, nome_fantasia: company === companyA ? 'Empresa A' : 'Empresa B', razao_social: 'Empresa', unidade_id: currentUnit, unidade_nome: 'Unidade atual', is_owner: false, perfis: ['Qualidade'], permissoes: options.permissions ?? allPermissions })
  await page.route('https://bpf-test.supabase.co/**', async route => {
    const name = new URL(route.request().url()).pathname.split('/').at(-1)!
    const body = route.request().postDataJSON() ?? {}
    const ok = (json: unknown) => route.fulfill({ status: 200, json })
    const fail = () => route.fulfill({ status: 400, json: { code: '42501', message: 'Operacao negada' } })
    if (name === 'v_meu_contexto') return ok([context(companyA)])
    if (name === 'meus_vinculos') return ok((options.multi ? [companyA, companyB] : [companyA]).map(company => ({ ...context(company), status: 'ativo' })))
    if (name === 'meu_contexto_empresa') {
      const response = [context(body.p_empresa_id)]
      const delay = state.delayTenant
      state.delayTenant = null
      if (delay) await delay
      return ok(response)
    }
    if (name === 'meu_workspace_comercial') return state.failCommercial ? fail() : ok([{ empresa_id: body.p_empresa_id, plano_codigo: 'basic', plano_nome: 'Basic', assinatura_status: options.readonly ? 'expired' : 'active', modo_acesso: options.readonly ? 'somente_leitura' : 'normal', onboarding_status: 'concluido', onboarding_etapa: 'concluido' }])
    if (name === 'documentos_listar') {
      const response = body.p_empresa_id === companyA ? structuredClone(state.documents) : []
      const delay = state.delayList
      state.delayList = null
      if (delay) await delay
      return state.failList ? fail() : ok(response)
    }
    if (name === 'documento_historico') {
      const response = structuredClone(state.versions)
      if (state.delayHistory) await state.delayHistory
      return state.failHistory ? fail() : ok(response)
    }
    if (name.startsWith('documento_')) {
      state.calls.push({ name, body })
      if (state.failWrite) return fail()
      if (name === 'documento_rascunho_atualizar') {
        state.documents[0] = { ...state.documents[0], titulo: body.p_titulo, tipo: body.p_tipo, unidade_id: body.p_unidade_id, descricao: body.p_descricao }
        state.versions[0] = historyVersion(state.documents[0])
      } else if (name === 'documento_transicionar') {
        state.documents[0].status = body.p_status_destino
        if (body.p_status_destino === 'vigente') {
          state.documents[0].vigente_numero = state.documents[0].versao_numero
          state.versions.slice(1).forEach(v => { if (v.status === 'vigente') v.status = 'obsoleto' })
        }
        state.versions[0] = historyVersion(state.documents[0])
      } else if (name === 'documento_iniciar_revisao') {
        state.documents[0] = { ...state.documents[0], versao_id: 'c5000000-0000-0000-0000-000000000002', versao_numero: 2, status: 'rascunho', vigente_numero: 1 }
        state.versions.unshift(historyVersion(state.documents[0]))
      }
      return ok(null)
    }
    return ok([])
  })
  return state
}

async function confirm(page: Page, action: string) {
  await page.getByRole('button', { name: action, exact: true }).click()
  await page.getByLabel('Justificativa').fill('Justificativa tecnica controlada')
  await page.getByRole('button', { name: 'Confirmar', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Confirmar ação documental' })).toHaveCount(0)
}

test('preserva unidade original e envia versao esperada na edicao', async ({ page }) => {
  const state = await setup(page)
  await page.goto('/documentos')
  await page.getByRole('button', { name: 'Editar POP-OUTRA' }).click()
  await expect(page.getByLabel('Escopo')).toHaveValue(otherUnit)
  await page.getByLabel('Título').fill('Titulo atualizado')
  await page.getByRole('button', { name: 'Salvar rascunho' }).click()
  await expect(page.getByText('Rascunho atualizado.', { exact: true })).toBeVisible()
  await expect(page.getByText('POP-OUTRA · Titulo atualizado')).toBeVisible()
  expect(state.calls[0]).toMatchObject({ name: 'documento_rascunho_atualizar', body: { p_unidade_id: otherUnit, p_versao_id: document.versao_id } })
})

test('workflow completo preserva v1 vigente e evidencia historica durante v2', async ({ page }) => {
  const state = await setup(page)
  await page.goto('/documentos')
  for (const action of ['Enviar para revisão', 'Concluir revisão', 'Aprovar', 'Publicar']) await confirm(page, action)
  await expect(page.getByRole('button', { name: 'Iniciar revisão', exact: true })).toBeVisible()
  await confirm(page, 'Iniciar revisão')
  await expect(page.getByText('v1 vigente', { exact: true })).toBeVisible()
  await expect(page.locator('.documents-metrics article').filter({ hasText: 'Vigentes' }).locator('strong')).toHaveText('1')
  await page.getByRole('button', { name: 'Editar POP-OUTRA' }).click()
  await page.getByLabel('Título').fill('Titulo exclusivo v2')
  await page.getByLabel('Descrição').fill('Conteudo exclusivo v2')
  await page.getByRole('button', { name: 'Salvar rascunho' }).click()
  await page.getByRole('button', { name: 'Histórico de POP-OUTRA', exact: true }).click()
  const history = page.getByRole('region', { name: 'Histórico de POP-OUTRA', exact: true })
  await expect(history.getByText('Texto original preservado', { exact: true })).toBeVisible()
  await expect(history.getByText('Conteudo exclusivo v2', { exact: true })).toBeVisible()
  for (const action of ['Enviar para revisão', 'Concluir revisão', 'Aprovar', 'Publicar']) await confirm(page, action)
  expect(state.calls.filter(c => c.name === 'documento_transicionar').at(-1)?.body).toMatchObject({ p_versao_id: 'c5000000-0000-0000-0000-000000000002', p_status_destino: 'vigente' })
  await page.getByRole('button', { name: 'Histórico de POP-OUTRA', exact: true }).click()
  await expect(history.getByText('Obsoleto', { exact: true })).toBeVisible()
})

for (const role of ['viewer', 'editor', 'approver', 'readonly'] as const) {
  test(`acoes respeitam perfil ${role}`, async ({ page }) => {
    const permissions = role === 'readonly' ? allPermissions : ['dashboard.visualizar', 'documentos.visualizar', ...(role === 'editor' ? ['documentos.editar'] : role === 'approver' ? ['documentos.aprovar'] : [])]
    const state = await setup(page, { permissions, readonly: role === 'readonly' })
    state.documents[0].status = role === 'approver' ? 'aguardando_aprovacao' : 'rascunho'
    await page.goto('/documentos')
    await expect(page.getByRole('button', { name: 'Histórico de POP-OUTRA' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Novo documento' })).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Editar POP-OUTRA' })).toHaveCount(role === 'editor' ? 1 : 0)
    await expect(page.getByRole('button', { name: 'Enviar para revisão' })).toHaveCount(role === 'editor' ? 1 : 0)
    await expect(page.getByRole('button', { name: 'Aprovar', exact: true })).toHaveCount(role === 'approver' ? 1 : 0)
    await page.getByRole('button', { name: 'Histórico de POP-OUTRA' }).click()
    await expect(page.getByText('Texto original preservado', { exact: true })).toBeVisible()
    expect(state.calls).toHaveLength(0)
  })
}

test('URL direta e menu exigem documentos.visualizar', async ({ page }) => {
  await setup(page, { permissions: ['dashboard.visualizar', 'documentos.editar'] })
  await page.goto('/documentos')
  await expect(page).toHaveURL(/\/dashboard$/)
  await expect(page.locator('a[href="/documentos"]')).toHaveCount(0)
})

test('falhas de lista, historico e escrita nao viram vazio ou sucesso', async ({ page }) => {
  const state = await setup(page)
  state.failList = true
  await page.goto('/documentos')
  await expect(page.getByRole('alert')).toContainText('Não foi possível carregar')
  await expect(page.getByText('Nenhum documento cadastrado')).toHaveCount(0)
  state.failList = false
  await page.getByRole('button', { name: 'Atualizar documentos' }).click()
  await expect(page.getByText('POP-OUTRA · Documento de outra unidade')).toBeVisible()
  state.failHistory = true
  await page.getByRole('button', { name: 'Histórico de POP-OUTRA' }).click()
  await expect(page.getByText('Não foi possível carregar o histórico do documento.')).toBeVisible()
  state.failWrite = true
  await page.getByRole('button', { name: 'Editar POP-OUTRA' }).click()
  await page.getByRole('button', { name: 'Salvar rascunho' }).click()
  await expect(page.getByText('Não foi possível salvar o documento.')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Editar rascunho' })).toBeVisible()
})

test('erro comercial bloqueia escrita e permite consulta e recuperacao', async ({ page }) => {
  const state = await setup(page, { commercialError: true })
  await page.goto('/documentos')
  await expect(page.getByRole('alert')).toContainText('disponibilidade de escrita')
  await expect(page.getByRole('button', { name: 'Editar POP-OUTRA' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Histórico de POP-OUTRA' })).toBeVisible()
  state.failCommercial = false
  await page.getByRole('button', { name: 'Atualizar contexto' }).click()
  await expect(page.getByRole('button', { name: 'Editar POP-OUTRA' })).toBeVisible()
})

test('respostas de lista e historico do tenant anterior nao reaparecem apos troca', async ({ page }) => {
  const state = await setup(page, { multi: true })
  await page.goto('/documentos')
  await expect(page.getByRole('button', { name: 'Histórico de POP-OUTRA' })).toBeVisible()
  let releaseHistory!: () => void
  let releaseList!: () => void
  state.delayHistory = new Promise(resolve => { releaseHistory = resolve })
  state.delayList = new Promise(resolve => { releaseList = resolve })
  const historyRequest = page.waitForRequest('**/rpc/documento_historico')
  await page.getByRole('button', { name: 'Histórico de POP-OUTRA' }).click()
  await historyRequest
  const listRequest = page.waitForRequest('**/rpc/documentos_listar')
  await page.getByRole('button', { name: 'Atualizar documentos' }).click()
  await listRequest
  await page.getByLabel('Empresa ativa').selectOption(companyB)
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(companyB)
  await expect(page.getByText('Nenhum documento cadastrado')).toBeVisible()
  const historyResponse = page.waitForResponse('**/rpc/documento_historico')
  const listResponse = page.waitForResponse('**/rpc/documentos_listar')
  releaseHistory(); releaseList()
  await Promise.all([historyResponse, listResponse])
  await expect(page.getByText('POP-OUTRA · Documento de outra unidade')).toHaveCount(0)
  await expect(page.getByRole('region', { name: 'Histórico de POP-OUTRA' })).toHaveCount(0)
  expect(state.calls).toHaveLength(0)
})

for (const width of [375, 768, 1440]) {
  test(`documentos responsivo em ${width}px preserva prazos e conteudo longo`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    const state = await setup(page)
    state.documents[0].titulo = 'Documento'.repeat(20)
    await page.goto('/documentos')
    await expect(page.getByRole('button', { name: 'Histórico de POP-OUTRA' })).toBeVisible()
    await expect(page.getByText('01/01/2027', { exact: true })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  })
}

test('refresh de sessao concorrente preserva tenant solicitado e descarta resposta antiga', async ({ page }) => {
  const state = await setup(page, { multi: true })
  await page.goto('/documentos')
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(companyA)
  let release!: () => void
  state.delayTenant = new Promise(resolve => { release = resolve })
  const first = page.waitForRequest('**/rpc/meu_contexto_empresa')
  await page.getByLabel('Empresa ativa').selectOption(companyB)
  await first
  const refreshed = page.waitForResponse('**/rpc/meu_contexto_empresa')
  await page.evaluate(() => {
    const channel = new BroadcastChannel('sb-bpf-test-auth-token')
    channel.postMessage({ event: 'TOKEN_REFRESHED', session: JSON.parse(localStorage.getItem('sb-bpf-test-auth-token')!) })
    channel.close()
  })
  await refreshed
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(companyB)
  const oldResponse = page.waitForResponse('**/rpc/meu_contexto_empresa')
  release()
  await oldResponse
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(companyB)
  expect(await page.evaluate(userId => localStorage.getItem(`bpf-manager:empresa-ativa:${userId}`), user.id)).toBe(companyB)
})
