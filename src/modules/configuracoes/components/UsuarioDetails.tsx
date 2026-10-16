import { useMemo, useState } from 'react'
import { AlertTriangle, LockKeyhole, ShieldCheck } from 'lucide-react'
import type { Usuario, UsuariosData } from '../types'
import { displayDate, statusLabels } from '../lib/presentation'
import { useUsuarioAdminActions } from '../hooks/useConfiguracoesQuery'
import { DetailsDialog } from './DetailsDialog'
import { StatusBadge } from './StatusBadge'

export function UsuarioDetails({ usuario, data, onClose, onChanged }: {
  usuario: Usuario
  data: UsuariosData
  onClose: () => void
  onChanged: () => void
}) {
  const actions = useUsuarioAdminActions()
  const assigned = useMemo(() => new Set(data.vinculos.filter(link => link.usuario_id === usuario.id).map(link => link.perfil_id)), [data.vinculos, usuario.id])
  const [unitId, setUnitId] = useState(usuario.unidade_id ?? '')
  const [statusReason, setStatusReason] = useState('')
  const [unitReason, setUnitReason] = useState('')
  const [profileReason, setProfileReason] = useState('')
  const isSelf = actions.currentUserId === usuario.id
  const pending = usuario.status === 'pendente'
  const activeUnits = data.unidades.filter(item => item.ativo || item.id === usuario.unidade_id)

  const done = (ok: boolean) => {
    if (!ok) return
    onChanged()
  }
  const changeStatus = async (status: 'ativo' | 'inativo' | 'bloqueado') => {
    const label = statusLabels[status]
    if ((status === 'inativo' || status === 'bloqueado') && !window.confirm(`Confirma alterar o status de ${usuario.nome || usuario.email || 'este usuário'} para ${label}?`)) return
    done(await actions.alterarStatus(usuario.id, status, statusReason))
  }
  const changeUnit = async () => {
    if (!window.confirm('Confirma a alteração de unidade deste usuário?')) return
    done(await actions.alterarUnidade(usuario.id, unitId || null, unitReason))
  }
  const changeProfile = async (perfilId: string, acao: 'atribuir' | 'remover') => {
    const perfil = data.perfis.find(item => item.id === perfilId)
    if (!perfil) return
    if (!window.confirm(`Confirma ${acao === 'atribuir' ? 'atribuir' : 'remover'} o perfil “${perfil.nome}”?`)) return
    done(await actions.alterarPerfil(usuario.id, perfilId, acao, profileReason))
  }

  return <DetailsDialog title="Detalhes do usuário" onClose={onClose}>
    <div className="settings-detail-intro"><h3>{usuario.nome || 'Nome não informado'}</h3><p>{usuario.email || 'E-mail não informado'}</p><StatusBadge status={usuario.status} /></div>
    {pending && <p className="settings-notice warning"><AlertTriangle size={18} /><span><strong>Cadastro pendente.</strong> Este registro não pode ser ativado por edição direta. Novos acessos devem usar o fluxo seguro de convite e vínculo.</span></p>}
    {!pending && <p className="settings-notice"><ShieldCheck size={18} /><span><strong>Administração protegida.</strong> Alterações são executadas por comandos seguros no servidor, exigem justificativa e geram trilha de auditoria.</span></p>}
    {isSelf && !pending && <p className="settings-notice warning"><LockKeyhole size={18} />Por segurança, você não pode bloquear/inativar a própria conta nem alterar seus próprios perfis administrativos.</p>}
    {actions.error && <p className="settings-notice warning" role="alert"><AlertTriangle size={18} />{actions.error}</p>}

    <fieldset className="settings-fields" disabled>
      <legend>Cadastro</legend>
      <label>Nome<input value={usuario.nome ?? ''} readOnly placeholder="Não informado" /></label>
      <label>E-mail<input value={usuario.email ?? ''} readOnly placeholder="Não informado" /></label>
      <label>Empresa<select value={usuario.empresa_id ?? ''} disabled><option value="">Não vinculada</option>{data.empresas.map(empresa => <option key={empresa.id} value={empresa.id}>{empresa.nome_fantasia || empresa.razao_social}</option>)}</select></label>
      <label>Situação do cadastro<input value={usuario.ativo ? 'Ativo' : 'Inativo'} readOnly /></label>
    </fieldset>
    <button className="button primary" disabled>Salvar alterações</button>

    {!pending && <div className="settings-admin-stack">
      <section className="settings-admin-card" aria-labelledby="status-admin-title">
        <div><h4 id="status-admin-title">Status de acesso</h4><p>Ative, inative ou bloqueie o usuário. O servidor impede auto-bloqueio e perda do último administrador efetivo.</p></div>
        <label>Justificativa<input value={statusReason} onChange={event => { actions.clearError(); setStatusReason(event.target.value) }} placeholder="Informe o motivo da alteração" /></label>
        <div className="settings-future-actions">
          <button className="button secondary" disabled={actions.busy !== null || usuario.status === 'ativo' || statusReason.trim().length < 5} onClick={() => void changeStatus('ativo')}>Ativar</button>
          <button className="button secondary" disabled={actions.busy !== null || isSelf || usuario.status === 'inativo' || statusReason.trim().length < 5} onClick={() => void changeStatus('inativo')}>Inativar</button>
          <button className="button secondary" disabled={actions.busy !== null || isSelf || usuario.status === 'bloqueado' || statusReason.trim().length < 5} onClick={() => void changeStatus('bloqueado')}>Bloquear</button>
        </div>
      </section>

      <section className="settings-admin-card" aria-labelledby="unit-admin-title">
        <div><h4 id="unit-admin-title">Unidade</h4><p>Somente unidades ativas da mesma empresa podem ser vinculadas.</p></div>
        <label>Unidade<select value={unitId} onChange={event => { actions.clearError(); setUnitId(event.target.value) }}><option value="">Sem unidade</option>{activeUnits.map(unidade => <option key={unidade.id} value={unidade.id}>{unidade.nome}{!unidade.ativo && ' (inativa atual)'}</option>)}</select></label>
        <label>Justificativa<input value={unitReason} onChange={event => { actions.clearError(); setUnitReason(event.target.value) }} placeholder="Informe o motivo da alteração" /></label>
        <button className="button primary" disabled={actions.busy !== null || unitId === (usuario.unidade_id ?? '') || unitReason.trim().length < 5} onClick={() => void changeUnit()}>Salvar unidade</button>
      </section>

      <section className="settings-admin-card" aria-labelledby="profiles-admin-title">
        <div><h4 id="profiles-admin-title">Perfis</h4><p>Atribuições exigem a permissão de gestão de perfis. Alterar os próprios perfis é bloqueado.</p></div>
        {!actions.canManageProfiles ? <p className="settings-muted">Você pode administrar o usuário, mas não possui permissão para alterar perfis.</p> : <>
          <label>Justificativa<input value={profileReason} onChange={event => { actions.clearError(); setProfileReason(event.target.value) }} placeholder="Informe o motivo da alteração de perfil" /></label>
          <div className="settings-profile-actions">
            {data.perfis.map(perfil => {
              const linked = assigned.has(perfil.id)
              return <div className="settings-profile-action" key={perfil.id}><span><strong>{perfil.nome}</strong>{!perfil.ativo && <small>Perfil inativo</small>}</span><button className="button secondary" disabled={actions.busy !== null || isSelf || profileReason.trim().length < 5 || (!linked && !perfil.ativo)} onClick={() => void changeProfile(perfil.id, linked ? 'remover' : 'atribuir')}>{linked ? 'Remover' : 'Atribuir'}</button></div>
            })}
          </div>
        </>}
      </section>
    </div>}

    {pending && <><fieldset className="settings-profile-checks" disabled><legend>Perfis vinculados · somente leitura</legend>
      {data.perfis.length === 0 ? <p>Nenhum perfil disponível para consulta.</p> : data.perfis.map(perfil => <label key={perfil.id}><input type="checkbox" checked={assigned.has(perfil.id)} readOnly /><span>{perfil.nome}{!perfil.ativo && ' (inativo)'}</span></label>)}
      {assigned.size === 0 && <p className="settings-muted">Nenhum vínculo de perfil visível para este usuário.</p>}
    </fieldset><div className="settings-future-actions"><button className="button secondary" disabled>Ativar</button><button className="button secondary" disabled>Inativar</button><button className="button secondary" disabled>Bloquear</button></div></>}
    <p className="settings-muted">Cadastrado em {displayDate(usuario.created_at)}. Toda escrita habilitada nesta tela passa pelo backend auditado.</p>
  </DetailsDialog>
}
