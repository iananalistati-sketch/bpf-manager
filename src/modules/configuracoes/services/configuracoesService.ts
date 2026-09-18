import type { SupabaseClient } from '@supabase/supabase-js'
import { hasPermission } from '../../../lib/permissions'
import type { MeuContexto, UsuarioStatus } from '../../../types/auth'
import type { Empresa, Perfil, PerfilPermissao, PerfisData, Permissao, ReadScope, Unidade, Usuario, UsuarioPerfil, UsuariosData } from '../types'

const PAGE_SIZE = 500
type Page<T> = { data: T[] | null; error: { message: string } | null; count: number | null }
type PerfilAction = 'atribuir' | 'remover'

async function readAll<T>(query: (from: number, to: number) => PromiseLike<Page<T>>, signal: AbortSignal): Promise<T[]> {
  const rows: T[] = []
  for (;;) {
    signal.throwIfAborted()
    const result = await query(rows.length, rows.length + PAGE_SIZE - 1)
    if (result.error || !result.data || result.count === null) {
      throw new Error('Não foi possível consultar os dados. Verifique sua conexão e suas permissões e tente novamente.')
    }
    rows.push(...result.data)
    if (rows.length >= result.count) return rows
    if (!result.data.length) throw new Error('A consulta retornou dados incompletos. Atualize a listagem.')
  }
}

function validateUuid(value: string, label: string) {
  if (!/^[0-9a-f-]{36}$/i.test(value)) throw new Error(`${label} inválido.`)
}

function validateJustification(value: string) {
  if (value.trim().length < 5) throw new Error('Informe uma justificativa com pelo menos 5 caracteres.')
}

function mutationError(message?: string) {
  const text = message ?? ''
  const known = [
    'Sem permissao para administrar usuarios',
    'Sem permissao para gerir perfis de usuarios',
    'Usuario pendente exige fluxo de vinculacao/aprovacao dedicado',
    'Nao e permitido inativar ou bloquear o proprio usuario',
    'Nao e permitido alterar o proprio perfil administrativo',
    'Operacao removeria o ultimo administrador efetivo da empresa',
    'Unidade invalida, inativa ou fora da empresa',
    'Perfil fora do escopo autorizado',
    'Perfil inativo nao pode ser atribuido',
    'Perfil ja atribuido ao usuario',
    'Perfil nao esta atribuido ao usuario',
    'Nenhuma alteracao de status identificada',
    'Nenhuma alteracao de unidade identificada',
  ]
  const matched = known.find(item => text.includes(item))
  if (matched) return matched
    .replace('Nao ', 'Não ')
    .replace('nao ', 'não ')
    .replace('Usuario', 'Usuário')
    .replace('usuario', 'usuário')
    .replace('permissao', 'permissão')
    .replace('gestao', 'gestão')
    .replace('vinculacao', 'vinculação')
    .replace('aprovacao', 'aprovação')
    .replace('Operacao', 'Operação')
    .replace('removeria', 'removeria')
    .replace('ultimo', 'último')
    .replace('invalida', 'inválida')
    .replace('atribuido', 'atribuído')
  return 'Não foi possível concluir a alteração. Atualize os dados e tente novamente.'
}

