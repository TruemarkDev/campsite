import { useEffect, useRef, useState, lazy, Suspense } from 'react'

// Lazy load the Lottie player to prevent SSR issues
const LottieLightLazy = lazy(() => import('react-lottie-player/dist/LottiePlayerLight').then(module => ({ default: module.default })))

interface Props {
  url: string
  onLoad?: (animationItem: any) => void
  onError?: () => void
  onFrame?: (frame: number) => void
  className?: string
}

function LottieLoader() {
  return <div className="w-full h-full animate-pulse bg-gray-100" />
}

export function Lottie(props: Props) {
  const { url, onLoad, onError, onFrame, className = 'w-full h-full' } = props
  const ref = useRef(null)
  const [animationItem, setAnimationItem] = useState<any>(null)
  const [loaded, setLoaded] = useState(false)
  const [_frame, setFrame] = useState(0)

  useEffect(() => {
    if (loaded) {
      const player = ref.current as any

      setAnimationItem(player)
      onLoad?.(player)
    }
  }, [ref, loaded, onLoad])

  const handleLoad = () => {
    setLoaded(true)
  }

  const handleEnterFrame = () => {
    const percentage = (animationItem?.currentFrame / animationItem?.totalFrames) * 100

    setFrame(percentage)
    onFrame?.(percentage)
  }

  return (
    <Suspense fallback={<LottieLoader />}>
      <LottieLightLazy
        ref={ref}
        path={url}
        play
        loop
        onEnterFrame={handleEnterFrame}
        onLoad={handleLoad}
        onError={onError}
        className={className}
      />
    </Suspense>
  )
}
