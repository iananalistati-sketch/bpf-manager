import type { SupabaseClient } from '@supabase/supabase-js'
import { hasPermission } from '../../../lib/permissions'
import type { MeuContexto, UsuarioStatus } from '../../../types/auth'
import type {
  AuditoriaData, AuditoriaEvento, Empresa, EstruturaData, Perfil, PerfilPermissao, PerfisData,
  Permissao, PlanoData, PlanoEntitlement, PlanoResumo, ReadScope, Setor, Unidade, Usuario, UsuarioPerfil, UsuariosData,
} from '../types'

const PAGE_SIZE = 500
type Page<T> = { data: T[] | null; error: { message: string } | null; count: number | null }
type PerfilAction = 'atribuir' | 'remover'

async function readAll<T>(query: (from: number, to: number) => PromiseLike<Page<T>>, signal: AbortSignal): Promise<T[]> {
  const rows: T[] = []
  for (;;) {
    signal.throwIfAborted()
    const result = await query(rows.length, rows.length + PAGE_SIZE - 1)
    if (result.error || !result.data || result.count === null) throw new Error('Não foi possível consultar os dados. Verifique sua conexão e suas permissões e tente novamente.')
    rows.push(...result.data)
    if (rows.length >= result.count) return rows
    if (!result.data.length) throw new Error('A consulta retornou dados incompletos. Atualize a listagem.')
  }
}
function validateUuid(value: string, label: string) { if (!/^[0-9a-f-]{36}$/i.test(value)) throw new Error(`${label} inválido.`) }
function validateJustification(value: string) { if (value.trim().length < 5) throw new Error('Informe uma justificativa com pelo menos 5 caracteres.') }
function validateName(value: string, label: string) { if (value.trim().length < 2) throw new Error(`${label} deve possuir pelo menos 2 caracteres.`) }
function mutationError(message?: string) {
  const text = message ?? ''
  const known = ['Sem permissao para administrar usuarios','Sem permissao para gerir perfis de usuarios','Sem permissao para convidar usuarios','Sem permissao para convidar usuarios no tenant selecionado','Sem permissao para gerenciar estrutura','Limite de usuarios ativos do plano atingido','Usuario pendente exige fluxo de vinculacao/aprovacao dedicado','Nao e permitido inativar ou bloquear o proprio usuario','Nao e permitido alterar o proprio perfil administrativo','Nao e permitido delegar um perfil com permissoes superiores as do ator','Nao e permitido conceder uma permissao que o ator nao possui','Perfil em uso por usuarios ativos deve ser desvinculado antes de alterar permissoes','Operacao removeria o ultimo administrador efetivo da empresa','Unidade invalida, inativa ou fora da empresa','Unidade possui usuarios ativos vinculados','Unidade nao encontrada no escopo autorizado','Setor nao encontrado no escopo autorizado','Unidade fora do escopo autorizado','Perfil fora do escopo autorizado','Perfil de sistema ou fora do escopo nao pode ser alterado','Perfil possui usuarios ativos vinculados','Perfil inativo nao pode ser atribuido','Perfil ja atribuido ao usuario','Perfil nao esta atribuido ao usuario','Nenhuma alteracao de status identificada','Nenhuma alteracao de unidade identificada','Convite pendente nao encontrado','Selecione ao menos um perfil','Perfil invalido, inativo ou fora da empresa','Razao social invalida','Nome da unidade invalido','Nome do setor invalido','Nome do perfil invalido','Permissao invalida']
  const matched = known.find(item => text.includes(item))
  if (!matched) return 'Não foi possível concluir a alteração. Atualize os dados e tente novamente.'
  return matched.replaceAll('Nao','Não').replaceAll('nao','não').replaceAll('Usuario','Usuário').replaceAll('usuarios','usuários').replaceAll('usuario','usuário').replaceAll('permissoes','permissões').replaceAll('permissao','permissão').replaceAll('Permissao','Permissão').replaceAll('gestao','gestão').replaceAll('vinculacao','vinculação').replaceAll('aprovacao','aprovação').replaceAll('Operacao','Operação').replaceAll('ultimo','último').replaceAll('invalida','inválida').replaceAll('atribuido','atribuído').replaceAll('Razao','Razão')
}
async function edgeFunctionMessage(error: unknown) {
  const response = (error as { context?: Response } | null)?.context
  if (!response) return null
  try { const payload = await response.clone().json() as { error?: unknown }; return typeof payload.error === 'string' ? payload.error : null } catch { return null }
}

