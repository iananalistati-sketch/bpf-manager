import { expect, test } from '@playwright/test'

test('login oferece recuperação de senha sem revelar cadastro', async ({ page }) => {
  let recoveryRequest = false

  await page.route('https://bpf-test.supabase.co/**', async route => {
    const url = new URL(route.request().url())
    if (url.pathname === '/auth/v1/recover') {
      recoveryRequest = true
      return route.fulfill({ status: 200, json: {} })
    }
    return route.fulfill({ status: 200, json: {} })
  })

  await page.goto('/login')
  await page.getByRole('button', { name: 'Esqueci minha senha' }).click()
  await expect(page.getByRole('heading', { name: 'Recupere seu acesso' })).toBeVisible()
  await page.getByLabel('E-mail').fill('usuario@example.test')
  await page.getByRole('button', { name: 'Enviar link' }).click()
  await expect(page.getByRole('status')).toContainText('Se existir uma conta para este e-mail')
  expect(recoveryRequest).toBe(true)
})

test('rota de redefinição sem sessão informa link inválido ou expirado', async ({ page }) => {
  await page.route('https://bpf-test.supabase.co/**', route => route.fulfill({ status: 200, json: {} }))
  await page.goto('/redefinir-senha')
  await expect(page.getByRole('heading', { name: 'Link inválido ou expirado' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Ir para o login' })).toBeVisible()
})
