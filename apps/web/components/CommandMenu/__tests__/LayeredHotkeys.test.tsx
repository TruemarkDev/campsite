import { fireEvent, render } from '@testing-library/react'
import { HotkeysProvider } from 'react-hotkeys-hook'
import { describe, expect, it, vi } from 'vitest'

import { DismissibleLayer, LayeredHotkeys, useRegisteredLayeredHotkeys } from '@campsite/ui'

function RegisteredHotkeysProbe() {
  const hotkeys = useRegisteredLayeredHotkeys()

  return <output data-testid='registered-hotkeys'>{hotkeys.map((hotkey) => hotkey.hotkey).join(',')}</output>
}

describe('LayeredHotkeys', () => {
  it('only invokes the shortcut registered in the top layer', () => {
    const rootCallback = vi.fn()
    const topCallback = vi.fn()

    render(
      <HotkeysProvider>
        <LayeredHotkeys keys='x' callback={rootCallback} options={{ description: 'Root action' }} />
        <DismissibleLayer>
          <div>
            <LayeredHotkeys keys='x' callback={topCallback} />
          </div>
        </DismissibleLayer>
      </HotkeysProvider>
    )

    fireEvent.keyDown(document, { code: 'KeyX', key: 'x' })

    expect(topCallback).toHaveBeenCalledOnce()
    expect(rootCallback).not.toHaveBeenCalled()
  })

  it('does not invoke a background sequence through the top layer', () => {
    const rootCallback = vi.fn()

    const { getByTestId } = render(
      <HotkeysProvider>
        <LayeredHotkeys keys='g>i' callback={rootCallback} options={{ description: 'Go to inbox' }} />
        <RegisteredHotkeysProbe />
        <DismissibleLayer>
          <div>Dialog</div>
        </DismissibleLayer>
      </HotkeysProvider>
    )

    fireEvent.keyDown(document, { code: 'KeyG', key: 'g' })
    fireEvent.keyDown(document, { code: 'KeyI', key: 'i' })

    expect(rootCallback).not.toHaveBeenCalled()
    expect(getByTestId('registered-hotkeys').textContent).toBe('g>i')
  })

  it('ignores shortcuts from custom text inputs and contenteditable elements by default', () => {
    const callback = vi.fn()
    const { getByRole, getByTestId } = render(
      <HotkeysProvider>
        <LayeredHotkeys keys='x' callback={callback} />
        <div role='searchbox' tabIndex={0} />
        <div contentEditable data-testid='editor' />
      </HotkeysProvider>
    )

    const searchbox = getByRole('searchbox')
    const editor = getByTestId('editor')

    // jsdom does not implement these ARIA/contenteditable reflection properties,
    // while the browser and react-hotkeys-hook read them directly.
    Object.defineProperty(searchbox, 'role', { value: 'searchbox' })
    Object.defineProperty(editor, 'isContentEditable', { value: true })

    fireEvent.keyDown(searchbox, { code: 'KeyX', key: 'x' })
    fireEvent.keyDown(editor, { code: 'KeyX', key: 'x' })

    expect(callback).not.toHaveBeenCalled()
  })

  it('can match a user-visible punctuation character explicitly', () => {
    const callback = vi.fn()

    render(
      <HotkeysProvider>
        <LayeredHotkeys keys='/' callback={callback} options={{ useKey: true }} />
      </HotkeysProvider>
    )

    fireEvent.keyDown(document, { code: 'Slash', key: '/' })

    expect(callback).toHaveBeenCalledOnce()
  })

  it('can match a punctuation key by physical position across layouts', () => {
    const callback = vi.fn()

    render(
      <HotkeysProvider>
        <LayeredHotkeys keys='BracketLeft' callback={callback} />
      </HotkeysProvider>
    )

    fireEvent.keyDown(document, { code: 'BracketLeft', key: 'å' })

    expect(callback).toHaveBeenCalledOnce()
  })
})
