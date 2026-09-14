import { ArrowLeft, Construction } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { NavigationItem } from '../types/navigation'
export function ModulePage({ module }: { module?: NavigationItem }) {
  const Icon = module?.icon ?? Construction
  return <><div className="page-heading"><div><span className="eyebrow">BPF MANAGER</span><h1>{module?.title ?? 'Página não encontrada'}</h1><p>{module?.description ?? 'O endereço acessado não corresponde a uma página da plataforma.'}</p></div></div>
    <section className="panel empty-state"><span className="empty-icon"><Icon size={32} /></span><span className="badge neutral">{module ? 'Em preparação' : 'Erro 404'}</span><h2>{module ? `Seu espaço de ${module.title.toLocaleLowerCase('pt-BR')}` : 'Vamos voltar ao início?'}</h2><p>{module ? 'Este módulo receberá os registros e as ferramentas para apoiar a rotina da sua equipe. Por enquanto, explore a navegação e a visão geral da unidade.' : 'Acesse o dashboard ou escolha um módulo no menu lateral.'}</p><Link className="button secondary" to="/dashboard"><ArrowLeft size={16} />Voltar ao dashboard</Link></section></>
}
