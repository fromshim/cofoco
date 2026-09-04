import { userError } from '../error.ts'
import { dirtyPaths, revParse, tryRevParse, updateRef } from '../git.ts'
import { baseRef } from '../refs.ts'

export type PreflightResult = {
  runId: string
  base: string
  baseSha: string
}

/**
 * Freeze the base commit for a run.
 *
 * Two invariants land here: the working tree must be clean before any lane is
 * created, and a run's base is chosen exactly once. Everything downstream reads
 * the base from `refs/omija/base/<run-id>` rather than re-resolving the branch,
 * so the base cannot drift underneath a run.
 */
export function preflight(repo: string, runId: string, base: string): PreflightResult {
  const baseSha = revParse(repo, base)

  const dirty = dirtyPaths(repo)
  if (dirty.length > 0) {
    throw userError(
      `working tree has ${dirty.length} uncommitted change(s); commit or stash them yourself`,
      { dirty },
    )
  }

  const ref = baseRef(runId)
  const existing = tryRevParse(repo, ref)
  if (existing !== null && existing !== baseSha) {
    throw userError(
      `run ${runId} is already based on ${existing.slice(0, 12)}, not ${baseSha.slice(0, 12)}; ` +
        `use a new run id`,
      { runId, existing, requested: baseSha },
    )
  }

  updateRef(repo, ref, baseSha)
  return { runId, base, baseSha }
}
