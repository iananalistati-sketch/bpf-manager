import { useMemo, useState } from 'react'
import { MailPlus, ShieldCheck } from 'lucide-react'
import type { UsuariosData } from '../types'
import { useUsuarioAdminActions } from '../hooks/useConfiguracoesQuery'
import { DetailsDialog } from './DetailsDialog'

export function InviteUsuarioDialog({ data, onClose, onChanged }: { data: UsuariosData; onClose: () => void; onChanged: () => void }) {
  const actions = useUsuarioAdminActions()
  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [unidadeId, setUnidadeId] = useState('')
  const [perfilIds, setPerfilIds] = useState<string[]>([])
  const [justificativa, setJustificativa] = useState('')
  const activeProfiles = useMemo(() => data.perfis.filter(item => item.ativo), [data.perfis])
  const activeUnits = useMemo(() => data.unidades.filter(item => item.ativo), [data.unidades])
  const valid = nome.trim().length >= 2 && /^\S+@\S+\.\S+$/.test(email.trim()) && perfilIds.length > 0 && justificativa.trim().length >= 5

  const toggleProfile = (id: string) => setPerfilIds(current => current.includes(id) ? current.filter(item => item !== id) : [...current, id])
  const submit = async () => {
    const result = await actions.convidarUsuario({ email, nome, unidadeId: unidadeId || null, perfilIds, justificativa })
    if (!result.ok) return
    onChanged()
    onClose()
  }

  return <DetailsDialog title="Convidar usuário" onClose={onClose}>
    <p className="settings-notice"><MailPlus size={18} /><span><strong>Convite seguro.</strong> O usuário receberá um e-mail do Supabase Auth e será vinculado somente à sua empresa, unidade e perfis selecionados.</span></p>
    {actions.error && <p className="settings-notice warning" role="alert">{actions.error}</p>}
    <div className="settings-fields">
      <label>Nome<input autoFocus value={nome} onChange={event => { actions.clearError(); setNome(event.target.value) }} placeholder="Nome do usuário" /></label>
      <label>E-mail<input type="email" value={email} onChange={event => { actions.clearError(); setEmail(event.target.value) }} placeholder="usuario@empresa.com" /></label>
      <label>Unidade<select value={unidadeId} onChange={event => setUnidadeId(event.target.value)}><option value="">Sem unidade</option>{activeUnits.map(item => <option key={item.id} value={item.id}>{item.nome}</option>)}</select></label>
      <label>Justificativa<input value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Motivo do convite" /></label>
    </div>
    <fieldset className="settings-profile-checks"><legend><ShieldCheck size={15} /> Perfis iniciais</legend>
      {activeProfiles.map(perfil => <label key={perfil.id}><input type="checkbox" checked={perfilIds.includes(perfil.id)} onChange={() => toggleProfile(perfil.id)} /><span>{perfil.nome}{perfil.is_system && ' · sistema'}</span></label>)}
      {!activeProfiles.length && <p className="settings-muted">Nenhum perfil ativo disponível.</p>}
    </fieldset>
    <div className="settings-future-actions"><button className="button primary" disabled={!valid || actions.busy !== null} onClick={() => void submit()}>{actions.busy ? 'Enviando…' : 'Enviar convite'}</button></div>
  </DetailsDialog>
}
