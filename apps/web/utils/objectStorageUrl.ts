export function objectStorageUploadUrl(presignedUrl: string, objectStorageOrigin?: string) {
  if (!objectStorageOrigin) return presignedUrl

  const uploadUrl = new URL(presignedUrl)
  const configuredOrigin = new URL(objectStorageOrigin)

  uploadUrl.protocol = configuredOrigin.protocol
  uploadUrl.host = configuredOrigin.host

  return uploadUrl.toString()
}
