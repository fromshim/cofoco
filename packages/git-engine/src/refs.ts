import { userError } from './error.ts'

/**
 * Run and task ids end up inside git ref names, so they are a trust boundary.
 * A value like `../../heads/main` would let a caller overwrite an arbitrary ref.
 */
const ID = /^[a-z0-9][a-z0-9._-]*$/i

export function assertId(kind: 'run' | 'task', value: string): string {
  if (!ID.test(value) || value.includes('..') || value.endsWith('.lock')) {
    throw userError(
      `invalid ${kind} id ${JSON.stringify(value)}: expected ${ID.source}, no ".." and no ".lock" suffix`,
      { kind, value },
    )
  }
  return value
}

/** Frozen base SHA for a run. Written once by preflight. */
export function baseRef(runId: string): string {
  return `refs/omija/base/${assertId('run', runId)}`
}

/** Copy of a task branch head. The task branch itself is never rewritten. */
export function stagingRef(runId: string, taskId: string): string {
  return `refs/omija/staging/${assertId('run', runId)}/${assertId('task', taskId)}`
}

/** Candidate history for a run. Rebuilt from scratch on every preview. */
export function integrationRef(runId: string): string {
  return `refs/omija/integration/${assertId('run', runId)}`
}

/** Where staging refs move after a successful apply. */
export function archiveRef(runId: string, taskId: string): string {
  return `refs/omija/archive/${assertId('run', runId)}/${assertId('task', taskId)}`
}
