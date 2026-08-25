import { InfiniteData } from '@tanstack/react-query'

interface Identifiable {
  id: string
}
interface DataPage<T> {
  data: T[]
}

export function flattenInfiniteData<T extends Identifiable>(data?: InfiniteData<DataPage<T>>) {
  const ids = new Set()

  return data?.pages
    .map((page) => page.data)
    .flat(2)
    .filter((obj) => {
      if (ids.has(obj.id)) {
        return false
      } else {
        ids.add(obj.id)
        return true
      }
    })
}
