import type { Permissao, Usuario, UsuarioFilters, UsuarioPerfil } from '../types'

export const statusLabels = { pendente: 'Pendente', ativo: 'Ativo', inativo: 'Inativo', bloqueado: 'Bloqueado' }
export const emptyFilters: UsuarioFilters = { busca: '', status: '', unidade: '', perfil: '' }
const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR')

export function filterUsuarios(usuarios: Usuario[], vinculos: UsuarioPerfil[], filters: UsuarioFilters) {
  const search = normalize(filters.busca.trim())
  return usuarios.filter(user => (!search || normalize(`${user.nome ?? ''} ${user.email ?? ''}`).includes(search))
    && (!filters.status || user.status === filters.status)
    && (!filters.unidade || (filters.unidade === 'sem-unidade' ? !user.unidade_id : user.unidade_id === filters.unidade))
    && (!filters.perfil || (filters.perfil === 'sem-perfil'
      ? !vinculos.some(link => link.usuario_id === user.id)
      : vinculos.some(link => link.usuario_id === user.id && link.perfil_id === filters.perfil))))
}

export function groupPermissions(permissoes: Permissao[]) {
  const groups = new Map<string, Permissao[]>()
  for (const permissao of permissoes) groups.set(permissao.modulo, [...(groups.get(permissao.modulo) ?? []), permissao])
  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b, 'pt-BR'))
}

export function displayCode(code: string) {
  const text = code.replaceAll('_', ' ')
  return text.charAt(0).toLocaleUpperCase('pt-BR') + text.slice(1)
}

export function displayDate(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Não informada' : date.toLocaleDateString('pt-BR')
}
