import type { CurrentUser } from '@campsite/types/generated'

const cursorColors = [
  ['bg-blue-500 border-blue-500 text-white', 'bg-blue-500/40'],
  ['bg-green-400 border-green-400 text-black', 'bg-green-400/40'],
  ['bg-yellow-300 border-yellow-300 text-black', 'bg-yellow-300/40'],
  ['bg-red-500 border-red-500 text-white', 'bg-red-500/40'],
  ['bg-purple-300 border-purple-300 text-black', 'bg-purple-300/40'],
  ['bg-pink-500 border-pink-500 text-white', 'bg-pink-500/40'],
  ['bg-indigo-500 border-indigo-500 text-white', 'bg-indigo-500/40'],
  ['bg-teal-300 border-teal-300 text-black', 'bg-teal-300/40']
] as const

export interface CollaborationUser {
  id?: string
  name?: string
  avatarUrl?: string
  customColor?: string
  customSelection?: string
  isAgent?: boolean
}

export function currentUserToCollaborationUser(
  user: Pick<CurrentUser, 'id' | 'display_name' | 'avatar_urls'>
): CollaborationUser {
  const index = (user.display_name.codePointAt(0) ?? 0) % cursorColors.length
  const [customColor, customSelection] = cursorColors[index]

  return {
    id: user.id,
    name: user.display_name,
    avatarUrl: user.avatar_urls.xs,
    customColor,
    customSelection
  }
}

export function renderCollaborationCaret(user: CollaborationUser) {
  const element = document.createElement('div')
  const customColors = user.customColor?.split(' ').filter(Boolean) ?? []

  element.classList.add('collaboration-cursor__caret', ...customColors)

  const label = document.createElement('div')

  label.classList.add('collaboration-cursor__label', ...customColors)

  if (user.avatarUrl) {
    const avatar = document.createElement('img')

    avatar.classList.add('collaboration-cursor__avatar')
    avatar.src = user.avatarUrl
    avatar.alt = ''
    avatar.draggable = false
    label.appendChild(avatar)
  }

  label.appendChild(document.createTextNode(user.name?.trim() || 'Collaborator'))
  element.appendChild(label)

  return element
}
