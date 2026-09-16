import { CircleAlert, LoaderCircle, SearchX } from 'lucide-react'

export function QueryFeedback({ loading, error, onRetry, empty }: {
  loading?: boolean; error?: string | null; onRetry?: () => void; empty?: string
}) {
  return <div className="settings-feedback" role={error ? 'alert' : 'status'}>
    {loading ? <LoaderCircle size={26} className="settings-spinner" /> : error ? <CircleAlert size={26} /> : <SearchX size={26} />}
    <h3>{loading ? 'Carregando dados…' : error ? 'Não foi possível carregar' : 'Nenhum registro encontrado'}</h3>
    <p>{loading ? 'Consultando os registros disponíveis para seu acesso.' : error ?? empty}</p>
    {error && onRetry && <button className="button secondary" onClick={onRetry}>Tentar novamente</button>}
  </div>
}
