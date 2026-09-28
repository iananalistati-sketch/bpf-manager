import { useState } from 'react'
import { ShieldPlus } from 'lucide-react'
import type { PerfisData } from '../types'
import { displayCode, groupPermissions } from '../lib/presentation'
import { useAdministracaoActions } from '../hooks/useConfiguracoesQuery'
import { DetailsDialog } from './DetailsDialog'

export function PerfilCreateDialog({ data, onClose, onChanged }: { data: PerfisData; onClose: () => void; onChanged: () => void }) {
  const actions = useAdministracaoActions()
  const [nome, setNome] = useState('')
  const [descricao, setDescricao] = useState('')
  const [permissionIds, setPermissionIds] = useState<string[]>([])
  const [justificativa, setJustificativa] = useState('')
  const toggle = (id: string) => setPermissionIds(current => current.includes(id) ? current.filter(item => item !== id) : [...current, id])
  const save = async () => {
    const result = await actions.perfilCriar(nome, descricao, permissionIds, justificativa)
    if (!result.ok) return
    onChanged(); onClose()
  }
  return <DetailsDialog title="Novo perfil" onClose={onClose}>
    <p className="settings-notice"><ShieldPlus size={18} /><span><strong>Perfil da empresa.</strong> O novo perfil será exclusivo da sua empresa. Perfis de sistema permanecem globais e somente leitura.</span></p>
    {actions.error && <p className="settings-notice warning" role="alert">{actions.error}</p>}
    <div className="settings-fields"><label>Nome<input autoFocus value={nome} onChange={event => setNome(event.target.value)} placeholder="Ex.: Coordenador de Qualidade" /></label><label>Descrição<input value={descricao} onChange={event => setDescricao(event.target.value)} placeholder="Finalidade do perfil" /></label></div>
    <div className="settings-permission-groups">{groupPermissions(data.permissoes).map(([modulo, permissoes]) => <fieldset key={modulo}><legend>{displayCode(modulo)}</legend>{permissoes.map(permissao => <label key={permissao.id} className="settings-permission"><input type="checkbox" checked={permissionIds.includes(permissao.id)} onChange={() => toggle(permissao.id)} /><span><strong>{displayCode(permissao.acao)}</strong><small>{permissao.descricao || permissao.codigo}</small></span></label>)}</fieldset>)}</div>
    <label className="settings-standalone-field">Justificativa<input value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Motivo da criação" /></label>
    <button className="button primary" disabled={nome.trim().length < 2 || justificativa.trim().length < 5 || actions.busy !== null} onClick={() => void save()}>{actions.busy ? 'Criando…' : 'Criar perfil'}</button>
  </DetailsDialog>
}
