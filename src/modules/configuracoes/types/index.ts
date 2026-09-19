import type { UsuarioStatus } from '../../../types/auth'

export interface Empresa {
  id: string
  nome_fantasia: string | null
  razao_social: string
  cnpj?: string | null
  ativo?: boolean
}
export interface Unidade { id: string; empresa_id: string; nome: string; codigo?: string | null; ativo: boolean }
export interface Setor { id: string; unidade_id: string; nome: string; codigo: string | null; ativo: boolean }
export interface Perfil {
  id: string
  empresa_id: string | null
  nome: string
  descricao: string | null
  is_system: boolean
  ativo: boolean
}
export interface Permissao { id: string; codigo: string; modulo: string; acao: string; descricao: string | null }
export interface UsuarioPerfil { usuario_id: string; perfil_id: string }
export interface PerfilPermissao { perfil_id: string; permissao_id: string }
export interface Usuario {
  id: string
  nome: string | null
  email: string | null
  empresa_id: string | null
  unidade_id: string | null
  status: UsuarioStatus
  ativo: boolean
  created_at: string
}
export interface UsuariosData {
  usuarios: Usuario[]
  empresas: Empresa[]
  unidades: Unidade[]
  perfis: Perfil[]
  vinculos: UsuarioPerfil[]
}
export interface PerfisData { perfis: Perfil[]; permissoes: Permissao[]; vinculos: PerfilPermissao[] }
export interface EstruturaData { empresa: Empresa; unidades: Unidade[]; setores: Setor[] }
export interface AuditoriaEvento {
  id: string
  empresa_id: string
  unidade_id: string | null
  ator_id: string
  entidade: string
  registro_id: string
  acao: string
  antes: Record<string, unknown> | null
  depois: Record<string, unknown> | null
  justificativa: string
  contexto: Record<string, unknown>
  created_at: string
}
export interface AuditoriaData { eventos: AuditoriaEvento[]; usuarios: Pick<Usuario, 'id' | 'nome' | 'email'>[] }
export interface ReadScope { usuarioId: string; empresaId: string }
export interface UsuarioFilters { busca: string; status: string; unidade: string; perfil: string }
