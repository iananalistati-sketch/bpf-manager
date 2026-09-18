import { useMemo, useState } from 'react'
import { LockKeyhole, ShieldCheck } from 'lucide-react'
import type { Perfil, PerfisData } from '../types'
import { displayCode, groupPermissions } from '../lib/presentation'
import { useAdministracaoActions } from '../hooks/useConfiguracoesQuery'
import { DetailsDialog } from './DetailsDialog'

export function PerfilDetails({ perfil, data, onClose, onChanged }: { perfil: Perfil; data: PerfisData; onClose: () => void; onChanged?: () => void }) {
  const actions = useAdministracaoActions()
  const initial = useMemo(() => data.vinculos.filter(link => link.perfil_id === perfil.id).map(link => link.permissao_id), [data.vinculos, perfil.id])
  const [nome, setNome] = useState(perfil.nome)
  const [descricao, setDescricao] = useState(perfil.descricao ?? '')
  const [ativo, setAtivo] = useState(perfil.ativo)
  const [permissionIds, setPermissionIds] = useState<string[]>(initial)
  const [justificativa, setJustificativa] = useState('')
  const readOnly = perfil.is_system
  const toggle = (id: string) => setPermissionIds(current => current.includes(id) ? current.filter(item => item !== id) : [...current, id])
  const changed = nome.trim() !== perfil.nome || descricao.trim() !== (perfil.descricao ?? '') || ativo !== perfil.ativo
    || [...permissionIds].sort().join(',') !== [...initial].sort().join(',')
  const save = async () => {
    const result = await actions.perfilAtualizar(perfil.id, nome, descricao, ativo, permissionIds, justificativa)
    if (!result.ok) return
    onChanged?.()
    onClose()
  }

  return <DetailsDialog title={perfil.nome} onClose={onClose}>
    <div className="settings-detail-intro"><p>{perfil.descricao || 'Descrição não informada.'}</p><div className="settings-tags"><span className={`badge ${perfil.ativo ? 'green' : 'neutral'}`}>{perfil.ativo ? 'Ativo' : 'Inativo'}</span>{perfil.is_system && <span className="badge blue">Perfil de sistema</span>}<span className="badge neutral">{initial.length} permissões atribuídas</span></div></div>
    <p className="settings-notice">{readOnly ? <><LockKeyhole size={18} /><span><strong>Perfil de sistema.</strong> Ele é compartilhado entre empresas e permanece somente leitura. Crie um perfil da empresa para personalizar permissões.</span></> : <><ShieldCheck size={18} /><span><strong>Perfil da empresa.</strong> Nome, situação e permissões podem ser alterados com justificativa e auditoria.</span></>}</p>
    {actions.error && <p className="settings-notice warning" role="alert">{actions.error}</p>}
    {!readOnly && <div className="settings-fields"><label>Nome<input value={nome} onChange={event => setNome(event.target.value)} /></label><label>Situação<select value={ativo ? 'ativo' : 'inativo'} onChange={event => setAtivo(event.target.value === 'ativo')}><option value="ativo">Ativo</option><option value="inativo">Inativo</option></select></label><label className="settings-field-wide">Descrição<input value={descricao} onChange={event => setDescricao(event.target.value)} placeholder="Descrição do perfil" /></label></div>}
    <div className="settings-permission-groups">
      {groupPermissions(data.permissoes).map(([modulo, permissoes]) => <fieldset key={modulo} disabled={readOnly}><legend>{displayCode(modulo)}</legend>{permissoes.map(permissao => <label key={permissao.id} className="settings-permission"><input type="checkbox" checked={permissionIds.includes(permissao.id)} onChange={() => toggle(permissao.id)} /><span><strong>{displayCode(permissao.acao)}</strong><small>{permissao.descricao || permissao.codigo}</small></span></label>)}</fieldset>)}
      {!data.permissoes.length && <p className="settings-muted">Nenhuma permissão retornada para consulta.</p>}
    </div>
    {!readOnly && <><label className="settings-standalone-field">Justificativa<input value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Motivo da alteração" /></label><button className="button primary" disabled={!changed || justificativa.trim().length < 5 || nome.trim().length < 2 || actions.busy !== null} onClick={() => void save()}>{actions.busy ? 'Salvando…' : 'Salvar perfil'}</button></>}
  </DetailsDialog>
}
