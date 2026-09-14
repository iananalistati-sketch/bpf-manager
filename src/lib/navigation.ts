import { LayoutDashboard, CalendarDays, Files, Truck, PackageCheck, SprayCan, GraduationCap, Droplets, Wrench, Bug, Recycle, CircleAlert, Factory, Route, ClipboardCheck, ChartNoAxesCombined, Settings } from 'lucide-react'
import type { NavigationGroup } from '../types/navigation'

export const navigationGroups: NavigationGroup[] = [
  { title: 'GESTÃO', items: [
    { path: '/dashboard', title: 'Dashboard', description: 'Acompanhe os indicadores da sua unidade.', icon: LayoutDashboard },
    { path: '/agenda', title: 'Agenda', description: 'Organize as atividades, os prazos e as rotinas de BPF da sua unidade.', icon: CalendarDays },
  ] },
  { title: 'QUALIDADE', items: [
    { path: '/documentos', title: 'Documentos', description: 'Centralize procedimentos, manuais e registros de boas práticas de fabricação.', icon: Files },
    { path: '/fornecedores', title: 'Fornecedores', description: 'Acompanhe a qualificação e a avaliação dos fornecedores de matérias-primas e serviços.', icon: Truck },
    { path: '/recebimentos', title: 'Recebimentos', description: 'Organize as inspeções de recebimento de ingredientes, insumos e embalagens.', icon: PackageCheck },
    { path: '/higienizacao', title: 'Higienização', description: 'Acompanhe os planos e os registros de limpeza dos ambientes e equipamentos.', icon: SprayCan },
    { path: '/treinamentos', title: 'Treinamentos', description: 'Planeje capacitações e acompanhe os registros de treinamento da equipe.', icon: GraduationCap },
    { path: '/agua', title: 'Água', description: 'Acompanhe o controle de qualidade da água, as coletas e as análises da unidade.', icon: Droplets },
    { path: '/equipamentos', title: 'Equipamentos', description: 'Organize o cadastro, as manutenções e as calibrações dos equipamentos.', icon: Wrench },
    { path: '/pragas', title: 'Pragas', description: 'Monitore as ações preventivas e os registros de controle integrado de pragas.', icon: Bug },
    { path: '/residuos', title: 'Resíduos', description: 'Acompanhe a segregação, a coleta e a destinação dos resíduos da operação.', icon: Recycle },
    { path: '/nao-conformidades', title: 'Não Conformidades', description: 'Registre desvios e acompanhe a investigação e os planos de ação corretiva.', icon: CircleAlert },
  ] },
  { title: 'OPERAÇÃO', items: [
    { path: '/producao', title: 'Produção', description: 'Acompanhe os registros de fabricação e os controles de processo dos alimentos para animais.', icon: Factory },
    { path: '/rastreabilidade', title: 'Rastreabilidade', description: 'Consulte o histórico dos lotes, desde as matérias-primas até o produto acabado.', icon: Route },
  ] },
  { title: 'ANÁLISE', items: [
    { path: '/auditorias', title: 'Auditorias', description: 'Planeje auditorias e organize checklists, evidências e resultados das avaliações.', icon: ClipboardCheck },
    { path: '/relatorios', title: 'Relatórios', description: 'Explore os indicadores e os resultados da gestão de BPF da sua unidade.', icon: ChartNoAxesCombined },
  ] },
  { title: 'ADMINISTRAÇÃO', items: [
    { path: '/configuracoes', title: 'Configurações', description: 'Organize as preferências da plataforma e as informações da sua unidade.', icon: Settings },
  ] },
]
