import { expect, test, type Page } from '@playwright/test'
import { navigationGroups } from '../src/lib/navigation'
import { hasPermission } from '../src/lib/permissions'
import { createConfiguracoesService } from '../src/modules/configuracoes/services/configuracoesService'
import { createClient } from '@supabase/supabase-js'
import type { MeuContexto } from '../src/types/auth'

const companyId = '10000000-0000-0000-0000-000000000001'
const userId = '20000000-0000-0000-0000-000000000001'
const unitId = '30000000-0000-0000-0000-000000000001'
const profileId = '40000000-0000-0000-0000-000000000001'
const allPermissions = [...navigationGroups.flatMap(group => group.items.map(item => item.permission)), 'usuarios.gerenciar', 'perfis.gerenciar', 'configuracoes.gerenciar']
const context: MeuContexto = { usuario_id: userId, nome: 'Ana Qualidade', email: 'ana@example.test', ativo: true, status: 'ativo', empresa_id: companyId, nome_fantasia: 'Empresa de teste', razao_social: 'Empresa de teste', unidade_id: unitId, unidade_nome: 'Unidade Principal', perfis: ['Administrador'], permissoes: allPermissions }
const baseUser = { id: userId, nome: 'Ana Qualidade', email: 'ana@example.test', empresa_id: companyId, unidade_id: unitId, status: 'ativo', ativo: true, created_at: '2026-09-15T12:00:00Z' }
const profiles = ['Administrador', 'Responsável Técnico', 'Qualidade', 'Supervisor', 'Operador', 'Auditor', 'Consulta'].map((nome, index) => ({ id: index === 0 ? profileId : `profile-${index}`, empresa_id: null, nome, descricao: `Perfil ${nome}`, is_system: true, ativo: true }))

async function setup(page: Page, permissions = allPermissions, options: { empty?: boolean; pending?: boolean; colleague?: boolean; fail?: boolean; delay?: number } = {}) {
  const errors: string[] = []
  const requests: { table: string; url: string; method: string }[] = []
  page.on('pageerror', error => errors.push(error.message))
  const current = { ...context, permissoes: permissions }
  await page.addInitScript(({ userId }) => {
    const user = { id: userId, aud: 'authenticated', role: 'authenticated', email: 'ana@example.test', app_metadata: {}, user_metadata: {}, created_at: '2026-09-15T12:00:00Z' }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({ access_token: 'test-access-token', refresh_token: 'test-refresh-token', expires_at: Math.floor(Date.now() / 1000) + 3600, expires_in: 3600, token_type: 'bearer', user }))
  }, { userId })
  await page.route('https://bpf-test.supabase.co/**', async route => {
    const url = new URL(route.request().url())
    const table = url.pathname.split('/').pop() ?? ''
    requests.push({ table, url: url.toString(), method: route.request().method() })
    if (!url.pathname.startsWith('/rest/v1/')) return route.fulfill({ status: 200, json: {} })
    if (table === 'usuarios' && options.delay) await new Promise(resolve => setTimeout(resolve, options.delay))
    if (table === 'usuarios' && options.fail) return route.fulfill({ status: 403, json: { message: 'Permission denied', code: '42501' } })
    const data: Record<string, unknown[]> = {
      v_meu_contexto: [current],
      usuarios: options.empty ? [] : [baseUser, ...(options.colleague ? [{ ...baseUser, id: 'colleague-user', nome: 'Maria Qualidade', email: 'maria@example.test' }] : []), ...(options.pending ? [{ ...baseUser, id: 'pending-user', nome: 'João Pendente', email: 'joao@example.test', status: 'pendente', ativo: false, unidade_id: null }] : [])],
      empresas: [{ id: companyId, nome_fantasia: 'Empresa de teste', razao_social: 'Empresa de teste' }],
      unidades: [{ id: unitId, empresa_id: companyId, nome: 'Unidade Principal', ativo: true }],
      perfis: profiles,
      permissoes: [{ id: 'permission-1', codigo: 'documentos.visualizar', modulo: 'documentos', acao: 'visualizar', descricao: 'Visualizar documentos' }, { id: 'permission-2', codigo: 'documentos.aprovar', modulo: 'documentos', acao: 'aprovar', descricao: 'Aprovar documentos' }],
      usuario_perfis: [{ usuario_id: userId, perfil_id: profileId }],
      perfil_permissoes: [{ perfil_id: profileId, permissao_id: 'permission-1' }],
    }
    const rows = data[table] ?? []
    return route.fulfill({ status: 200, json: rows, headers: { 'content-range': `0-${Math.max(rows.length - 1, 0)}/${rows.length}`, 'access-control-expose-headers': 'content-range' } })
  })
  return { errors, requests, options }
}

