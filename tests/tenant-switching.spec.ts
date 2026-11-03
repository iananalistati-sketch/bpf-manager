import { expect, test } from '@playwright/test'
import { navigationGroups } from '../src/lib/navigation'

const userId = 'b3000000-0000-0000-0000-000000000001'
const companyA = 'b1000000-0000-0000-0000-000000000001'
const companyB = 'b1000000-0000-0000-0000-000000000002'
const membershipA = 'b6000000-0000-0000-0000-000000000001'
const membershipB = 'b6000000-0000-0000-0000-000000000002'
const dashboardPermission = navigationGroups.flatMap(group => group.items).find(item => item.path === '/dashboard')!.permission

const legacyContext = {
  usuario_id: userId,
  nome: 'Usuário Multiempresa',
  email: 'multi@example.test',
  ativo: true,
  status: 'ativo',
  empresa_id: companyA,
  nome_fantasia: 'Empresa A',
  razao_social: 'Empresa A',
  unidade_id: null,
  unidade_nome: null,
  perfis: ['Administrador'],
  permissoes: [dashboardPermission],
}

const memberships = [
  { membership_id: membershipA, empresa_id: companyA, nome_fantasia: 'Empresa A', razao_social: 'Empresa A', unidade_id: null, unidade_nome: null, status: 'ativo', is_owner: true },
  { membership_id: membershipB, empresa_id: companyB, nome_fantasia: 'Empresa B', razao_social: 'Empresa B', unidade_id: null, unidade_nome: null, status: 'ativo', is_owner: false },
]

const tenantContext = (empresaId: string) => ({
  ...legacyContext,
  membership_id: empresaId === companyA ? membershipA : membershipB,
  empresa_id: empresaId,
  nome_fantasia: empresaId === companyA ? 'Empresa A' : 'Empresa B',
  razao_social: empresaId === companyA ? 'Empresa A' : 'Empresa B',
  is_owner: empresaId === companyA,
})

test('seleciona e persiste empresa ativa usando contexto validado pelo backend', async ({ page }) => {
  await page.addInitScript(({ userId }) => {
    const user = { id: userId, aud: 'authenticated', role: 'authenticated', email: 'multi@example.test', app_metadata: {}, user_metadata: {}, created_at: '2026-09-24T12:00:00Z' }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({ access_token: 'test-access-token', refresh_token: 'test-refresh-token', expires_at: Math.floor(Date.now() / 1000) + 3600, expires_in: 3600, token_type: 'bearer', user }))
  }, { userId })

  const requestedCompanies: string[] = []
  await page.route('https://bpf-test.supabase.co/**', async route => {
    const request = route.request()
    const url = new URL(request.url())

    if (url.pathname.endsWith('/rest/v1/v_meu_contexto')) {
      return route.fulfill({ status: 200, json: [legacyContext] })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/meus_vinculos')) {
      return route.fulfill({ status: 200, json: memberships })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/meu_contexto_empresa')) {
      const body = JSON.parse(request.postData() ?? '{}') as { p_empresa_id?: string }
      const empresaId = body.p_empresa_id ?? ''
      requestedCompanies.push(empresaId)
      return route.fulfill({ status: 200, json: empresaId === companyA || empresaId === companyB ? [tenantContext(empresaId)] : [] })
    }

    return route.fulfill({ status: 200, json: [] })
  })

  await page.goto('/dashboard')
  const selector = page.getByLabel('Empresa ativa')
  await expect(selector).toBeVisible()
  await expect(selector).toHaveValue(companyA)
  await expect(page.locator('.workspace-footer')).toContainText('Empresa A')

  await selector.selectOption(companyB)
  await expect(selector).toHaveValue(companyB)
  await expect(page.locator('.workspace-footer')).toContainText('Empresa B')
  expect(requestedCompanies).toContain(companyB)

  await page.reload()
  await expect(page.getByLabel('Empresa ativa')).toHaveValue(companyB)
  await expect(page.locator('.workspace-footer')).toContainText('Empresa B')
})
