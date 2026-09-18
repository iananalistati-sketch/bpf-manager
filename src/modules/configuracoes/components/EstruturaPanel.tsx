import { useState } from 'react'
import { Building2, Pencil, Plus, RefreshCw } from 'lucide-react'
import { useAdministracaoActions, useEstrutura } from '../hooks/useConfiguracoesQuery'
import type { Setor, Unidade } from '../types'
import { DetailsDialog } from './DetailsDialog'
import { QueryFeedback } from './QueryFeedback'

function UnidadeDialog({ unidade, onClose, onSaved }: { unidade: Unidade | null; onClose: () => void; onSaved: () => void }) {
  const actions = useAdministracaoActions()
  const [nome, setNome] = useState(unidade?.nome ?? '')
  const [codigo, setCodigo] = useState(unidade?.codigo ?? '')
  const [ativo, setAtivo] = useState(unidade?.ativo ?? true)
  const [justificativa, setJustificativa] = useState('')
  const save = async () => {
    const result = await actions.unidadeSalvar(unidade?.id ?? null, nome, codigo, ativo, justificativa)
    if (!result.ok) return
    onSaved(); onClose()
  }
  return <DetailsDialog title={unidade ? 'Editar unidade' : 'Nova unidade'} onClose={onClose}>
    {actions.error && <p className="settings-notice warning" role="alert">{actions.error}</p>}
    <div className="settings-fields"><label>Nome<input autoFocus value={nome} onChange={event => setNome(event.target.value)} /></label><label>Código<input value={codigo} onChange={event => setCodigo(event.target.value)} /></label><label>Situação<select value={ativo ? 'ativo' : 'inativo'} onChange={event => setAtivo(event.target.value === 'ativo')}><option value="ativo">Ativa</option><option value="inativo">Inativa</option></select></label><label>Justificativa<input value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Motivo da alteração" /></label></div>
    <button className="button primary" disabled={nome.trim().length < 2 || justificativa.trim().length < 5 || actions.busy !== null} onClick={() => void save()}>{actions.busy ? 'Salvando…' : 'Salvar unidade'}</button>
  </DetailsDialog>
}

function SetorDialog({ setor, unidades, initialUnitId, onClose, onSaved }: { setor: Setor | null; unidades: Unidade[]; initialUnitId?: string; onClose: () => void; onSaved: () => void }) {
  const actions = useAdministracaoActions()
  const [unidadeId, setUnidadeId] = useState(setor?.unidade_id ?? initialUnitId ?? unidades.find(item => item.ativo)?.id ?? '')
  const [nome, setNome] = useState(setor?.nome ?? '')
  const [codigo, setCodigo] = useState(setor?.codigo ?? '')
  const [ativo, setAtivo] = useState(setor?.ativo ?? true)
  const [justificativa, setJustificativa] = useState('')
  const save = async () => {
    const result = await actions.setorSalvar(setor?.id ?? null, unidadeId, nome, codigo, ativo, justificativa)
    if (!result.ok) return
    onSaved(); onClose()
  }
  return <DetailsDialog title={setor ? 'Editar setor' : 'Novo setor'} onClose={onClose}>
    {actions.error && <p className="settings-notice warning" role="alert">{actions.error}</p>}
    <div className="settings-fields"><label>Unidade<select value={unidadeId} onChange={event => setUnidadeId(event.target.value)}>{unidades.map(item => <option key={item.id} value={item.id}>{item.nome}{!item.ativo && ' (inativa)'}</option>)}</select></label><label>Nome<input autoFocus value={nome} onChange={event => setNome(event.target.value)} /></label><label>Código<input value={codigo} onChange={event => setCodigo(event.target.value)} /></label><label>Situação<select value={ativo ? 'ativo' : 'inativo'} onChange={event => setAtivo(event.target.value === 'ativo')}><option value="ativo">Ativo</option><option value="inativo">Inativo</option></select></label><label className="settings-field-wide">Justificativa<input value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Motivo da alteração" /></label></div>
    <button className="button primary" disabled={!unidadeId || nome.trim().length < 2 || justificativa.trim().length < 5 || actions.busy !== null} onClick={() => void save()}>{actions.busy ? 'Salvando…' : 'Salvar setor'}</button>
  </DetailsDialog>
}

