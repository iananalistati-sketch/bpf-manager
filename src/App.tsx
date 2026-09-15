import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from './components/ProtectedRoute'
import { PermissionRoute } from './components/PermissionRoute'
import { AuthProvider } from './hooks/useAuth'
import { MainLayout } from './layouts/MainLayout'
import { DashboardPage } from './pages/DashboardPage'
import { ModulePage } from './pages/ModulePage'
import { LoginPage } from './pages/LoginPage'
import { navigationGroups } from './lib/navigation'
import './App.css'
import './auth.css'

export default function App() {
  const items = navigationGroups.flatMap(group => group.items)
  const dashboard = items.find(item => item.path === '/dashboard')!

  return <AuthProvider><BrowserRouter><Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<MainLayout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<PermissionRoute permission={dashboard.permission}><DashboardPage /></PermissionRoute>} />
        {items.filter(item => item.path !== '/dashboard').map(item => <Route key={item.path} path={item.path} element={<PermissionRoute permission={item.permission}><ModulePage module={item} /></PermissionRoute>} />)}
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Route>
    </Route>
  </Routes></BrowserRouter></AuthProvider>
}
