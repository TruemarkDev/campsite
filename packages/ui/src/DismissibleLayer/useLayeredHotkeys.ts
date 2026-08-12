import { DependencyList, useEffect, useId, useMemo } from 'react'
import { atom, useAtomValue, useSetAtom } from 'jotai'
// eslint-disable-next-line no-restricted-imports
import { HotkeyCallback, Keys, Options, useHotkeys } from 'react-hotkeys-hook'

import { useIsTopLayer } from '.'

export interface RegisteredLayeredHotkey {
  description: string
  hotkey: string
  metadata?: Record<string, unknown>
}

type InternalRegisteredLayeredHotkey = RegisteredLayeredHotkey & { registrationId: string }

const registeredLayeredHotkeysAtom = atom<InternalRegisteredLayeredHotkey[]>([])

export function useRegisteredLayeredHotkeys() {
  return useAtomValue(registeredLayeredHotkeysAtom)
}

function useRegisterLayeredHotkeys(keys: Keys, options: Options) {
  const registrationId = useId()
  const setRegisteredHotkeys = useSetAtom(registeredLayeredHotkeysAtom)
  const keysSignature = typeof keys === 'string' ? keys : keys.join(options.delimiter ?? ',')
  const serializedMetadata = JSON.stringify(options.metadata)
  const registrations = useMemo(() => {
    const description = options.description

    if (!description || options.enabled === false) return []

    const hotkeys = keysSignature.split(options.delimiter ?? ',')
    const metadata = serializedMetadata ? JSON.parse(serializedMetadata) : undefined

    return hotkeys.map((hotkey) => ({
      description,
      hotkey: hotkey.trim().toLowerCase(),
      metadata,
      registrationId
    }))
  }, [keysSignature, options.delimiter, options.description, options.enabled, registrationId, serializedMetadata])

  useEffect(() => {
    if (registrations.length === 0) return

    setRegisteredHotkeys((current) => [
      ...current.filter((hotkey) => hotkey.registrationId !== registrationId),
      ...registrations
    ])

    return () => {
      setRegisteredHotkeys((current) => current.filter((hotkey) => hotkey.registrationId !== registrationId))
    }
  }, [registrationId, registrations, setRegisteredHotkeys])
}

export interface LayeredHotkeysProps {
  keys: Keys
  callback: HotkeyCallback
  options?: Options & { repeat?: boolean; skipEscapeWhenDisabled?: boolean }
  dependencies?: DependencyList
}

/**
 * Wraps useHotkeys and automatically disables the hotkey if the layer is not the top layer.
 * Use this hook for hotkeys that should only work when the view layer is open, e.g. list navigation.
 * Do not use it for global hotkeys that should work regardless of the layer.
 */
export function useLayeredHotkeys({
  keys,
  callback,
  options: { repeat, skipEscapeWhenDisabled, ...options } = {},
  dependencies
}: LayeredHotkeysProps) {
  const isTopLayer = useIsTopLayer()

  useRegisterLayeredHotkeys(keys, options)

  useHotkeys(
    keys,
    (keyboardEvent, hotkeysEvent) => {
      /**
       * Ignore repeated keydown events by default. This helps prevent re-submitting forms
       * and aggresively re-running callbacks for users with short key repeat delay settings.
       *
       * @see https://github.com/JohannesKlauss/react-hotkeys-hook/issues/327
       */
      if (!repeat && keyboardEvent.repeat) return

      // some components like Radix popovers and dialogs have custom escape key handling
      // add a custom attribute to prevent global hotkeys from firing alongside
      // https://github.com/radix-ui/primitives/issues/1299
      if (
        skipEscapeWhenDisabled &&
        keyboardEvent.key === 'Escape' &&
        keyboardEvent.target &&
        keyboardEvent.target instanceof HTMLElement &&
        keyboardEvent.target.closest('[disable-escape-layered-hotkeys]')
      ) {
        return
      }

      callback(keyboardEvent, hotkeysEvent)
    },
    {
      ...options,
      // shortcut will always be disabled if the layer is not top layer,
      // regardless of the enabled option passed into this hook
      enabled: isTopLayer ? options.enabled : false
    },
    dependencies
  )
}
