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

export interface VinculoEmpresa {
  membership_id: string
  empresa_id: string
  nome_fantasia: string | null
  razao_social: string | null
  unidade_id: string | null
  unidade_nome: string | null
  status: UsuarioStatus
  is_owner: boolean
}

export interface MeuContextoEmpresa extends MeuContexto {
  membership_id: string
  empresa_id: string
  is_owner: boolean
}


export interface WorkspaceCommercial {
  empresa_id: string
  plano_codigo: string | null
  plano_nome: string | null
  assinatura_status: 'trialing' | 'active' | 'past_due' | 'paused' | 'canceled' | 'expired'
  trial_inicio: string | null
  trial_fim: string | null
  trial_expirado: boolean
  dias_trial_restantes: number
  modo_acesso: 'normal' | 'somente_leitura'
  onboarding_status: 'nao_iniciado' | 'em_andamento' | 'concluido'
  onboarding_etapa: string | null
}
