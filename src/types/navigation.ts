import type { LucideIcon } from 'lucide-react'

export interface NavigationItem {
  path: string
  title: string
  description: string
  icon: LucideIcon
  permission: string
}

export interface NavigationGroup {
  title: string
  items: NavigationItem[]
}
