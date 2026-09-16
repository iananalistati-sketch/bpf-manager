import { LockKeyhole } from 'lucide-react'
import type { Usuario, UsuariosData } from '../types'
import { displayDate, statusLabels } from '../lib/presentation'
import { DetailsDialog } from './DetailsDialog'
import { StatusBadge } from './StatusBadge'

export function UsuarioDetails({ usuario, data, onClose }: { usuario: Usuario; data: UsuariosData; onClose: () => void }) {
  const assigned = new Set(data.vinculos.filter(link => link.usuario_id === usuario.id).map(link => link.perfil_id))
  return <DetailsDialog title="Detalhes do usuário" onClose={onClose}>
    <div className="settings-detail-intro"><h3>{usuario.nome || 'Nome não informado'}</h3><p>{usuario.email || 'E-mail não informado'}</p><StatusBadge status={usuario.status} /></div>
    {usuario.status === 'pendente' && <p className="settings-notice warning">Este cadastro aguarda aprovação e vínculo organizacional. Nenhum acesso será concedido por esta tela.</p>}
    <p className="settings-notice" id="user-readonly"><LockKeyhole size={18} />Consulta disponível. Alterações de cadastro, status e perfis aguardam habilitação administrativa segura.</p>
    <fieldset className="settings-fields" disabled aria-describedby="user-readonly">
      <legend>Cadastro e acesso · somente leitura</legend>
      <label>Nome<input value={usuario.nome ?? ''} readOnly placeholder="Não informado" /></label>
      <label>E-mail<input value={usuario.email ?? ''} readOnly placeholder="Não informado" /></label>
      <label>Empresa<select value={usuario.empresa_id ?? ''} disabled><option value="">Não vinculada</option>{data.empresas.map(empresa => <option key={empresa.id} value={empresa.id}>{empresa.nome_fantasia || empresa.razao_social}</option>)}</select></label>
      <label>Unidade<select value={usuario.unidade_id ?? ''} disabled><option value="">Não vinculada</option>{data.unidades.map(unidade => <option key={unidade.id} value={unidade.id}>{unidade.nome}{!unidade.ativo && ' (inativa)'}</option>)}</select></label>
      <label>Status<select value={usuario.status} disabled>{Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Situação do cadastro<input value={usuario.ativo ? 'Ativo' : 'Inativo'} readOnly /></label>
    </fieldset>
    <p className="settings-muted">Cadastrado em {displayDate(usuario.created_at)}. Status e situação são exibidos conforme o registro.</p>
    <fieldset className="settings-profile-checks" disabled><legend>Perfis vinculados · somente leitura</legend>
      {data.perfis.length === 0 ? <p>Nenhum perfil disponível para consulta.</p> : data.perfis.map(perfil => <label key={perfil.id}><input type="checkbox" checked={assigned.has(perfil.id)} readOnly /><span>{perfil.nome}{!perfil.ativo && ' (inativo)'}</span></label>)}
      {assigned.size === 0 && <p className="settings-muted">Nenhum vínculo de perfil visível para este usuário.</p>}
    </fieldset>
    <div className="settings-future-actions" aria-describedby="user-readonly"><button className="button secondary" disabled>Ativar</button><button className="button secondary" disabled>Inativar</button><button className="button secondary" disabled>Bloquear</button><button className="button primary" disabled>Salvar alterações</button></div>
  </DetailsDialog>
}