export function createConfiguracoesService(client: SupabaseClient) {
  async function authorize(scope: ReadScope, permission: string, signal: AbortSignal) {
    validateUuid(scope.empresaId, 'Empresa de acesso')
    const legacy = await client.from('v_meu_contexto').select('*').abortSignal(signal).maybeSingle<MeuContexto>()
    if (legacy.error) throw new Error('Não foi possível validar seu acesso. Atualize a sessão e tente novamente.')
    let data = legacy.data
    if (!data || data.empresa_id !== scope.empresaId) {
      const tenant = await client.rpc('meu_contexto_empresa', { p_empresa_id: scope.empresaId }).abortSignal(signal).maybeSingle<MeuContexto>()
      if (tenant.error) throw new Error('Não foi possível validar a empresa ativa. Atualize a sessão e tente novamente.')
      data = tenant.data
    }
    if (!data || data.usuario_id !== scope.usuarioId || data.empresa_id !== scope.empresaId || !hasPermission(data,'configuracoes.visualizar') || !hasPermission(data,permission)) throw new Error('Seu acesso a esta área não está mais disponível. Atualize a sessão.')
    return data
  }
  async function authorizeMutation(scope: ReadScope, permission: string) { return authorize(scope, permission, new AbortController().signal) }
  const readProfiles = (scope: ReadScope, signal: AbortSignal) => readAll<Perfil>((from,to)=>client.from('perfis').select('id,empresa_id,nome,descricao,is_system,ativo',{count:'exact'}).or(`empresa_id.eq.${scope.empresaId},and(empresa_id.is.null,is_system.eq.true)`).order('nome').order('id').range(from,to).abortSignal(signal).returns<Perfil[]>(),signal)
  return {
    async usuarios(scope: ReadScope, signal: AbortSignal): Promise<UsuariosData> {
      await authorize(scope,'usuarios.gerenciar',signal)
      const [usuarios,empresas,unidades,perfis]=await Promise.all([
        readAll<Usuario>((from,to)=>client.from('usuarios').select('id,nome,email,empresa_id,unidade_id,status,ativo,created_at',{count:'exact'}).eq('empresa_id',scope.empresaId).order('created_at').order('id').range(from,to).abortSignal(signal).returns<Usuario[]>(),signal),
        readAll<Empresa>((from,to)=>client.from('empresas').select('id,nome_fantasia,razao_social,cnpj,ativo',{count:'exact'}).eq('id',scope.empresaId).order('id').range(from,to).abortSignal(signal).returns<Empresa[]>(),signal),
        readAll<Unidade>((from,to)=>client.from('unidades').select('id,empresa_id,nome,codigo,ativo',{count:'exact'}).eq('empresa_id',scope.empresaId).order('nome').order('id').range(from,to).abortSignal(signal).returns<Unidade[]>(),signal),
        readProfiles(scope,signal),
      ])
      const vinculos: UsuarioPerfil[]=[]
      for(let start=0;start<usuarios.length;start+=100) vinculos.push(...await readAll<UsuarioPerfil>((from,to)=>client.from('usuario_perfis').select('usuario_id,perfil_id',{count:'exact'}).in('usuario_id',usuarios.slice(start,start+100).map(user=>user.id)).order('usuario_id').order('perfil_id').range(from,to).abortSignal(signal).returns<UsuarioPerfil[]>(),signal))
      return {usuarios,empresas,unidades,perfis,vinculos}
    },
    async perfis(scope: ReadScope, signal: AbortSignal): Promise<PerfisData> {
      await authorize(scope,'perfis.gerenciar',signal)
      const [perfis,permissoes]=await Promise.all([readProfiles(scope,signal),readAll<Permissao>((from,to)=>client.from('permissoes').select('id,codigo,modulo,acao,descricao',{count:'exact'}).order('modulo').order('acao').order('id').range(from,to).abortSignal(signal).returns<Permissao[]>(),signal)])
      const vinculos: PerfilPermissao[]=[]
      for(let start=0;start<perfis.length;start+=100) vinculos.push(...await readAll<PerfilPermissao>((from,to)=>client.from('perfil_permissoes').select('perfil_id,permissao_id',{count:'exact'}).in('perfil_id',perfis.slice(start,start+100).map(perfil=>perfil.id)).order('perfil_id').order('permissao_id').range(from,to).abortSignal(signal).returns<PerfilPermissao[]>(),signal))
      return {perfis,permissoes,vinculos}
    },
    async estrutura(scope: ReadScope, signal: AbortSignal): Promise<EstruturaData> {
      await authorize(scope,'estrutura.gerenciar',signal)
      const [empresas,unidades,setores]=await Promise.all([
        readAll<Empresa>((from,to)=>client.from('empresas').select('id,nome_fantasia,razao_social,cnpj,ativo',{count:'exact'}).eq('id',scope.empresaId).range(from,to).abortSignal(signal).returns<Empresa[]>(),signal),
        readAll<Unidade>((from,to)=>client.from('unidades').select('id,empresa_id,nome,codigo,ativo',{count:'exact'}).eq('empresa_id',scope.empresaId).order('nome').range(from,to).abortSignal(signal).returns<Unidade[]>(),signal),
        readAll<Setor>((from,to)=>client.from('setores').select('id,unidade_id,nome,codigo,ativo',{count:'exact'}).order('nome').range(from,to).abortSignal(signal).returns<Setor[]>(),signal),
      ])
      if(!empresas[0]) throw new Error('A empresa da sua sessão não foi encontrada.')
      const unitIds=new Set(unidades.map(item=>item.id)); return {empresa:empresas[0],unidades,setores:setores.filter(item=>unitIds.has(item.unidade_id))}
    },
    async auditoria(scope: ReadScope, signal: AbortSignal): Promise<AuditoriaData> {
      const context=await authorize(scope,'auditoria.visualizar',signal)
      const eventos=await readAll<AuditoriaEvento>((from,to)=>client.from('auditoria_eventos').select('id,empresa_id,unidade_id,ator_id,entidade,registro_id,acao,antes,depois,justificativa,contexto,created_at',{count:'exact'}).eq('empresa_id',scope.empresaId).order('created_at',{ascending:false}).range(from,to).abortSignal(signal).returns<AuditoriaEvento[]>(),signal)
      const usuarios=hasPermission(context,'usuarios.gerenciar')?await readAll<Pick<Usuario,'id'|'nome'|'email'>>((from,to)=>client.from('usuarios').select('id,nome,email',{count:'exact'}).eq('empresa_id',scope.empresaId).order('id').range(from,to).abortSignal(signal).returns<Pick<Usuario,'id'|'nome'|'email'>[]>(),signal):[]
      return {eventos,usuarios}
    },
    async plano(scope: ReadScope, signal: AbortSignal): Promise<PlanoData> {
      await authorize(scope,'configuracoes.visualizar',signal)
      const [resumoResult,entitlementsResult]=await Promise.all([
        client.rpc('meu_plano_resumo',{p_empresa_id:scope.empresaId}).abortSignal(signal).maybeSingle<PlanoResumo>(),
        client.rpc('meu_plano_entitlements',{p_empresa_id:scope.empresaId}).abortSignal(signal),
      ])
      if(resumoResult.error||!resumoResult.data) throw new Error('Não foi possível carregar o resumo comercial da empresa.')
      if(entitlementsResult.error||!Array.isArray(entitlementsResult.data)) throw new Error('Não foi possível carregar os limites do plano.')
      const entitlements = entitlementsResult.data as PlanoEntitlement[]
      return {resumo:resumoResult.data,entitlements}
    },
    async alterarStatus(scope: ReadScope, usuarioId: string, status: Exclude<UsuarioStatus,'pendente'>, justificativa: string) { validateUuid(usuarioId,'Usuário');validateJustification(justificativa);await authorizeMutation(scope,'usuarios.gerenciar');const {error}=await client.rpc('admin_usuario_alterar_status',{p_usuario_id:usuarioId,p_status:status,p_justificativa:justificativa.trim()});if(error) throw new Error(mutationError(error.message)) },
    async alterarUnidade(scope: ReadScope, usuarioId: string, unidadeId: string|null, justificativa: string) { validateUuid(usuarioId,'Usuário');if(unidadeId)validateUuid(unidadeId,'Unidade');validateJustification(justificativa);await authorizeMutation(scope,'usuarios.gerenciar');const {error}=await client.rpc('admin_usuario_alterar_unidade',{p_usuario_id:usuarioId,p_unidade_id:unidadeId,p_justificativa:justificativa.trim()});if(error) throw new Error(mutationError(error.message)) },
    async alterarPerfil(scope: ReadScope, usuarioId: string, perfilId: string, acao: PerfilAction, justificativa: string) { validateUuid(usuarioId,'Usuário');validateUuid(perfilId,'Perfil');validateJustification(justificativa);await authorizeMutation(scope,'perfis.gerenciar');const {error}=await client.rpc('admin_usuario_alterar_perfil',{p_usuario_id:usuarioId,p_perfil_id:perfilId,p_acao:acao,p_justificativa:justificativa.trim()});if(error) throw new Error(mutationError(error.message)) },
    async convidarUsuario(scope: ReadScope,input:{email:string;nome:string;unidadeId:string|null;perfilIds:string[];justificativa:string}) {
      if(!/^\S+@\S+\.\S+$/.test(input.email.trim())) throw new Error('Informe um e-mail válido.')
      validateName(input.nome,'Nome');if(input.unidadeId)validateUuid(input.unidadeId,'Unidade');if(!input.perfilIds.length)throw new Error('Selecione ao menos um perfil.');input.perfilIds.forEach(id=>validateUuid(id,'Perfil'));validateJustification(input.justificativa);await authorizeMutation(scope,'usuarios.convidar')
      const {data,error}=await client.functions.invoke('admin-invite-user',{body:{empresaId:scope.empresaId,email:input.email.trim().toLowerCase(),nome:input.nome.trim(),unidadeId:input.unidadeId,perfilIds:input.perfilIds,justificativa:input.justificativa.trim()}})
      if(error){const detail=await edgeFunctionMessage(error);throw new Error(detail??'Não foi possível enviar o convite. Verifique a sessão e tente novamente.')}
      if(data?.error)throw new Error(typeof data.error==='string'?data.error:'Não foi possível concluir o convite.');return data as {userId:string;email:string;empresaId:string}
    },
    async perfilCriar(scope: ReadScope,nome:string,descricao:string,permissaoIds:string[],justificativa:string){validateName(nome,'Nome do perfil');permissaoIds.forEach(id=>validateUuid(id,'Permissão'));validateJustification(justificativa);await authorizeMutation(scope,'perfis.gerenciar');const {data,error}=await client.rpc('admin_perfil_criar',{p_nome:nome.trim(),p_descricao:descricao.trim(),p_permissao_ids:permissaoIds,p_justificativa:justificativa.trim()});if(error)throw new Error(mutationError(error.message));return data as string},
    async perfilAtualizar(scope: ReadScope,perfilId:string,nome:string,descricao:string,ativo:boolean,permissaoIds:string[],justificativa:string){validateUuid(perfilId,'Perfil');validateName(nome,'Nome do perfil');permissaoIds.forEach(id=>validateUuid(id,'Permissão'));validateJustification(justificativa);await authorizeMutation(scope,'perfis.gerenciar');const {error}=await client.rpc('admin_perfil_atualizar',{p_perfil_id:perfilId,p_nome:nome.trim(),p_descricao:descricao.trim(),p_ativo:ativo,p_permissao_ids:permissaoIds,p_justificativa:justificativa.trim()});if(error)throw new Error(mutationError(error.message))},
    async empresaAtualizar(scope: ReadScope,razaoSocial:string,nomeFantasia:string,cnpj:string,justificativa:string){validateName(razaoSocial,'Razão social');validateJustification(justificativa);await authorizeMutation(scope,'estrutura.gerenciar');const {error}=await client.rpc('admin_empresa_atualizar',{p_razao_social:razaoSocial.trim(),p_nome_fantasia:nomeFantasia.trim(),p_cnpj:cnpj.trim(),p_justificativa:justificativa.trim()});if(error)throw new Error(mutationError(error.message))},
    async unidadeSalvar(scope: ReadScope,unidadeId:string|null,nome:string,codigo:string,ativo:boolean,justificativa:string){if(unidadeId)validateUuid(unidadeId,'Unidade');validateName(nome,'Nome da unidade');validateJustification(justificativa);await authorizeMutation(scope,'estrutura.gerenciar');const {data,error}=await client.rpc('admin_unidade_salvar',{p_unidade_id:unidadeId,p_nome:nome.trim(),p_codigo:codigo.trim(),p_ativo:ativo,p_justificativa:justificativa.trim()});if(error)throw new Error(mutationError(error.message));return data as string},
    async setorSalvar(scope: ReadScope,setorId:string|null,unidadeId:string,nome:string,codigo:string,ativo:boolean,justificativa:string){if(setorId)validateUuid(setorId,'Setor');validateUuid(unidadeId,'Unidade');validateName(nome,'Nome do setor');validateJustification(justificativa);await authorizeMutation(scope,'estrutura.gerenciar');const {data,error}=await client.rpc('admin_setor_salvar',{p_setor_id:setorId,p_unidade_id:unidadeId,p_nome:nome.trim(),p_codigo:codigo.trim(),p_ativo:ativo,p_justificativa:justificativa.trim()});if(error)throw new Error(mutationError(error.message));return data as string},
  }
}
