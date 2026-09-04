import { userError } from './error.ts'
import { tryRevParse, git } from './git.ts'
import { baseRef, stagingRef } from './refs.ts'

/** The base SHA frozen by preflight. Every other command reads it from here. */
export function requireBase(repo: string, runId: string): string {
  const sha = tryRevParse(repo, baseRef(runId))
  if (sha === null) {
    throw userError(`run ${runId} has no base; run "omija preflight" first`, { runId })
  }
  return sha
}

export type StagedTask = { taskId: string; ref: string; sha: string }

/** Task ids currently staged for a run, in ref-name order. */
export function listStaged(repo: string, runId: string): StagedTask[] {
  const prefix = stagingRef(runId, 'x').slice(0, -1)
  const out = git(repo, ['for-each-ref', '--format=%(refname)%00%(objectname)', prefix])
  if (out === '') return []
  return out.split('\n').map((line) => {
    const [ref = '', sha = ''] = line.split('\0')
    return { taskId: ref.slice(prefix.length), ref, sha }
  })
}
