export type UsuarioStatus = 'pendente' | 'ativo' | 'inativo' | 'bloqueado'

export interface MeuContexto {
  usuario_id: string
  nome: string | null
  email: string | null
  ativo: boolean
  status: UsuarioStatus
  empresa_id: string | null
  nome_fantasia: string | null
  razao_social: string | null
  unidade_id: string | null
  unidade_nome: string | null
  perfis: string[] | null
  permissoes: string[] | null
}
