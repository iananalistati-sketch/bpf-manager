import { expect, test } from '@playwright/test'

const userId = 'e1000000-0000-0000-0000-000000000001'
const companyId = 'e2000000-0000-0000-0000-000000000001'
const unitId = 'e3000000-0000-0000-0000-000000000001'
const membershipId = 'e4000000-0000-0000-0000-000000000001'

const pendingContext = {
  usuario_id: userId,
  nome: 'Owner Trial',
  email: 'owner@example.test',
  ativo: false,
  status: 'pendente',
  empresa_id: null,
  nome_fantasia: null,
  razao_social: null,
  unidade_id: null,
  unidade_nome: null,
  perfis: [],
  permissoes: [],
}

const activeContext = {
  ...pendingContext,
  ativo: true,
  status: 'ativo',
  empresa_id: companyId,
  nome_fantasia: 'Fábrica Trial',
  razao_social: 'Fábrica Trial Ltda',
  unidade_id: unitId,
  unidade_nome: 'Unidade Principal',
  perfis: ['Administrador'],
  permissoes: ['dashboard.visualizar'],
}

test('self-service percorre provisionamento, onboarding e libera o dashboard', async ({ page }) => {
  await page.addInitScript(({ userId }) => {
    const user = {
      id: userId,
      aud: 'authenticated',
      role: 'authenticated',
      email: 'owner@example.test',
      app_metadata: {},
      user_metadata: { nome: 'Owner Trial' },
      created_at: '2026-10-13T14:00:00Z',
    }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({
      access_token: 'trial-access-token',
      refresh_token: 'trial-refresh-token',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      expires_in: 3600,
      token_type: 'bearer',
      user,
    }))
  }, { userId })

  let provisioned = false
  let onboarded = false
  let provisionPayload: Record<string, unknown> | null = null
  let onboardingPayload: Record<string, unknown> | null = null

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const request = route.request()
    const url = new URL(request.url())

    if (url.pathname.endsWith('/rest/v1/v_meu_contexto')) {
      return route.fulfill({ status: 200, json: [provisioned ? activeContext : pendingContext] })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/meus_vinculos')) {
      return route.fulfill({
        status: 200,
        json: provisioned ? [{
          membership_id: membershipId,
          empresa_id: companyId,
          nome_fantasia: 'Fábrica Trial',
          razao_social: 'Fábrica Trial Ltda',
          unidade_id: unitId,
          unidade_nome: 'Unidade Principal',
          status: 'ativo',
          is_owner: true,
        }] : [],
      })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/meu_contexto_empresa')) {
      return route.fulfill({ status: 200, json: provisioned ? [{ ...activeContext, membership_id: membershipId, is_owner: true }] : [] })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/meu_workspace_comercial')) {
      return route.fulfill({
        status: 200,
        json: provisioned ? [{
          empresa_id: companyId,
          plano_codigo: 'basic',
          plano_nome: 'Basic',
          assinatura_status: 'trialing',
          trial_inicio: '2026-10-13T14:00:00Z',
          trial_fim: '2026-10-27T14:00:00Z',
          trial_expirado: false,
          dias_trial_restantes: 14,
          modo_acesso: 'normal',
          onboarding_status: onboarded ? 'concluido' : 'nao_iniciado',
          onboarding_etapa: onboarded ? 'concluido' : 'empresa',
        }] : [],
      })
    }

    if (url.pathname.endsWith('/rest/v1/rpc/atualizar_meu_onboarding')) {
      onboardingPayload = JSON.parse(request.postData() ?? '{}')
      onboarded = true
      return route.fulfill({
        status: 200,
        json: [{
          empresa_id: companyId,
          status: 'concluido',
          etapa_atual: 'concluido',
          dados: onboardingPayload,
          started_at: '2026-10-13T14:05:00Z',
          completed_at: '2026-10-13T14:06:00Z',
        }],
      })
    }

    if (url.pathname.endsWith('/functions/v1/start-trial')) {
      provisionPayload = JSON.parse(request.postData() ?? '{}')
      provisioned = true
      return route.fulfill({
        status: 200,
        json: {
          empresaId: companyId,
          unidadeId: unitId,
          membershipId,
          assinaturaId: 'e5000000-0000-0000-0000-000000000001',
          trialFim: '2026-10-27T14:00:00Z',
        },
      })
    }

    return route.fulfill({ status: 200, json: {} })
  })

  await page.goto('/dashboard')
  await expect(page).toHaveURL(/\/iniciar-trial$/)
  await expect(page.getByRole('heading', { name: 'Prepare seu ambiente de teste' })).toBeVisible()

  await page.getByLabel('Razão social').fill('Fábrica Trial Ltda')
  await page.getByLabel('Nome da empresa').fill('Fábrica Trial')
  await page.getByLabel('Unidade principal').fill('Unidade Principal')
  await page.getByRole('button', { name: 'Iniciar meu trial' }).click()

  await expect(page).toHaveURL(/\/onboarding$/)
  await expect(page.getByRole('heading', { name: 'Configure o primeiro acesso' })).toBeVisible()
  await page.getByLabel('Responsável técnico').fill('Dra. Responsável')
  await page.getByLabel('Tipo de operação').selectOption('fabricacao')
  await page.getByLabel('Setores principais').fill('Recebimento, Produção, Qualidade')
  await page.getByRole('button', { name: 'Concluir e acessar o BPF Manager' }).click()

  await expect(page).toHaveURL(/\/dashboard$/)
  expect(provisionPayload).toEqual({
    razaoSocial: 'Fábrica Trial Ltda',
    nomeFantasia: 'Fábrica Trial',
    unidadeNome: 'Unidade Principal',
  })
  expect(JSON.stringify(onboardingPayload)).toContain('Dra. Responsável')
  expect(JSON.stringify(onboardingPayload)).toContain('Recebimento')
})

