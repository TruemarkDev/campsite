import { Toaster } from 'react-hot-toast'

export function ToasterProvider() {
  const position = 'bottom-center'

  return (
    <Toaster
      containerClassName='toaster-container'
      position={position}
      toastOptions={{
        // Define default options
        duration: 5000,
        // can't use tailwind classes because of conflicts with default toast styles
        style: {
          background: '#000',
          color: '#fff',
          fontWeight: '500',
          fontSize: '14px',
          boxShadow: 'none',
          borderRadius: '9999px'
        }
      }}
    />
  )
}
