/**
 * Exit codes are part of the CLI contract. The orchestration skill branches on
 * them, so they must stay stable.
 *
 *   0  success
 *   1  the user (or a worker) has to fix something
 *   2  integration conflict
 *   3  internal failure
 */
export type ExitCode = 0 | 1 | 2 | 3

export class OmijaError extends Error {
  readonly code: ExitCode
  readonly detail: Record<string, unknown>

  constructor(message: string, code: ExitCode, detail: Record<string, unknown> = {}) {
    super(message)
    this.name = 'OmijaError'
    this.code = code
    this.detail = detail
  }
}

/** The user has to fix something before this command can succeed. */
export function userError(message: string, detail?: Record<string, unknown>): OmijaError {
  return new OmijaError(message, 1, detail)
}

/** Integration could not be assembled because of a conflict. */
export function conflictError(message: string, detail?: Record<string, unknown>): OmijaError {
  return new OmijaError(message, 2, detail)
}

/** Something we did not anticipate. Bug in omija or a broken repository. */
export function internalError(message: string, detail?: Record<string, unknown>): OmijaError {
  return new OmijaError(message, 3, detail)
}
