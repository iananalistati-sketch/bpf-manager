import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { ArrowRight, ClipboardCheck, Factory, ShieldCheck } from 'lucide-react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Brand } from '../components/Brand'
import { useAuth } from '../hooks/useAuth'
import { supabase } from '../lib/supabase'

export function OnboardingPage() {
  const { contexto, empresaAtivaId, workspaceCommercial, loading, refreshContexto, signOut } = useAuth()
  const navigate = useNavigate()
  const [responsavelTecnico, setResponsavelTecnico] = useState('')
  const [tipoOperacao, setTipoOperacao] = useState('')
  const [setores, setSetores] = useState('')
  const [observacoes, setObservacoes] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => { document.title = 'Configuração inicial | BPF Manager' }, [])

  const setoresNormalizados = useMemo(
    () => setores.split(',').map(item => item.trim()).filter(Boolean),
    [setores],
  )

  if (loading) return <main className="auth-state-page"><section className="auth-state-card panel"><p>Carregando configuração inicial...</p></section></main>
  if (!empresaAtivaId || !contexto?.empresa_id) return <Navigate to="/iniciar-trial" replace />
  if (!workspaceCommercial) return <Navigate to="/dashboard" replace />
  if (workspaceCommercial.modo_acesso !== 'normal' || workspaceCommercial.onboarding_status === 'concluido') return <Navigate to="/dashboard" replace />

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSubmitting(true)
    setError(null)

    try {
      const { error: rpcError } = await supabase.rpc('atualizar_meu_onboarding', {
        p_empresa_id: empresaAtivaId,
        p_etapa_atual: 'concluido',
        p_dados: {
          responsavel_tecnico: responsavelTecnico.trim(),
          tipo_operacao: tipoOperacao,
          setores: setoresNormalizados,
          observacoes: observacoes.trim() || null,
        },
        p_concluir: true,
      })

      if (rpcError) {
        setError(
          rpcError.message.toLowerCase().includes('owner')
            ? 'Somente o responsável principal do workspace pode concluir esta configuração.'
            : 'Não foi possível concluir a configuração inicial. Tente novamente.',
        )
        return
      }

      await refreshContexto()
      navigate('/dashboard', { replace: true })
    } finally {
      setSubmitting(false)
    }
  }

  return <main className="login-page">
    <section className="onboarding-card panel">
      <Brand />
      <span className="empty-icon"><ClipboardCheck size={34} /></span>

      <div className="trial-heading">
        <h1>Configure o primeiro acesso</h1>
        <p>Seu workspace já foi criado. Complete estas informações para personalizar o início da operação.</p>
      </div>

      <div className="onboarding-summary" aria-label="Resumo do workspace">
        <span><Factory size={16} /> <strong>{contexto.nome_fantasia ?? contexto.razao_social}</strong></span>
        <span><ShieldCheck size={16} /> Trial: {workspaceCommercial.dias_trial_restantes} dia(s) restante(s)</span>
      </div>

      <form className="login-form" onSubmit={handleSubmit}>
        <label>
          <span>Responsável técnico</span>
          <input
            value={responsavelTecnico}
            onChange={event => setResponsavelTecnico(event.target.value)}
            minLength={2}
            maxLength={140}
            placeholder="Nome do responsável técnico"
            required
          />
        </label>

        <label>
          <span>Tipo de operação</span>
          <select value={tipoOperacao} onChange={event => setTipoOperacao(event.target.value)} required>
            <option value="">Selecione</option>
            <option value="fabricacao">Fabricação</option>
            <option value="armazenamento">Armazenamento</option>
            <option value="distribuicao">Distribuição</option>
            <option value="mista">Operação mista</option>
            <option value="outra">Outra</option>
          </select>
        </label>

        <label>
          <span>Setores principais</span>
          <input
            value={setores}
            onChange={event => setSetores(event.target.value)}
            placeholder="Recebimento, Produção, Qualidade"
            required
          />
          <small>Separe os setores por vírgula.</small>
        </label>

        <label>
          <span>Observações iniciais (opcional)</span>
          <textarea
            rows={3}
            value={observacoes}
            onChange={event => setObservacoes(event.target.value)}
            placeholder="Informações úteis para a configuração inicial"
          />
        </label>

        <p className="onboarding-note">Depois, você poderá convidar outros usuários e detalhar estrutura, documentos e rotinas em Configurações.</p>
        {error && <p className="login-error" role="alert">{error}</p>}

        <button className="button primary" type="submit" disabled={submitting || setoresNormalizados.length === 0}>
          {submitting ? 'Concluindo configuração...' : <>Concluir e acessar o BPF Manager <ArrowRight size={18} /></>}
        </button>
      </form>

      <button className="text-link auth-mode-switch" type="button" onClick={() => void signOut()}>
        Sair e continuar depois
      </button>
    </section>
  </main>
}
