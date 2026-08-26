import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { CustomReactionsPacks } from '@/components/OrgSettings/OrganizationReactions/CustomReactionsPacks'
import { useGetCustomReactionsPacks } from '@/hooks/useGetCustomReactionsPacks'

vi.mock('@/hooks/useGetCustomReactionsPacks', () => ({
  useGetCustomReactionsPacks: vi.fn()
}))

describe('CustomReactionsPacks', () => {
  beforeEach(() => {
    vi.mocked(useGetCustomReactionsPacks).mockReturnValue({
      data: [
        { name: 'blobs', installed: false, items: [] },
        { name: 'memes', installed: false, items: [] }
      ],
      isLoading: false
    } as unknown as ReturnType<typeof useGetCustomReactionsPacks>)
  })

  it('renders an unavailable state when object storage has no pack assets', () => {
    render(<CustomReactionsPacks />)

    expect(screen.getByText('Emoji packs are not available in this environment.')).toBeTruthy()
  })
})