test('administrador mantém todos os módulos e navega por usuários e perfis', async ({ page }) => {
  const result = await setup(page, allPermissions, { colleague: true })
  await page.goto('/configuracoes')
  await expect(page.getByRole('heading', { name: 'Configurações', exact: true })).toBeVisible()
  await expect(page.locator('.desktop-sidebar .nav-link')).toHaveCount(17)
  await page.getByRole('navigation', { name: 'Seções de configurações' }).getByRole('button', { name: 'Usuários', exact: true }).click()
  await expect(page.getByText('Consulta restrita à sua empresa.')).toBeVisible()
  await expect(page.locator('.settings-user-card')).toHaveCount(2)
  await expect(page.getByRole('button', { name: 'Ver detalhes de Maria Qualidade' })).toBeVisible()
  await page.getByRole('button', { name: 'Ver detalhes de Ana Qualidade' }).click()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Salvar alterações' })).toBeDisabled()
  await expect(page.getByRole('dialog').getByLabel('Nome', { exact: true })).toBeDisabled()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Ver detalhes de Ana Qualidade' })).toBeFocused()
  await page.getByRole('button', { name: 'Perfis e Permissões', exact: true }).click()
  await expect(page.locator('.settings-profile-card')).toHaveCount(7)
  await page.getByRole('button', { name: 'Ver permissões de Administrador', exact: true }).click()
  await expect(page.getByRole('dialog').getByRole('checkbox', { name: /Visualizar/ })).toBeChecked()
  await expect(page.getByRole('dialog').getByRole('checkbox', { name: /Aprovar/ })).not.toBeChecked()
  await expect(page.getByRole('button', { name: 'Salvar permissões' })).toBeDisabled()
  expect(result.errors).toEqual([])
  expect(result.requests.every(request => request.method === 'GET')).toBe(true)
  expect(result.requests.filter(request => request.table === 'usuarios').every(request => new URL(request.url).searchParams.get('empresa_id') === `eq.${companyId}`)).toBe(true)
})

test('visibilidade não concede administração, nem por URL direta', async ({ page }) => {
  const result = await setup(page, ['configuracoes.visualizar', 'configuracoes.gerenciar'])
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByRole('heading', { name: 'Acesso não autorizado' })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Seções de configurações' }).getByRole('button')).toHaveCount(1)
  await page.goto('/configuracoes?secao=perfis')
  await expect(page.getByRole('heading', { name: 'Acesso não autorizado' })).toBeVisible()
  expect(result.requests.filter(request => request.table !== 'v_meu_contexto')).toEqual([])
})

test('sem configuracoes.visualizar a rota e o menu são bloqueados', async ({ page }) => {
  const result = await setup(page, ['dashboard.visualizar', 'usuarios.gerenciar', 'perfis.gerenciar'])
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page).toHaveURL(/\/dashboard$/)
  await expect(page.locator('.desktop-sidebar').getByRole('link', { name: 'Configurações' })).toHaveCount(0)
  expect(result.requests.filter(request => request.table !== 'v_meu_contexto')).toEqual([])
})

