import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from './components/ProtectedRoute'
import { PermissionRoute } from './components/PermissionRoute'
import { AuthProvider } from './components/AuthProvider'
import { MainLayout } from './layouts/MainLayout'
import { DashboardPage } from './pages/DashboardPage'
import { ModulePage } from './pages/ModulePage'
import { LoginPage } from './pages/LoginPage'
import { ResetPasswordPage } from './pages/ResetPasswordPage'
import { navigationGroups } from './lib/navigation'
import './App.css'
import './auth.css'
import './tenant.css'

const ConfiguracoesPage = lazy(() => import('./modules/configuracoes/pages/ConfiguracoesPage')
  .then(module => ({ default: module.ConfiguracoesPage })))

export default function App() {
  const items = navigationGroups.flatMap(group => group.items)
  const dashboard = items.find(item => item.path === '/dashboard')!

  return <AuthProvider><BrowserRouter><Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route path="/redefinir-senha" element={<ResetPasswordPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<MainLayout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<PermissionRoute permission={dashboard.permission}><DashboardPage /></PermissionRoute>} />
        {items.filter(item => item.path !== '/dashboard').map(item => <Route key={item.path} path={item.path} element={<PermissionRoute permission={item.permission}>{item.path === '/configuracoes' ? <Suspense fallback={<p role="status">Carregando configurações…</p>}><ConfiguracoesPage /></Suspense> : <ModulePage module={item} />}</PermissionRoute>} />)}
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Route>
    </Route>
  </Routes></BrowserRouter></AuthProvider>
}
