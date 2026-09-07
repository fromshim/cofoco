import { userError } from '../error.ts'
import { type Commit, commitsBetween, isAncestor, revParse, updateRef } from '../git.ts'
import { stagingRef } from '../refs.ts'
import { requireBase } from '../run.ts'

export type StageResult = {
  runId: string
  taskId: string
  branch: string
  sha: string
  commits: Commit[]
}

/**
 * Copy a task branch head into a staging ref.
 *
 * The copy is the whole point: integration rebases the staging ref, never the
 * branch the worker is still sitting on, so previewing can never rewrite work.
 */
export function stage(repo: string, runId: string, taskId: string, branch: string): StageResult {
  const baseSha = requireBase(repo, runId)
  const sha = revParse(repo, branch)

  if (!isAncestor(repo, baseSha, sha)) {
    throw userError(
      `branch ${branch} is not based on the run base ${baseSha.slice(0, 12)}`,
      { branch, baseSha, sha },
    )
  }

  const commits = commitsBetween(repo, baseSha, sha)
  if (commits.length === 0) {
    throw userError(`branch ${branch} has no commits on top of the run base`, { branch, baseSha })
  }

  updateRef(repo, stagingRef(runId, taskId), sha)
  return { runId, taskId, branch, sha, commits }
}
