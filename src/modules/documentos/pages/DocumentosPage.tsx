import { useCallback, useEffect, useMemo, useState } from 'react'
import { CheckCircle2, FileClock, FilePlus2, Files, History, Pencil, RefreshCw, Send, ShieldCheck } from 'lucide-react'
import { useAuth } from '../../../hooks/useAuth'
import { hasPermission } from '../../../lib/permissions'
import { supabase } from '../../../lib/supabase'
import '../documentos.css'

type DocumentoRow = {
  documento_id: string
  empresa_id: string
  unidade_id: string | null
  codigo: string
  titulo: string
  tipo: string
  ativo: boolean
  versao_id: string
  versao_numero: number
  status: 'rascunho' | 'em_revisao' | 'aguardando_aprovacao' | 'aprovado' | 'vigente' | 'obsoleto'
  descricao: string | null
  revisao_prevista_em: string | null
  autor_id: string
  revisor_id: string | null
  aprovador_id: string | null
  vigencia_inicio: string | null
  updated_at: string
}

type HistoricoRow = {
  versao_id: string
  numero: number
  status: DocumentoRow['status']
  descricao: string | null
  motivo_revisao: string | null
  revisao_prevista_em: string | null
  aprovado_em: string | null
  vigencia_inicio: string | null
  obsoleto_em: string | null
  updated_at: string
}

const statusLabel: Record<DocumentoRow['status'], string> = {
  rascunho: 'Rascunho',
  em_revisao: 'Em revisão',
  aguardando_aprovacao: 'Aguardando aprovação',
  aprovado: 'Aprovado',
  vigente: 'Vigente',
  obsoleto: 'Obsoleto',
}

const statusTone: Record<DocumentoRow['status'], string> = {
  rascunho: 'neutral',
  em_revisao: 'blue',
  aguardando_aprovacao: 'orange',
  aprovado: 'purple',
  vigente: 'green',
  obsoleto: 'neutral',
}

const nextAction = (status: DocumentoRow['status']) => {
  if (status === 'rascunho') return { target: 'em_revisao', label: 'Enviar para revisão' }
  if (status === 'em_revisao') return { target: 'aguardando_aprovacao', label: 'Concluir revisão' }
  if (status === 'aguardando_aprovacao') return { target: 'aprovado', label: 'Aprovar' }
  if (status === 'aprovado') return { target: 'vigente', label: 'Publicar' }
  return null
}