export function createConfiguracoesService(client: SupabaseClient) {
  async function authorize(scope: ReadScope, permission: string, signal: AbortSignal) {
    const { data, error } = await client.from('v_meu_contexto').select('*')
      .abortSignal(signal).maybeSingle<MeuContexto>()
    if (error) throw new Error('Não foi possível validar seu acesso. Atualize a sessão e tente novamente.')
    if (!data || data.usuario_id !== scope.usuarioId || data.empresa_id !== scope.empresaId
      || !hasPermission(data, 'configuracoes.visualizar') || !hasPermission(data, permission)) {
      throw new Error('Seu acesso a esta área não está mais disponível. Atualize a sessão.')
    }
    validateUuid(scope.empresaId, 'Empresa de acesso')
  }

  async function authorizeMutation(scope: ReadScope, permission: string) {
    const controller = new AbortController()
    await authorize(scope, permission, controller.signal)
  }

  const readProfiles = (scope: ReadScope, signal: AbortSignal) => readAll<Perfil>((from, to) => client
    .from('perfis').select('id,empresa_id,nome,descricao,is_system,ativo', { count: 'exact' })
    .or(`empresa_id.eq.${scope.empresaId},and(empresa_id.is.null,is_system.eq.true)`)
    .order('nome').order('id').range(from, to).abortSignal(signal).returns<Perfil[]>(), signal)

  return {
    async usuarios(scope: ReadScope, signal: AbortSignal): Promise<UsuariosData> {
      await authorize(scope, 'usuarios.gerenciar', signal)
      const [usuarios, empresas, unidades, perfis] = await Promise.all([
        readAll<Usuario>((from, to) => client.from('usuarios')
          .select('id,nome,email,empresa_id,unidade_id,status,ativo,created_at', { count: 'exact' })
          .eq('empresa_id', scope.empresaId).order('created_at').order('id')
          .range(from, to).abortSignal(signal).returns<Usuario[]>(), signal),
        readAll<Empresa>((from, to) => client.from('empresas')
          .select('id,nome_fantasia,razao_social', { count: 'exact' }).eq('id', scope.empresaId)
          .order('id').range(from, to).abortSignal(signal).returns<Empresa[]>(), signal),
        readAll<Unidade>((from, to) => client.from('unidades')
          .select('id,empresa_id,nome,ativo', { count: 'exact' }).eq('empresa_id', scope.empresaId)
          .order('nome').order('id').range(from, to).abortSignal(signal).returns<Unidade[]>(), signal),
        readProfiles(scope, signal),
      ])
      const vinculos: UsuarioPerfil[] = []
      for (let start = 0; start < usuarios.length; start += 100) {
        vinculos.push(...await readAll<UsuarioPerfil>((from, to) => client.from('usuario_perfis')
          .select('usuario_id,perfil_id', { count: 'exact' }).in('usuario_id', usuarios.slice(start, start + 100).map(user => user.id))
          .order('usuario_id').order('perfil_id').range(from, to).abortSignal(signal).returns<UsuarioPerfil[]>(), signal))
      }
      return { usuarios, empresas, unidades, perfis, vinculos }
    },
    async perfis(scope: ReadScope, signal: AbortSignal): Promise<PerfisData> {
      await authorize(scope, 'perfis.gerenciar', signal)
      const [perfis, permissoes] = await Promise.all([
        readProfiles(scope, signal),
        readAll<Permissao>((from, to) => client.from('permissoes')
          .select('id,codigo,modulo,acao,descricao', { count: 'exact' })
          .order('modulo').order('acao').order('id').range(from, to).abortSignal(signal).returns<Permissao[]>(), signal),
      ])
      const vinculos: PerfilPermissao[] = []
      for (let start = 0; start < perfis.length; start += 100) {
        vinculos.push(...await readAll<PerfilPermissao>((from, to) => client.from('perfil_permissoes')
          .select('perfil_id,permissao_id', { count: 'exact' }).in('perfil_id', perfis.slice(start, start + 100).map(perfil => perfil.id))
          .order('perfil_id').order('permissao_id').range(from, to).abortSignal(signal).returns<PerfilPermissao[]>(), signal))
      }
      return { perfis, permissoes, vinculos }
    },
    async alterarStatus(scope: ReadScope, usuarioId: string, status: Exclude<UsuarioStatus, 'pendente'>, justificativa: string) {
      validateUuid(usuarioId, 'Usuário')
      validateJustification(justificativa)
      await authorizeMutation(scope, 'usuarios.gerenciar')
      const { error } = await client.rpc('admin_usuario_alterar_status', {
        p_usuario_id: usuarioId, p_status: status, p_justificativa: justificativa.trim(),
      })
      if (error) throw new Error(mutationError(error.message))
    },
    async alterarUnidade(scope: ReadScope, usuarioId: string, unidadeId: string | null, justificativa: string) {
      validateUuid(usuarioId, 'Usuário')
      if (unidadeId) validateUuid(unidadeId, 'Unidade')
      validateJustification(justificativa)
      await authorizeMutation(scope, 'usuarios.gerenciar')
      const { error } = await client.rpc('admin_usuario_alterar_unidade', {
        p_usuario_id: usuarioId, p_unidade_id: unidadeId, p_justificativa: justificativa.trim(),
      })
      if (error) throw new Error(mutationError(error.message))
    },
    async alterarPerfil(scope: ReadScope, usuarioId: string, perfilId: string, acao: PerfilAction, justificativa: string) {
      validateUuid(usuarioId, 'Usuário')
      validateUuid(perfilId, 'Perfil')
      validateJustification(justificativa)
      await authorizeMutation(scope, 'perfis.gerenciar')
      const { error } = await client.rpc('admin_usuario_alterar_perfil', {
        p_usuario_id: usuarioId, p_perfil_id: perfilId, p_acao: acao, p_justificativa: justificativa.trim(),
      })
      if (error) throw new Error(mutationError(error.message))
    },
  }
}
