import { useEffect } from 'react'
import { ArrowRight, ShieldCheck } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Brand } from '../components/Brand'
export function LoginPage() {
  useEffect(() => { document.title = 'Login | BPF Manager' }, [])
  return <main className="login-page"><section className="login-card panel"><Brand /><span className="empty-icon"><ShieldCheck size={34} /></span><h1>Qualidade em cada etapa.</h1><p>Boas práticas, processos organizados e uma visão completa da sua operação em um só lugar.</p><div className="login-notice"><strong>Acesso demonstrativo</strong><p>Explore a interface como Administrador da Unidade Principal. O acesso com credenciais estará disponível em uma próxima etapa.</p></div><Link className="button primary" to="/dashboard">Explorar plataforma<ArrowRight size={18} /></Link><small>Gestão de BPF para indústrias de alimentação animal</small></section></main>
}
