import type { SupabaseClient } from '@supabase/supabase-js'
import { hasPermission } from '../../../lib/permissions'
import type { MeuContexto } from '../../../types/auth'
import type { Empresa, Perfil, PerfilPermissao, PerfisData, Permissao, ReadScope, Unidade, Usuario, UsuarioPerfil, UsuariosData } from '../types'

const PAGE_SIZE = 500
type Page<T> = { data: T[] | null; error: { message: string } | null; count: number | null }

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

// Somente SELECT com o cliente autenticado; não existem métodos de escrita neste serviço.
// Filtros de empresa reduzem o escopo, mas nunca substituem as políticas RLS.
export function createConfiguracoesService(client: SupabaseClient) {
  async function authorize(scope: ReadScope, permission: string, signal: AbortSignal) {
    const { data, error } = await client.from('v_meu_contexto').select('*')
      .abortSignal(signal).maybeSingle<MeuContexto>()
    if (error) throw new Error('Não foi possível validar seu acesso. Atualize a sessão e tente novamente.')
    if (!data || data.usuario_id !== scope.usuarioId || data.empresa_id !== scope.empresaId
      || !hasPermission(data, 'configuracoes.visualizar') || !hasPermission(data, permission)) {
      throw new Error('Seu acesso a esta área não está mais disponível. Atualize a sessão.')
    }
    if (!/^[0-9a-f-]{36}$/i.test(scope.empresaId)) throw new Error('Empresa de acesso inválida.')
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
      // Lotes evitam URLs longas e a paginação evita truncar vínculos silenciosamente.
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
  }
}
