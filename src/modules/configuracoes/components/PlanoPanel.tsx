import { CreditCard, Gauge, RefreshCw, Users, Warehouse } from 'lucide-react'
import { usePlano } from '../hooks/useConfiguracoesQuery'
import { QueryFeedback } from './QueryFeedback'

const entitlementLabel: Record<string, string> = {
  'usuarios_ativos.max': 'Usuários ativos',
  'unidades.max': 'Unidades ativas',
}

function usageText(value: number, max: number | null) {
  return max === null ? `${value} / sem limite definido` : `${value} / ${max}`
}

export function PlanoPanel() {
  const query = usePlano()
  if (!query.allowed) return <QueryFeedback error="Você não possui acesso às informações comerciais desta empresa." />
  if (query.loading || query.error || !query.data) return <QueryFeedback loading={query.loading} error={query.error} onRetry={query.reload} />

  const { resumo, entitlements } = query.data
  const hasPlan = Boolean(resumo.plano_id)

  return <>
    <div className="settings-section-heading">
      <div><h2>Plano e uso</h2><p>Consulte o plano atribuído à empresa e o consumo dos limites comerciais aplicados no backend.</p></div>
      <button className="button secondary" onClick={query.reload}><RefreshCw size={15} />Atualizar</button>
    </div>

    {!hasPlan && <div className="settings-notice warning"><CreditCard size={19} /><p><strong>Nenhum plano atribuído.</strong> Esta empresa continua operando sem limites comerciais até existir uma atribuição de plano, assinatura ou trial.</p></div>}

    <div className="settings-plan-summary">
      <article className="settings-plan-card">
        <span className="metric-icon green"><CreditCard size={22} /></span>
        <div><small>Plano atual</small><strong>{resumo.plano_nome || 'Sem plano atribuído'}</strong><p>{resumo.origem ? `Origem: ${resumo.origem}` : 'Aguardando configuração comercial'}</p></div>
      </article>
      <article className="settings-plan-card">
        <span className="metric-icon blue"><Users size={22} /></span>
        <div><small>Usuários ativos</small><strong>{usageText(resumo.usuarios_ativos, resumo.usuarios_ativos_max)}</strong><p>Contagem consolidada por empresa</p></div>
      </article>
      <article className="settings-plan-card">
        <span className="metric-icon purple"><Warehouse size={22} /></span>
        <div><small>Unidades ativas</small><strong>{usageText(resumo.unidades_ativas, resumo.unidades_max)}</strong><p>Limite validado no banco</p></div>
      </article>
    </div>

    <section className="settings-plan-entitlements" aria-label="Recursos e limites do plano">
      <div className="settings-section-heading compact"><div><h3><Gauge size={18} /> Recursos e limites</h3><p>Entitlements configuráveis; perfil de usuário continua sendo controlado separadamente por RBAC.</p></div></div>
      {!entitlements.length ? <p className="settings-muted">Nenhum entitlement está associado ao plano atual.</p> : <div className="settings-plan-list">
        {entitlements.map(item => <div key={item.chave ?? item.plano_id} className="settings-plan-row">
          <div><strong>{item.chave ? entitlementLabel[item.chave] || item.chave : 'Plano sem entitlement'}</strong><small>{item.chave || item.plano_codigo}</small></div>
          <span className="badge neutral">{item.tipo === 'inteiro' ? item.valor_inteiro : item.tipo === 'booleano' ? (item.valor_booleano ? 'Habilitado' : 'Desabilitado') : item.valor_texto || '—'}</span>
        </div>)}
      </div>}
    </section>
  </>
}
