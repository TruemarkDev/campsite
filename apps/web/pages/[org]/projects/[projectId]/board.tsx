import { Fragment, useEffect } from 'react'
import Head from 'next/head'
import { useRouter } from 'next/router'

import { ApiError } from '@campsite/types'

import { FullPageLoading } from '@/components/FullPageLoading'
import { AppLayout } from '@/components/Layout/AppLayout'
import { Project404 } from '@/components/Projects/Project404'
import { ProjectView } from '@/components/Projects/ProjectView'
import AuthAppProviders from '@/components/Providers/AuthAppProviders'
import { useScope } from '@/contexts/scope'
import { useGetProject } from '@/hooks/useGetProject'
import { useGetProjectBeadsBoard } from '@/hooks/useGetProjectBeadsBoard'
import { useGetProjectId } from '@/hooks/useGetProjectId'
import { PageWithLayout } from '@/utils/types'

const ProjectBoardPage: PageWithLayout<any> = () => {
  const router = useRouter()
  const { scope } = useScope()
  const projectId = useGetProjectId()
  const getProject = useGetProject({ id: projectId })
  const getBoard = useGetProjectBeadsBoard({ projectId: `${projectId}`, enabled: !!projectId })
  const boardIsUnavailable = getBoard.error instanceof ApiError && [403, 404].includes(getBoard.error.status)

  useEffect(() => {
    if (projectId && boardIsUnavailable) router.replace(`/${scope}/projects/${projectId}`)
  }, [boardIsUnavailable, projectId, router, scope])

  if (!projectId || getProject.isLoading || getBoard.isLoading || boardIsUnavailable) return <FullPageLoading />
  if (getProject.isError || !getProject.data) return <Project404 />

  const project = getProject.data

  return (
    <Fragment key={project.id}>
      <Head>
        <title>Board · {project.name}</title>
        {project.description && <meta name='description' content={project.description} />}
      </Head>

      <ProjectView project={project} />
    </Fragment>
  )
}

ProjectBoardPage.getProviders = (page, pageProps) => {
  return (
    <AuthAppProviders {...pageProps}>
      <AppLayout {...pageProps}>{page}</AppLayout>
    </AuthAppProviders>
  )
}

export default ProjectBoardPage
