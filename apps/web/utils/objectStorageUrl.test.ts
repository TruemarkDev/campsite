import { describe, expect, it } from 'vitest'

import { objectStorageUploadUrl } from './objectStorageUrl'

describe('objectStorageUploadUrl', () => {
  it('uses the private Garage origin while preserving the signed bucket path', () => {
    expect(objectStorageUploadUrl('https://camp-objects.polo-apps.com/campsite-media', 'https://s3.camp.home')).toBe(
      'https://s3.camp.home/campsite-media'
    )
  })

  it('keeps the public Garage origin for the public build', () => {
    expect(objectStorageUploadUrl('https://garage.internal/campsite-media', 'https://camp-objects.polo-apps.com')).toBe(
      'https://camp-objects.polo-apps.com/campsite-media'
    )
  })

  it('keeps the presigned URL when no deployment override is configured', () => {
    const presignedUrl = 'https://garage.internal/campsite-media'

    expect(objectStorageUploadUrl(presignedUrl)).toBe(presignedUrl)
  })
})
