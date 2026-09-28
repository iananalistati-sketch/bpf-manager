import type { UsuarioStatus } from '../../../types/auth'
import { statusLabels } from '../lib/presentation'

const tones = { pendente: 'orange', ativo: 'green', inativo: 'neutral', bloqueado: 'red' }
export function StatusBadge({ status }: { status: UsuarioStatus }) {
  return <span className={`badge ${tones[status] ?? 'neutral'}`}>{statusLabels[status] ?? 'Não informado'}</span>
}
