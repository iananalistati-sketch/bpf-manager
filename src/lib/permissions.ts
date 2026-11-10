import type { MeuContexto } from '../types/auth'

// Conveniência compartilhada da interface. A autorização definitiva pertence ao banco.
export function hasPermission(contexto: MeuContexto | null, permission: string): boolean {
  return Boolean(contexto?.ativo && contexto.status === 'ativo' && contexto.empresa_id
    && contexto.permissoes?.includes(permission))
}
