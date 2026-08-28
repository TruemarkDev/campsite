import { useQuery } from '@tanstack/react-query'

import { IS_PRODUCTION } from '@campsite/config'

export function useHasLatestBuild() {
  const clientBuildId = process.env.NEXT_PUBLIC_RELEASE_SHA
  const getServerBuildId = useQuery<{ buildId: string }>({
    queryKey: ['server-build-id'],
    queryFn: () => fetch('/api/build-id').then((res) => res.json() as Promise<{ buildId: string }>),
    /*
    Refetch when the window is focused so that we aren't fetching in the background,
    and if the buildId has changed on the server in the meantime, the user will see
    the upgrade prompt as they come into the app.
    */
    refetchOnWindowFocus: true,
    staleTime: 1000 * 60 * 60, // 1 hour
    enabled: IS_PRODUCTION // dev is always latest
  })
  const serverBuildId = getServerBuildId.data?.buildId
  const isLatestBuild = serverBuildId === clientBuildId

  return !IS_PRODUCTION || isLatestBuild
}
