import { useEffect } from 'react'
import { render, screen } from '@testing-library/react'
import { useAtomValue, useSetAtom } from 'jotai'
import { ScopeProvider } from 'jotai-scope'
import { describe, expect, it } from 'vitest'

import { setZoomAtom, zoomAtom, zoomStateAtom } from './atom'

function ZoomHarness() {
  const zoom = useAtomValue(zoomAtom)
  const setZoom = useSetAtom(setZoomAtom)

  useEffect(() => {
    setZoom({ viewport: { width: 1310, height: 1137 } })
  }, [setZoom])

  return <output>{`${zoom.viewport.width}×${zoom.viewport.height}`}</output>
}

describe('zoom state scope', () => {
  it('shares viewport writes with the lightbox zoom reader', async () => {
    render(
      <ScopeProvider atoms={[zoomStateAtom]}>
        <ZoomHarness />
      </ScopeProvider>
    )

    expect(await screen.findByText('1310×1137')).toBeTruthy()
  })
})
