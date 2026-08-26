import { describe, expect, it } from 'vitest'

import { currentUserToCollaborationUser, renderCollaborationCaret } from './collaborationUser'

describe('collaboration user presence', () => {
  it('publishes the current user display name and avatar with the existing cursor colors', () => {
    expect(
      currentUserToCollaborationUser({
        id: 'user-123',
        display_name: 'Ada Lovelace',
        avatar_urls: {
          xs: 'https://example.com/ada-xs.png',
          sm: 'https://example.com/ada-sm.png',
          base: 'https://example.com/ada-base.png',
          lg: 'https://example.com/ada-lg.png',
          xl: 'https://example.com/ada-xl.png',
          xxl: 'https://example.com/ada-xxl.png'
        }
      })
    ).toEqual({
      id: 'user-123',
      name: 'Ada Lovelace',
      avatarUrl: 'https://example.com/ada-xs.png',
      customColor: 'bg-green-400 border-green-400 text-black',
      customSelection: 'bg-green-400/40'
    })
  })

  it('renders the collaborator name and avatar without exposing an id as fallback text', () => {
    const caret = renderCollaborationCaret({
      id: 'user-123',
      name: 'Ada Lovelace',
      avatarUrl: 'https://example.com/ada.png',
      customColor: 'bg-green-400 border-green-400 text-black'
    })

    expect(caret.textContent).toBe('Ada Lovelace')
    expect(caret.querySelector('img')).toMatchObject({
      alt: '',
      draggable: false,
      src: 'https://example.com/ada.png'
    })

    expect(renderCollaborationCaret({ id: 'user-123' }).textContent).toBe('Collaborator')
  })
})
