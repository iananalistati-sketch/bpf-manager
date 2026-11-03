import { expect, test } from '@playwright/test'

const userId = 'be000000-0000-0000-0000-000000000001'
const companyId = 'be100000-0000-0000-0000-000000000001'
const unitId = 'be200000-0000-0000-0000-000000000001'
const membershipId = 'be300000-0000-0000-0000-000000000001'
const documentId = 'be400000-0000-0000-0000-000000000001'

const permissions = [
  'dashboard.visualizar',
  'documentos.visualizar',
  'documentos.criar',
  'documentos.editar',
  'documentos.aprovar',
]

const context = {
  usuario_id: userId,
  membership_id: membershipId,
  nome: 'Responsável Qualidade',
  email: 'qualidade@example.test',
  ativo: true,
  status: 'ativo',
  empresa_id: companyId,
  nome_fantasia: 'Fábrica BPF',
  razao_social: 'Fábrica BPF Ltda',
  unidade_id: unitId,
  unidade_nome: 'Unidade Principal',
  is_owner: true,
  perfis: ['Qualidade'],
  permissoes: permissions,
}

test('documentos cria rascunho e conduz transição auditável pela interface', async ({ page }) => {
  await page.addInitScript(({ userId }) => {
    const user = {
      id: userId,
      aud: 'authenticated',
      role: 'authenticated',
      email: 'qualidade@example.test',
      app_metadata: {},
      user_metadata: { nome: 'Responsável Qualidade' },
      created_at: '2026-10-14T12:00:00Z',
    }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({
      access_token: 'docs-access-token',
      refresh_token: 'docs-refresh-token',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      expires_in: 3600,
      token_type: 'bearer',
      user,
    }))
  }, { userId })

  let documents: Record<string, unknown>[] = []
  let createPayload: Record<string, unknown> | null = null
  let transitionPayload: Record<string, unknown> | null = null

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const request = route.request()
    const url = new URL(request.url())

    if (url.pathname.endsWith('/rest/v1/v_meu_contexto')) {
      return route.fulfill({ status: 200, json: [{ ...context }] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meus_vinculos')) {
      return route.fulfill({ status: 200, json: [{
        membership_id: membershipId,
        empresa_id: companyId,
        nome_fantasia: 'Fábrica BPF',
        razao_social: 'Fábrica BPF Ltda',
        unidade_id: unitId,
        unidade_nome: 'Unidade Principal',
        status: 'ativo',
        is_owner: true,
      }] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meu_contexto_empresa')) {
      return route.fulfill({ status: 200, json: [context] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/meu_workspace_comercial')) {
      return route.fulfill({ status: 200, json: [{
        empresa_id: companyId,
        plano_codigo: 'basic',
        plano_nome: 'Basic',
        assinatura_status: 'trialing',
        trial_inicio: '2026-10-14T12:00:00Z',
        trial_fim: '2026-10-28T12:00:00Z',
        trial_expirado: false,
        dias_trial_restantes: 14,
        modo_acesso: 'normal',
        onboarding_status: 'concluido',
        onboarding_etapa: 'concluido',
      }] })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/documentos_listar')) {
      return route.fulfill({ status: 200, json: documents })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/documento_criar')) {
      createPayload = JSON.parse(request.postData() ?? '{}')
      documents = [{
        documento_id: documentId,
        empresa_id: companyId,
        unidade_id: unitId,
        codigo: 'POP-001',
        titulo: 'Higienização das instalações',
        tipo: 'POP',
        ativo: true,
        versao_id: 'be500000-0000-0000-0000-000000000001',
        versao_numero: 1,
        status: 'rascunho',
        descricao: 'Procedimento controlado.',
        revisao_prevista_em: '2027-04-14',
        autor_id: userId,
        revisor_id: null,
        aprovador_id: null,
        vigencia_inicio: null,
        updated_at: '2026-10-14T12:10:00Z',
      }]
      return route.fulfill({ status: 200, json: documentId })
    }
    if (url.pathname.endsWith('/rest/v1/rpc/documento_transicionar')) {
      transitionPayload = JSON.parse(request.postData() ?? '{}')
      documents = documents.map(doc => ({ ...doc, status: 'em_revisao', updated_at: '2026-10-14T12:12:00Z' }))
      return route.fulfill({ status: 200, json: null })
    }

    return route.fulfill({ status: 200, json: [] })
  })

  await page.goto('/documentos')
  await expect(page.getByRole('heading', { name: 'Documentos', exact: true })).toBeVisible()
  await expect(page.getByText('Nenhum documento cadastrado')).toBeVisible()

  await page.getByRole('button', { name: 'Novo documento' }).click()
  await page.getByLabel('Código').fill('POP-001')
  await page.getByLabel('Título').fill('Higienização das instalações')
  await page.getByLabel('Tipo').fill('POP')
  await page.getByLabel('Revisão prevista').fill('2027-04-14')
  await page.getByLabel('Descrição').fill('Procedimento controlado.')
  await page.getByRole('button', { name: 'Salvar rascunho' }).click()

  await expect(page.getByText('POP-001 · Higienização das instalações')).toBeVisible()
  await expect(page.getByText('Rascunho', { exact: true })).toBeVisible()
  expect(createPayload).toMatchObject({
    p_empresa_id: companyId,
    p_unidade_id: unitId,
    p_codigo: 'POP-001',
    p_titulo: 'Higienização das instalações',
    p_tipo: 'POP',
    p_descricao: 'Procedimento controlado.',
    p_revisao_prevista_em: '2027-04-14',
  })

  await page.getByRole('button', { name: 'Enviar para revisão' }).click()
  await page.getByLabel('Justificativa').fill('Encaminhado para revisão técnica')
  await page.getByRole('button', { name: 'Confirmar' }).click()

  await expect(page.getByText('Em revisão')).toBeVisible()
  expect(transitionPayload).toMatchObject({
    p_documento_id: documentId,
    p_status_destino: 'em_revisao',
    p_justificativa: 'Encaminhado para revisão técnica',
  })
})

test('documentos preserva consulta e bloqueia ações quando o workspace está somente leitura', async ({ page }) => {
  await page.addInitScript(({ userId }) => {
    const user = {
      id: userId,
      aud: 'authenticated',
      role: 'authenticated',
      email: 'qualidade@example.test',
      app_metadata: {},
      user_metadata: {},
      created_at: '2026-10-01T12:00:00Z',
    }
    localStorage.setItem('sb-bpf-test-auth-token', JSON.stringify({
      access_token: 'docs-readonly-token',
      refresh_token: 'docs-readonly-refresh',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      expires_in: 3600,
      token_type: 'bearer',
      user,
    }))
  }, { userId })

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const url = new URL(route.request().url())
    if (url.pathname.endsWith('/rest/v1/v_meu_contexto')) return route.fulfill({ status: 200, json: [context] })
    if (url.pathname.endsWith('/rest/v1/rpc/meus_vinculos')) return route.fulfill({ status: 200, json: [{
      membership_id: membershipId, empresa_id: companyId, nome_fantasia: 'Fábrica BPF', razao_social: 'Fábrica BPF Ltda',
      unidade_id: unitId, unidade_nome: 'Unidade Principal', status: 'ativo', is_owner: true,
    }] })
    if (url.pathname.endsWith('/rest/v1/rpc/meu_contexto_empresa')) return route.fulfill({ status: 200, json: [context] })
    if (url.pathname.endsWith('/rest/v1/rpc/meu_workspace_comercial')) return route.fulfill({ status: 200, json: [{
      empresa_id: companyId, plano_codigo: 'basic', plano_nome: 'Basic', assinatura_status: 'expired',
      trial_inicio: null, trial_fim: null, trial_expirado: false, dias_trial_restantes: 0,
      modo_acesso: 'somente_leitura', onboarding_status: 'concluido', onboarding_etapa: 'concluido',
    }] })
    if (url.pathname.endsWith('/rest/v1/rpc/documentos_listar')) return route.fulfill({ status: 200, json: [{
      documento_id: documentId, empresa_id: companyId, unidade_id: unitId, codigo: 'POP-001',
      titulo: 'Higienização das instalações', tipo: 'POP', ativo: true,
      versao_id: 'be500000-0000-0000-0000-000000000001', versao_numero: 1, status: 'vigente',
      descricao: 'Procedimento controlado.', revisao_prevista_em: '2027-04-14', autor_id: userId,
      revisor_id: userId, aprovador_id: userId, vigencia_inicio: '2026-10-01T12:00:00Z', updated_at: '2026-10-01T12:00:00Z',
    }] })
    return route.fulfill({ status: 200, json: [] })
  })

  await page.goto('/documentos')
  await expect(page.getByText('POP-001 · Higienização das instalações')).toBeVisible()
  await expect(page.getByText('O workspace está em somente leitura.')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Novo documento' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Iniciar revisão' })).toHaveCount(0)
})