test('permissões de usuários e perfis são independentes', async ({ page }) => {
  const result = await setup(page, ['configuracoes.visualizar', 'perfis.gerenciar'])
  await page.goto('/configuracoes?secao=perfis')
  await expect(page.locator('.settings-profile-card')).toHaveCount(7)
  await expect(page.getByRole('navigation', { name: 'Seções de configurações' }).getByRole('button', { name: 'Usuários' })).toHaveCount(0)
  expect(result.requests.some(request => request.table === 'usuarios')).toBe(false)
})

test('carregamento, erro e nova tentativa não deixam tela branca', async ({ page }) => {
  const result = await setup(page, allPermissions, { fail: true, delay: 500 })
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByRole('heading', { name: 'Carregando dados…' })).toBeVisible()
  await expect(page.getByRole('alert')).toContainText('Não foi possível carregar')
  result.options.fail = false
  await page.getByRole('button', { name: 'Tentar novamente' }).click()
  await expect(page.getByRole('button', { name: 'Ver detalhes de Ana Qualidade' })).toBeVisible()
  expect(result.errors).toEqual([])
})

test('resposta vazia é diferente de falha e de filtro sem resultado', async ({ page }) => {
  await setup(page, allPermissions, { empty: true })
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByText('Nenhum cadastro foi retornado para seu acesso atual.')).toBeVisible()
  await expect(page.getByRole('alert')).toHaveCount(0)
})

test('filtros locais e detalhe pendente estão preparados sem conceder acesso', async ({ page }) => {
  await setup(page, allPermissions, { pending: true })
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.locator('.settings-user-card')).toHaveCount(2)
  await page.getByLabel('Nome ou e-mail').fill('joao')
  await page.getByLabel('Status', { exact: true }).selectOption('pendente')
  await page.getByLabel('Unidade', { exact: true }).selectOption('sem-unidade')
  await page.getByLabel('Perfil', { exact: true }).selectOption('sem-perfil')
  await expect(page.locator('.settings-user-card')).toHaveCount(1)
  await page.getByRole('button', { name: 'Ver detalhes de João Pendente' }).click()
  await expect(page.getByRole('dialog')).toContainText('Este cadastro aguarda aprovação')
  await expect(page.getByRole('button', { name: 'Ativar', exact: true })).toBeDisabled()
  await page.keyboard.press('Escape')
  await page.getByLabel('Nome ou e-mail').fill('inexistente')
  await expect(page.getByText('Nenhum usuário corresponde aos filtros selecionados.')).toBeVisible()
  await page.getByRole('button', { name: 'Limpar filtros' }).click()
  await expect(page.locator('.settings-user-card')).toHaveCount(2)
})

test('mudança de seção durante consulta não apresenta resposta antiga', async ({ page }) => {
  await setup(page, allPermissions, { delay: 800 })
  await page.goto('/configuracoes?secao=usuarios')
  await expect(page.getByRole('heading', { name: 'Carregando dados…' })).toBeVisible()
  await page.getByRole('button', { name: 'Perfis e Permissões', exact: true }).click()
  await expect(page.locator('.settings-profile-card')).toHaveCount(7)
  await expect(page.locator('.settings-user-card')).toHaveCount(0)
})

