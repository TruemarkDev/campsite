/* eslint-disable @next/next/no-img-element */
/* eslint-disable jsx-a11y/alt-text */
import { ImageResponse } from 'next/og'
import { DEFAULT_SEO } from '@campsite/config'

export const runtime = 'nodejs'

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)

  const title = searchParams.get('title') || DEFAULT_SEO.title
  const org = searchParams.get('org') || 'Campsite'
  const orgAvatar =
    searchParams.get('orgAvatar') ||
    'https://campsite.imgix.net/o/cl3gijjgd001/a/99693eed-1e95-47ff-b68a-42e298182f40.png?fit=crop&h=56&w=56'

  return new ImageResponse(
    (
      <div
        style={{
          height: '100%',
          width: '100%',
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'center',
          flexDirection: 'column',
          flexWrap: 'nowrap',
          backgroundColor: 'white',
          background: 'radial-gradient(circle at 80% 50%, rgba(0,0,0,0.05) 0%, transparent 60%)'
        }}
      >
        <div
          style={{
            height: '100%',
            width: '100%',
            display: 'flex',
            alignItems: 'flex-start',
            justifyContent: 'center',
            flexDirection: 'column',
            flexWrap: 'nowrap',
            padding: '64px'
          }}
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexDirection: 'row',
              fontSize: 32,
              fontWeight: 500,
              lineHeight: '56px',
              color: 'black'
            }}
          >
            <img
              src={orgAvatar}
              width='56'
              height='56'
              style={{
                borderRadius: '8px',
                marginRight: '20px'
              }}
            />
            <strong>{org}</strong>
          </div>
          <div
            style={{
              display: 'flex',
              fontSize: 56,
              fontWeight: 700,
              color: 'black',
              lineHeight: '1.2em',
              maxHeight: '3.6em',
              overflow: 'hidden',
              marginTop: '32px'
            }}
          >
            <strong>{title}</strong>
          </div>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630
    }
  )
}