export function DocumentosPage() {
  const { contexto, empresaAtivaId, workspaceCommercial } = useAuth()
  const [rows, setRows] = useState<DocumentoRow[]>([])
  const [loading, setLoading] = useState(true)
  const [feedback, setFeedback] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<DocumentoRow | null>(null)
  const [codigo, setCodigo] = useState('')
  const [titulo, setTitulo] = useState('')
  const [tipo, setTipo] = useState('POP')
  const [descricao, setDescricao] = useState('')
  const [revisaoPrevista, setRevisaoPrevista] = useState('')
  const [usarUnidadeAtual, setUsarUnidadeAtual] = useState(true)
  const [actionDoc, setActionDoc] = useState<DocumentoRow | null>(null)
  const [actionMode, setActionMode] = useState<'transition' | 'revision' | null>(null)
  const [justificativa, setJustificativa] = useState('')
  const [historyDoc, setHistoryDoc] = useState<DocumentoRow | null>(null)
  const [historyRows, setHistoryRows] = useState<HistoricoRow[]>([])
  const [busy, setBusy] = useState(false)

  const readOnly = workspaceCommercial?.modo_acesso === 'somente_leitura'
  const canCreate = hasPermission(contexto, 'documentos.criar') && !readOnly
  const canEdit = hasPermission(contexto, 'documentos.editar') && !readOnly
  const canApprove = hasPermission(contexto, 'documentos.aprovar') && !readOnly

  const loadRows = useCallback(async () => {
    if (!empresaAtivaId) return
    setLoading(true)
    setFeedback(null)
    const { data, error } = await supabase.rpc('documentos_listar', {
      p_empresa_id: empresaAtivaId,
      p_unidade_id: null,
    })
    if (error) {
      setRows([])
      setFeedback('Não foi possível carregar os documentos controlados.')
    } else {
      setRows((Array.isArray(data) ? data : []) as DocumentoRow[])
    }
    setLoading(false)
  }, [empresaAtivaId])

  useEffect(() => { void loadRows() }, [loadRows])

  const metrics = useMemo(() => ({
    total: rows.length,
    vigentes: rows.filter(row => row.status === 'vigente').length,
    pendentes: rows.filter(row => ['rascunho','em_revisao','aguardando_aprovacao','aprovado'].includes(row.status)).length,
    revisar: rows.filter(row => row.revisao_prevista_em && new Date(row.revisao_prevista_em) <= new Date(Date.now() + 30 * 86400000)).length,
  }), [rows])

  const resetForm = () => {
    setEditing(null)
    setCodigo('')
    setTitulo('')
    setTipo('POP')
    setDescricao('')
    setRevisaoPrevista('')
    setUsarUnidadeAtual(true)
    setShowForm(false)
  }

  const openCreate = () => {
    resetForm()
    setShowForm(true)
  }

  const openEdit = (row: DocumentoRow) => {
    setEditing(row)
    setCodigo(row.codigo)
    setTitulo(row.titulo)
    setTipo(row.tipo)
    setDescricao(row.descricao ?? '')
    setRevisaoPrevista(row.revisao_prevista_em ?? '')
    setUsarUnidadeAtual(Boolean(row.unidade_id))
    setShowForm(true)
  }

  const saveDocument = async () => {
    if (!empresaAtivaId || titulo.trim().length < 3 || tipo.trim().length < 2 || (!editing && codigo.trim().length < 2)) {
      setFeedback('Preencha código, título e tipo corretamente.')
      return
    }
    setBusy(true)
    setFeedback(null)
    const unidadeId = usarUnidadeAtual ? contexto?.unidade_id ?? null : null
    const { error } = editing
      ? await supabase.rpc('documento_rascunho_atualizar', {
        p_documento_id: editing.documento_id,
        p_unidade_id: unidadeId,
        p_titulo: titulo.trim(),
        p_tipo: tipo.trim(),
        p_descricao: descricao.trim(),
        p_revisao_prevista_em: revisaoPrevista || null,
      })
      : await supabase.rpc('documento_criar', {
        p_empresa_id: empresaAtivaId,
        p_unidade_id: unidadeId,
        p_codigo: codigo.trim(),
        p_titulo: titulo.trim(),
        p_tipo: tipo.trim(),
        p_descricao: descricao.trim(),
        p_revisao_prevista_em: revisaoPrevista || null,
      })

    if (error) setFeedback(error.message.toLowerCase().includes('duplicate') ? 'Já existe um documento ativo com este código.' : 'Não foi possível salvar o documento.')
    else {
      resetForm()
      setFeedback(editing ? 'Rascunho atualizado.' : 'Documento criado como rascunho.')
      await loadRows()
    }
    setBusy(false)
  }

  const openTransition = (row: DocumentoRow) => {
    setActionDoc(row)
    setActionMode('transition')
    setJustificativa('')
  }

  const openRevision = (row: DocumentoRow) => {
    setActionDoc(row)
    setActionMode('revision')
    setJustificativa('')
  }

  const submitAction = async () => {
    if (!actionDoc || justificativa.trim().length < 5) {
      setFeedback('Informe uma justificativa com pelo menos 5 caracteres.')
      return
    }
    setBusy(true)
    const transition = nextAction(actionDoc.status)
    const { error } = actionMode === 'revision'
      ? await supabase.rpc('documento_iniciar_revisao', {
        p_documento_id: actionDoc.documento_id,
        p_motivo_revisao: justificativa.trim(),
        p_revisao_prevista_em: null,
      })
      : await supabase.rpc('documento_transicionar', {
        p_documento_id: actionDoc.documento_id,
        p_status_destino: transition?.target,
        p_justificativa: justificativa.trim(),
      })

    if (error) setFeedback('Não foi possível concluir a ação documental.')
    else {
      setFeedback(actionMode === 'revision' ? 'Nova revisão iniciada como rascunho.' : 'Status do documento atualizado.')
      setActionDoc(null)
      setActionMode(null)
      setJustificativa('')
      await loadRows()
    }
    setBusy(false)
  }

  const loadHistory = async (row: DocumentoRow) => {
    const { data, error } = await supabase.rpc('documento_historico', { p_documento_id: row.documento_id })
    if (error) {
      setFeedback('Não foi possível carregar o histórico do documento.')
      return
    }
    setHistoryDoc(row)
    setHistoryRows((Array.isArray(data) ? data : []) as HistoricoRow[])
  }

  return <div className="documents-page">
    <div className="page-heading">
      <div><span className="eyebrow">QUALIDADE</span><h1>Documentos</h1><p>Controle versões, revisão, aprovação, vigência e histórico dos documentos de BPF.</p></div>
      {canCreate && <button className="button primary" onClick={openCreate}><FilePlus2 size={16} />Novo documento</button>}
    </div>

    {readOnly && <div className="documents-readonly" role="status"><ShieldCheck size={18} /><span>O workspace está em somente leitura. O histórico documental permanece disponível, mas novas alterações estão bloqueadas.</span></div>}
    {feedback && <div className="documents-feedback" role="status">{feedback}</div>}

    <section className="documents-metrics" aria-label="Indicadores documentais">
      <article className="panel"><span>Total controlado</span><strong>{metrics.total}</strong><Files size={19} /></article>
      <article className="panel"><span>Vigentes</span><strong>{metrics.vigentes}</strong><CheckCircle2 size={19} /></article>
      <article className="panel"><span>Em fluxo</span><strong>{metrics.pendentes}</strong><Send size={19} /></article>
      <article className="panel"><span>Revisão em até 30 dias</span><strong>{metrics.revisar}</strong><FileClock size={19} /></article>
    </section>

    {showForm && <section className="panel documents-form" aria-label={editing ? 'Editar rascunho' : 'Novo documento'}>
      <div className="panel-heading"><div><h2>{editing ? 'Editar rascunho' : 'Novo documento controlado'}</h2><p>O código identifica o documento e permanece estável entre revisões.</p></div></div>
      <div className="documents-form-grid">
        <label>Código<input value={codigo} disabled={Boolean(editing)} onChange={event => setCodigo(event.target.value)} placeholder="POP-001" /></label>
        <label>Tipo<input value={tipo} onChange={event => setTipo(event.target.value)} placeholder="POP" /></label>
        <label className="span-2">Título<input value={titulo} onChange={event => setTitulo(event.target.value)} placeholder="Título do documento" /></label>
        <label>Revisão prevista<input type="date" value={revisaoPrevista} onChange={event => setRevisaoPrevista(event.target.value)} /></label>
        <label className="documents-checkbox"><input type="checkbox" checked={usarUnidadeAtual} onChange={event => setUsarUnidadeAtual(event.target.checked)} />Vincular à unidade atual</label>
        <label className="span-2">Descrição<textarea rows={4} value={descricao} onChange={event => setDescricao(event.target.value)} placeholder="Resumo ou orientação principal desta versão." /></label>
      </div>
      <div className="documents-form-actions"><button className="button secondary" onClick={resetForm}>Cancelar</button><button className="button primary" disabled={busy} onClick={() => void saveDocument()}>{busy ? 'Salvando…' : 'Salvar rascunho'}</button></div>
    </section>}

    <section className="panel documents-list">
      <div className="panel-heading"><div><h2>Documentos controlados</h2><p>Versão mais recente de cada código documental.</p></div><button className="icon-button" aria-label="Atualizar documentos" onClick={() => void loadRows()}><RefreshCw size={17} /></button></div>
      {loading ? <div className="documents-empty">Carregando documentos…</div>
        : rows.length === 0 ? <div className="documents-empty"><Files size={28} /><strong>Nenhum documento cadastrado</strong><span>Crie o primeiro documento controlado para iniciar o fluxo de revisão e aprovação.</span></div>
          : <div className="documents-table">
            <div className="documents-table-head"><span>Documento</span><span>Versão</span><span>Status</span><span>Revisão prevista</span><span>Ações</span></div>
            {rows.map(row => {
              const transition = nextAction(row.status)
              const canTransition = transition && ((['rascunho','em_revisao'].includes(row.status) && canEdit) || (['aguardando_aprovacao','aprovado'].includes(row.status) && canApprove))
              return <article className="documents-row" key={row.documento_id}>
                <div><strong>{row.codigo} · {row.titulo}</strong><small>{row.tipo}{row.unidade_id ? ' · Unidade vinculada' : ' · Escopo empresarial'}</small></div>
                <span>v{row.versao_numero}</span>
                <span className={`badge ${statusTone[row.status]}`}>{statusLabel[row.status]}</span>
                <span>{row.revisao_prevista_em ? new Date(`${row.revisao_prevista_em}T12:00:00`).toLocaleDateString('pt-BR') : '—'}</span>
                <div className="documents-actions">
                  <button className="icon-button" title="Histórico" aria-label={`Histórico de ${row.codigo}`} onClick={() => void loadHistory(row)}><History size={16} /></button>
                  {row.status === 'rascunho' && canEdit && <button className="icon-button" title="Editar rascunho" aria-label={`Editar ${row.codigo}`} onClick={() => openEdit(row)}><Pencil size={16} /></button>}
                  {canTransition && <button className="button secondary" onClick={() => openTransition(row)}>{transition.label}</button>}
                  {row.status === 'vigente' && canEdit && <button className="button secondary" onClick={() => openRevision(row)}>Iniciar revisão</button>}
                </div>
              </article>
            })}
          </div>}
    </section>

    {actionDoc && actionMode && <section className="panel documents-action-panel" aria-label="Confirmar ação documental">
      <div><strong>{actionDoc.codigo} · {actionDoc.titulo}</strong><p>{actionMode === 'revision' ? 'Informe o motivo para abrir uma nova versão em rascunho.' : `Confirme a transição: ${nextAction(actionDoc.status)?.label ?? ''}.`}</p></div>
      <textarea aria-label="Justificativa" rows={3} value={justificativa} onChange={event => setJustificativa(event.target.value)} placeholder="Justificativa obrigatória" />
      <div className="documents-form-actions"><button className="button secondary" onClick={() => { setActionDoc(null); setActionMode(null) }}>Cancelar</button><button className="button primary" disabled={busy} onClick={() => void submitAction()}>{busy ? 'Processando…' : 'Confirmar'}</button></div>
    </section>}

    {historyDoc && <section className="panel documents-history" aria-label={`Histórico de ${historyDoc.codigo}`}>
      <div className="panel-heading"><div><h2>Histórico · {historyDoc.codigo}</h2><p>As versões anteriores permanecem preservadas para auditoria.</p></div><button className="button secondary" onClick={() => setHistoryDoc(null)}>Fechar</button></div>
      <div className="documents-history-list">{historyRows.map(version => <div key={version.versao_id}><div><strong>Versão {version.numero}</strong><span className={`badge ${statusTone[version.status]}`}>{statusLabel[version.status]}</span></div><small>{version.motivo_revisao || 'Versão inicial'} · Atualizada em {new Date(version.updated_at).toLocaleString('pt-BR')}</small></div>)}</div>
    </section>}
  </div>
}