for (const width of [375, 768, 1440]) {
  test(`layout e modal sem overflow horizontal em ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 })
    await setup(page)
    await page.goto('/configuracoes?secao=usuarios')
    await page.getByRole('button', { name: 'Ver detalhes de Ana Qualidade' }).click()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    expect(await page.getByRole('dialog').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true)
    await page.keyboard.press('Escape')
    await page.getByRole('button', { name: 'Perfis e Permissões', exact: true }).click()
    await page.getByRole('button', { name: 'Ver permissões de Administrador', exact: true }).click()
    expect(await page.getByRole('dialog').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true)
    await page.screenshot({ path: `test-results/configuracoes-${width}.png`, fullPage: true })
  })
}

test('checagem compartilhada nega contexto inativo, bloqueado, sem empresa e sem permissão', () => {
  expect(hasPermission(context, 'usuarios.gerenciar')).toBe(true)
  for (const override of [{ ativo: false }, { status: 'pendente' as const }, { status: 'bloqueado' as const }, { empresa_id: null }, { permissoes: [] }]) {
    expect(hasPermission({ ...context, ...override }, 'usuarios.gerenciar')).toBe(false)
  }
  expect(hasPermission(null, 'usuarios.gerenciar')).toBe(false)
})

test('serviço nega contexto revogado antes de consultar tabelas administrativas', async () => {
  const paths: string[] = []
  const client = createClient('https://bpf-test.supabase.co', 'test-key', { auth: { persistSession: false }, global: { fetch: async input => {
    paths.push(String(input))
    return new Response(JSON.stringify([{ ...context, permissoes: ['configuracoes.visualizar'] }]), { headers: { 'content-type': 'application/json' } })
  } } })
  await expect(createConfiguracoesService(client).usuarios({ usuarioId: userId, empresaId: companyId }, new AbortController().signal)).rejects.toThrow('não está mais disponível')
  expect(paths).toHaveLength(1)
  expect(paths[0]).toContain('v_meu_contexto')
})

for (const scenario of [
  { name: 'empresa adulterada pelo cliente', scope: { usuarioId: userId, empresaId: '10000000-0000-0000-0000-000000000002' }, override: {} },
  { name: 'identidade adulterada pelo cliente', scope: { usuarioId: '20000000-0000-0000-0000-000000000002', empresaId: companyId }, override: {} },
  { name: 'status bloqueado', override: { status: 'bloqueado' as const } },
  { name: 'status inativo', override: { status: 'inativo' as const } },
  { name: 'cadastro inativo', override: { ativo: false } },
  { name: 'sem configuracoes.visualizar', override: { permissoes: ['usuarios.gerenciar'] } },
  { name: 'permissões revogadas por perfil inativo', override: { perfis: [], permissoes: [] } },
]) {
  test(`serviço recusa ${scenario.name} antes da leitura administrativa`, async () => {
    const paths: string[] = []
    const client = createClient('https://bpf-test.supabase.co', 'test-key', { auth: { persistSession: false }, global: { fetch: async input => {
      paths.push(String(input))
      return new Response(JSON.stringify([{ ...context, ...scenario.override }]), { headers: { 'content-type': 'application/json' } })
    } } })
    await expect(createConfiguracoesService(client).usuarios(scenario.scope ?? { usuarioId: userId, empresaId: companyId }, new AbortController().signal)).rejects.toThrow('não está mais disponível')
    expect(paths).toHaveLength(1)
    expect(paths[0]).toContain('v_meu_contexto')
  })
}

test('serviço pagina respostas acima do limite do servidor', async () => {
  const permissions = Array.from({ length: 501 }, (_, i) => ({ id: `permission-${i}`, codigo: `modulo.acao_${i}`, modulo: 'modulo', acao: `acao_${i}`, descricao: null }))
  const offsets: number[] = []
  const client = createClient('https://bpf-test.supabase.co', 'test-key', { auth: { persistSession: false }, global: { fetch: async input => {
    const url = new URL(String(input))
    const table = url.pathname.split('/').pop()
    const all = table === 'v_meu_contexto' ? [context] : table === 'permissoes' ? permissions : []
    const from = Number(url.searchParams.get('offset') ?? 0)
    if (table === 'permissoes') offsets.push(from)
    return new Response(JSON.stringify(all.slice(from, from + 500)), { headers: { 'content-type': 'application/json', 'content-range': `0-0/${all.length}` } })
  } } })
  const data = await createConfiguracoesService(client).perfis({ usuarioId: userId, empresaId: companyId }, new AbortController().signal)
  expect(data.permissoes).toHaveLength(501)
  expect(offsets).toEqual([0, 500])
})
