import { ShieldCheck, CalendarCheck2, Clock3, CircleAlert, Wrench, GraduationCap } from 'lucide-react'
export const metrics = [
  { label: 'Conformidade BPF', value: '94%', detail: 'Meta de conformidade: 90%', icon: ShieldCheck, tone: 'green' },
  { label: 'Atividades hoje', value: '12', detail: '4 concluídas · 8 em andamento', icon: CalendarCheck2, tone: 'blue' },
  { label: 'Atividades vencidas', value: '3', detail: 'Precisam da sua atenção', icon: Clock3, tone: 'red' },
  { label: 'Não conformidades abertas', value: '5', detail: 'Planos de ação em acompanhamento', icon: CircleAlert, tone: 'orange' },
  { label: 'Calibrações próximas', value: '4', detail: 'Previstas para os próximos 30 dias', icon: Wrench, tone: 'purple' },
  { label: 'Treinamentos pendentes', value: '7', detail: 'Capacitações a realizar', icon: GraduationCap, tone: 'blue' },
]
export const activities = [
  { time: '08:00', title: 'Inspeção de recebimento de matérias-primas', area: 'Recebimentos', owner: 'Ana Silva', initials: 'AS', status: 'Concluída', tone: 'green', path: '/recebimentos' },
  { time: '09:30', title: 'Verificação de higienização da linha 01', area: 'Higienização', owner: 'Carlos Lima', initials: 'CL', status: 'Em andamento', tone: 'blue', path: '/higienizacao' },
  { time: '11:00', title: 'Coleta de água para análise', area: 'Água', owner: 'Mariana Costa', initials: 'MC', status: 'Pendente', tone: 'orange', path: '/agua' },
  { time: '14:00', title: 'Treinamento de boas práticas de fabricação', area: 'Treinamentos', owner: 'Ana Silva', initials: 'AS', status: 'Pendente', tone: 'orange', path: '/treinamentos' },
]
export const conformity = [
  { label: 'Documentação', value: 98 }, { label: 'Higienização', value: 96 },
  { label: 'Controle de pragas', value: 100 }, { label: 'Equipamentos', value: 90 }, { label: 'Treinamentos', value: 86 },
]
