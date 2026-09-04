import { matchesGlob } from 'node:path'
import { userError } from '../error.ts'
import { changedFiles, revParse } from '../git.ts'
import { requireBase } from '../run.ts'

export type ScopeCheckResult = {
  runId: string
  branch: string
  allow: string[]
  changed: string[]
}

/**
 * Enforce a task's write scope against what the worker actually touched.
 *
 * Workers are told their scope in the dispatch packet, but a prompt is not an
 * enforcement mechanism. This is the check that makes "one primary writer per
 * lane" real, and it is why two tasks with overlapping scopes are rejected at
 * planning time.
 */
export function scopeCheck(
  repo: string,
  runId: string,
  branch: string,
  allow: string[],
): ScopeCheckResult {
  if (allow.length === 0) {
    throw userError('at least one --allow glob is required', { branch })
  }

  const baseSha = requireBase(repo, runId)
  const sha = revParse(repo, branch)
  const changed = changedFiles(repo, baseSha, sha)

  if (changed.length === 0) {
    throw userError(`branch ${branch} changed no files`, { branch, baseSha })
  }

  const outside = changed.filter((path) => !allow.some((glob) => matchesGlob(path, glob)))
  if (outside.length > 0) {
    throw userError(
      `${outside.length} file(s) changed outside the task write scope`,
      { branch, allow, outside },
    )
  }

  return { runId, branch, allow, changed }
}
