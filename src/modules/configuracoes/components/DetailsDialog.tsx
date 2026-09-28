import { useEffect, useId, useRef, type ReactNode } from 'react'
import { X } from 'lucide-react'

export function DetailsDialog({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null)
  const heading = useId()
  useEffect(() => {
    const dialog = ref.current
    const previous = document.activeElement as HTMLElement | null
    dialog?.showModal()
    return () => { dialog?.close(); previous?.focus() }
  }, [])
  return <dialog ref={ref} className="settings-dialog" aria-labelledby={heading}
    onCancel={event => { event.preventDefault(); onClose() }}
    onClick={event => { if (event.target === event.currentTarget) onClose() }}>
    <div className="settings-dialog-content">
      <header className="settings-dialog-heading"><h2 id={heading}>{title}</h2><button autoFocus className="icon-button" onClick={onClose} aria-label="Fechar detalhes"><X size={20} /></button></header>
      {children}
      <footer className="settings-dialog-footer"><button className="button secondary" onClick={onClose}>Fechar</button></footer>
    </div>
  </dialog>
}