test('trial expirado preserva acesso ao dashboard em modo somente leitura sem prender no onboarding', async ({ page }) => {
  await page.addInitScript(({ userId }) => {
    const user = {
      id: userId,
      aud: 'authenticated',
      role: 'authenticated',
      email: 'owner@example.test',
      app_metadata: {},
      user_metadata: { nome: 'Owner Trial' },
      created_at: '2026-10-01T14:00:00Z',
    }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({
      access_token: 'expired-trial-token',
      refresh_token: 'expired-trial-refresh',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      expires_in: 3600,
      token_type: 'bearer',
      user,
    }))
  }, { userId })

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const url = new URL(route.request().url())

    if (url.pathname.endsWith('/rest/v1/v_meu_contexto')) {
      return route.fulfill({ status: 200, json: [activeContext] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meus_vinculos')) {
      return route.fulfill({ status: 200, json: [{
        membership_id: membershipId,
        empresa_id: companyId,
        nome_fantasia: 'Fábrica Trial',
        razao_social: 'Fábrica Trial Ltda',
        unidade_id: unitId,
        unidade_nome: 'Unidade Principal',
        status: 'ativo',
        is_owner: true,
      }] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meu_contexto_empresa')) {
      return route.fulfill({ status: 200, json: [{ ...activeContext, membership_id: membershipId, is_owner: true }] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meu_workspace_comercial')) {
      return route.fulfill({ status: 200, json: [{
        empresa_id: companyId,
        plano_codigo: 'basic',
        plano_nome: 'Basic',
        assinatura_status: 'trialing',
        trial_inicio: '2026-09-15T14:00:00Z',
        trial_fim: '2026-09-29T14:00:00Z',
        trial_expirado: true,
        dias_trial_restantes: 0,
        modo_acesso: 'somente_leitura',
        onboarding_status: 'nao_iniciado',
        onboarding_etapa: 'empresa',
      }] })
    }

    return route.fulfill({ status: 200, json: [] })
  })

  await page.goto('/dashboard')
  await expect(page).toHaveURL(/\/dashboard$/)
  await expect(page.getByLabel('Status do trial')).toContainText('Trial encerrado')
  await expect(page.getByLabel('Status do trial')).toContainText('somente leitura')
})

test('cadastro público envia nome do owner e comunica confirmação antes do trial', async ({ page }) => {
  let signupPayload: Record<string, unknown> | null = null

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const request = route.request()
    const url = new URL(request.url())

    if (url.pathname === '/auth/v1/signup') {
      signupPayload = JSON.parse(request.postData() ?? '{}')
      return route.fulfill({
        status: 200,
        json: {
          user: {
            id: userId,
            aud: 'authenticated',
            role: 'authenticated',
            email: 'owner@example.test',
            app_metadata: {},
            user_metadata: { nome: 'Owner Trial' },
            identities: [],
            created_at: '2026-10-13T14:00:00Z',
          },
          session: null,
        },
      })
    }

    return route.fulfill({ status: 200, json: {} })
  })

  await page.goto('/login')
  await page.getByRole('button', { name: 'Testar gratuitamente por 14 dias' }).click()
  await expect(page.getByRole('heading', { name: 'Comece seu teste gratuito' })).toBeVisible()

  await page.getByLabel('Seu nome').fill('Owner Trial')
  await page.getByLabel('E-mail').fill('owner@example.test')
  await page.getByLabel('Senha').fill('senha-segura-123')
  await page.getByRole('button', { name: 'Criar conta e continuar' }).click()

  await expect(page.getByRole('status')).toContainText('Confirme o e-mail')
  expect(signupPayload).not.toBeNull()
  expect(JSON.stringify(signupPayload)).toContain('Owner Trial')
})
