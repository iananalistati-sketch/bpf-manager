import { LockKeyhole } from 'lucide-react'
import type { Perfil, PerfisData } from '../types'
import { displayCode, groupPermissions } from '../lib/presentation'
import { DetailsDialog } from './DetailsDialog'

export function PerfilDetails({ perfil, data, onClose }: { perfil: Perfil; data: PerfisData; onClose: () => void }) {
  const assigned = new Set(data.vinculos.filter(link => link.perfil_id === perfil.id).map(link => link.permissao_id))
  return <DetailsDialog title={perfil.nome} onClose={onClose}>
    <div className="settings-detail-intro"><p>{perfil.descricao || 'Descrição não informada.'}</p><div className="settings-tags"><span className={`badge ${perfil.ativo ? 'green' : 'neutral'}`}>{perfil.ativo ? 'Ativo' : 'Inativo'}</span>{perfil.is_system && <span className="badge blue">Perfil de sistema</span>}<span className="badge neutral">{assigned.size} permissões atribuídas</span></div></div>
    <p className="settings-notice"><LockKeyhole size={18} />{perfil.is_system ? 'Perfil de sistema compartilhado. As permissões estão disponíveis apenas para consulta.' : 'Permissões disponíveis para consulta. A edição será habilitada após revisão das regras administrativas.'}</p>
    <div className="settings-permission-groups">
      {groupPermissions(data.permissoes).map(([modulo, permissoes]) => <fieldset key={modulo} disabled><legend>{displayCode(modulo)}</legend>{permissoes.map(permissao => <label key={permissao.id} className="settings-permission"><input type="checkbox" checked={assigned.has(permissao.id)} readOnly /><span><strong>{displayCode(permissao.acao)}</strong><small>{permissao.descricao || permissao.codigo}</small></span></label>)}</fieldset>)}
      {!data.permissoes.length && <p className="settings-muted">Nenhuma permissão retornada para consulta.</p>}
    </div>
    <button className="button primary" disabled>Salvar permissões</button>
  </DetailsDialog>
}
