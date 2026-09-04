import { existsSync, rmSync } from 'node:fs'
import { join, sep } from 'node:path'
import { conflictError, internalError, userError } from '../error.ts'
import {
  type Commit,
  commitsBetween,
  commonDir,
  git,
  gitTry,
  tryRevParse,
  updateRef,
} from '../git.ts'
import { integrationRef, stagingRef } from '../refs.ts'
import { requireBase } from '../run.ts'

export type PreviewStep = {
  taskId: string
  stagedSha: string
  commits: Commit[]
}

export type PreviewResult = {
  runId: string
  baseSha: string
  head: string
  order: string[]
  steps: PreviewStep[]
  graph: string
}

/**
 * Build the candidate history for a run in a throwaway worktree.
 *
 * Nothing the user can see moves: the real task branches are only read, and the
 * rebase happens in a detached worktree under the git common directory that is
 * removed again before this function returns. Only `refs/omija/integration/<run>`
 * survives, which is what apply later fast-forwards onto.
 */
export function preview(repo: string, runId: string, order: string[]): PreviewResult {
  const baseSha = requireBase(repo, runId)

  if (order.length === 0) {
    throw userError('--order needs at least one task id', { runId })
  }
  const seen = new Set<string>()
  for (const taskId of order) {
    if (seen.has(taskId)) {
      throw userError(`task ${taskId} appears twice in --order`, { order })
    }
    seen.add(taskId)
  }

  // Resolve every staging ref before touching the filesystem, so a typo fails
  // without leaving a worktree behind.
  const staged = order.map((taskId) => {
    const sha = tryRevParse(repo, stagingRef(runId, taskId))
    if (sha === null) {
      throw userError(`task ${taskId} is not staged; run "omija stage" first`, { runId, taskId })
    }
    return { taskId, sha }
  })

  const dir = join(commonDir(repo), 'omija', 'preview', runId)
  removePreviewWorktree(repo, dir)
  git(repo, ['worktree', 'add', '--detach', dir, baseSha])

  try {
    const steps: PreviewStep[] = []
    let head = baseSha

    for (const { taskId, sha } of staged) {
      // --committer-date-is-author-date keeps preview reproducible: replaying the
      // same staged commits twice yields the same SHAs, so re-previewing after a
      // repair is a real no-op when nothing changed.
      const r = gitTry(dir, [
        'rebase', '--committer-date-is-author-date', '--onto', head, baseSha, sha,
      ])
      if (!r.ok) {
        const files = conflictedFiles(dir)
        gitTry(dir, ['rebase', '--abort'])
        if (files.length === 0) {
          throw internalError(`rebase failed for task ${taskId}: ${r.stderr || r.stdout}`, {
            taskId,
          })
        }
        throw conflictError(
          `task ${taskId} conflicts with the tasks before it in --order`,
          { runId, taskId, files, appliedBefore: steps.map((s) => s.taskId) },
        )
      }

      const next = git(dir, ['rev-parse', 'HEAD'])
      steps.push({ taskId, stagedSha: sha, commits: commitsBetween(dir, head, next) })
      head = next
    }

    updateRef(repo, integrationRef(runId), head)
    const graph = git(repo, ['log', '--graph', '--oneline', '--no-decorate', `${baseSha}..${head}`])

    return { runId, baseSha, head, order, steps, graph }
  } finally {
    removePreviewWorktree(repo, dir)
  }
}

function conflictedFiles(dir: string): string[] {
  const out = gitTry(dir, ['diff', '--name-only', '--diff-filter=U'])
  return out.ok && out.stdout !== '' ? out.stdout.split('\n') : []
}

/**
 * Preview is idempotent, so the throwaway worktree is removed both before and
 * after a run. The path guard is deliberate: this is the only place omija
 * deletes a directory, and it must never be able to point at user work.
 */
function removePreviewWorktree(repo: string, dir: string): void {
  gitTry(repo, ['worktree', 'remove', '--force', dir])
  if (existsSync(dir)) {
    if (!dir.includes(`${sep}omija${sep}preview${sep}`)) {
      throw internalError(`refusing to remove ${dir}: not an omija preview worktree`, { dir })
    }
    rmSync(dir, { recursive: true, force: true })
  }
  gitTry(repo, ['worktree', 'prune'])
}