export function EstruturaPanel() {
  const query = useEstrutura()
  const actions = useAdministracaoActions()
  const [editingUnit, setEditingUnit] = useState<Unidade | null | undefined>(undefined)
  const [editingSector, setEditingSector] = useState<Setor | null | undefined>(undefined)
  const [newSectorUnit, setNewSectorUnit] = useState<string | undefined>()
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso à estrutura organizacional." />
  if (query.loading || query.error || !query.data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />
  const { empresa, unidades, setores } = query.data
  const [razao, setRazao] = useState(empresa.razao_social)
  const [fantasia, setFantasia] = useState(empresa.nome_fantasia ?? '')
  const [cnpj, setCnpj] = useState(empresa.cnpj ?? '')
  const [companyReason, setCompanyReason] = useState('')
  const saveCompany = async () => {
    const result = await actions.empresaAtualizar(razao, fantasia, cnpj, companyReason)
    if (result.ok) { setCompanyReason(''); query.reload() }
  }
  return <>
    <div className="settings-section-heading"><div><h2>Estrutura organizacional</h2><p>Administre os dados da empresa, suas unidades e setores.</p></div><div className="settings-heading-actions"><button className="button primary" onClick={() => setEditingUnit(null)}><Plus size={15} />Nova unidade</button><button className="button secondary" onClick={query.reload}><RefreshCw size={15} />Atualizar</button></div></div>
    <p className="settings-notice"><Building2 size={19} /><span><strong>Escopo da empresa atual.</strong> Nenhuma operação desta área pode criar ou alterar estrutura de outra empresa. Todas as mudanças são auditadas.</span></p>
    {(actions.error || actions.success) && <p className={`settings-notice${actions.error ? ' warning' : ''}`} role={actions.error ? 'alert' : 'status'}>{actions.error || actions.success}</p>}

    <section className="settings-admin-card"><div><h3>Empresa</h3><p>Dados cadastrais utilizados no contexto organizacional.</p></div><div className="settings-fields"><label>Razão social<input value={razao} onChange={event => setRazao(event.target.value)} /></label><label>Nome fantasia<input value={fantasia} onChange={event => setFantasia(event.target.value)} /></label><label>CNPJ<input value={cnpj} onChange={event => setCnpj(event.target.value)} placeholder="Opcional" /></label><label>Justificativa<input value={companyReason} onChange={event => setCompanyReason(event.target.value)} placeholder="Motivo da alteração" /></label></div><button className="button primary" disabled={razao.trim().length < 2 || companyReason.trim().length < 5 || actions.busy !== null} onClick={() => void saveCompany()}>Salvar empresa</button></section>

    <div className="settings-structure-grid">{unidades.map(unidade => <article className="settings-structure-card" key={unidade.id}><div className="settings-user-heading"><div><h3>{unidade.nome}</h3><p>{unidade.codigo || 'Sem código'}</p></div><span className={`badge ${unidade.ativo ? 'green' : 'neutral'}`}>{unidade.ativo ? 'Ativa' : 'Inativa'}</span></div><div className="settings-heading-actions"><button className="button secondary" onClick={() => setEditingUnit(unidade)}><Pencil size={14} />Editar</button><button className="button secondary" onClick={() => { setNewSectorUnit(unidade.id); setEditingSector(null) }}><Plus size={14} />Setor</button></div><div className="settings-sector-list">{setores.filter(setor => setor.unidade_id === unidade.id).map(setor => <button key={setor.id} className="settings-sector-row" onClick={() => setEditingSector(setor)}><span><strong>{setor.nome}</strong><small>{setor.codigo || 'Sem código'}</small></span><span className={`badge ${setor.ativo ? 'green' : 'neutral'}`}>{setor.ativo ? 'Ativo' : 'Inativo'}</span></button>)}{!setores.some(setor => setor.unidade_id === unidade.id) && <p className="settings-muted">Nenhum setor cadastrado.</p>}</div></article>)}</div>
    {!unidades.length && <QueryFeedback empty="Nenhuma unidade cadastrada para esta empresa." />}
    {editingUnit !== undefined && <UnidadeDialog unidade={editingUnit} onClose={() => setEditingUnit(undefined)} onSaved={query.reload} />}
    {editingSector !== undefined && <SetorDialog setor={editingSector} unidades={unidades} initialUnitId={newSectorUnit} onClose={() => { setEditingSector(undefined); setNewSectorUnit(undefined) }} onSaved={query.reload} />}
  </>
}
