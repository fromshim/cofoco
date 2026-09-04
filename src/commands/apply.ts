import { userError } from '../error.ts'
import { deleteRef, dirtyPaths, git, isAncestor, revParse, tryRevParse, updateRef } from '../git.ts'
import { archiveRef, integrationRef } from '../refs.ts'
import { listStaged, requireBase } from '../run.ts'

export type ApplyResult = {
  runId: string
  base: string
  from: string
  to: string
  archived: string[]
}

/**
 * Move the base branch onto the reviewed integration candidate.
 *
 * This is the only command that touches a branch the user works on, so every
 * precondition is checked before the merge: the candidate exists, HEAD is on the
 * base branch, the base has not moved since preview, the tree is clean, and the
 * result is a genuine fast-forward. A base that drifted is a hard stop rather
 * than a re-plan, because the preview the user approved no longer describes what
 * would land.
 */
export function apply(repo: string, runId: string, base: string): ApplyResult {
  const baseSha = requireBase(repo, runId)

  const head = tryRevParse(repo, integrationRef(runId))
  if (head === null) {
    throw userError(`run ${runId} has no integration candidate; run "omija preview" first`, { runId })
  }

  const branch = git(repo, ['rev-parse', '--abbrev-ref', 'HEAD'])
  if (branch !== base) {
    throw userError(`HEAD is on ${branch}; check out ${base} before applying`, { branch, base })
  }

  const current = revParse(repo, base)
  if (current !== baseSha) {
    throw userError(
      `${base} moved from ${baseSha.slice(0, 12)} to ${current.slice(0, 12)} since preview; ` +
        `re-run "omija preview"`,
      { base, expected: baseSha, actual: current },
    )
  }

  const dirty = dirtyPaths(repo)
  if (dirty.length > 0) {
    throw userError(`working tree has ${dirty.length} uncommitted change(s)`, { dirty })
  }

  if (!isAncestor(repo, baseSha, head)) {
    throw userError(`integration candidate is not a fast-forward from ${base}`, { base, head })
  }

  git(repo, ['merge', '--ff-only', head])

  const staged = listStaged(repo, runId)
  for (const task of staged) {
    updateRef(repo, archiveRef(runId, task.taskId), task.sha)
    deleteRef(repo, task.ref)
  }
  deleteRef(repo, integrationRef(runId))

  return { runId, base, from: baseSha, to: head, archived: staged.map((t) => t.taskId) }
}
