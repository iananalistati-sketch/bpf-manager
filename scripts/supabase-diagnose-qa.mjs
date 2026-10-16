import { diagnoseQa } from './supabase-prepare-qa.mjs'

try {
  if(process.argv.length>2) throw new Error('Diagnostico QA nao aceita argumentos; usa somente BPF_QA_EMAIL e consultas fixas de leitura.')
  process.exitCode=await diagnoseQa()
} catch(error) {
  console.error(error.message)
  process.exitCode=error.exitCode??1
}
