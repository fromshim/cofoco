import { spawnSync } from 'node:child_process'
import { isAbsolute, resolve } from 'node:path'
import { internalError, userError } from './error.ts'

/**
 * Safety invariant from the architecture doc: print the exact command before any
 * git operation that can change refs or working trees. Everything here goes to
 * stderr so stdout stays machine-readable.
 */
const DESTRUCTIVE = new Set([
  'update-ref', 'branch', 'checkout', 'switch', 'reset', 'rebase',
  'merge', 'cherry-pick', 'worktree', 'push', 'gc', 'prune',
])

export type GitResult = {
  ok: boolean
  code: number
  stdout: string
  stderr: string
}

export function gitTry(repo: string, args: string[]): GitResult {
  const head = args[0]
  if (head !== undefined && DESTRUCTIVE.has(head)) {
    process.stderr.write(`  git ${args.join(' ')}\n`)
  }
  const r = spawnSync('git', ['-C', repo, ...args], { encoding: 'utf8' })
  if (r.error) {
    throw internalError(`could not run git: ${r.error.message}`, { args })
  }
  return {
    ok: r.status === 0,
    code: r.status ?? 3,
    stdout: (r.stdout ?? '').trim(),
    stderr: (r.stderr ?? '').trim(),
  }
}

/** Run git and return trimmed stdout. Throws when git exits non-zero. */
export function git(repo: string, args: string[]): string {
  const r = gitTry(repo, args)
  if (!r.ok) {
    throw internalError(`git ${args.join(' ')} failed: ${r.stderr || r.stdout}`, { args })
  }
  return r.stdout
}

export function isRepo(repo: string): boolean {
  return gitTry(repo, ['rev-parse', '--git-dir']).ok
}

/** Shared git directory, so every worktree of a repo resolves to the same path. */
export function commonDir(repo: string): string {
  const raw = git(repo, ['rev-parse', '--git-common-dir'])
  return isAbsolute(raw) ? raw : resolve(repo, raw)
}

export function revParse(repo: string, ref: string): string {
  const r = gitTry(repo, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`])
  if (!r.ok || r.stdout === '') {
    throw userError(`cannot resolve ref ${JSON.stringify(ref)}`, { ref })
  }
  return r.stdout
}

export function tryRevParse(repo: string, ref: string): string | null {
  const r = gitTry(repo, ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`])
  return r.ok && r.stdout !== '' ? r.stdout : null
}

/** Paths with uncommitted changes, including untracked files. */
export function dirtyPaths(repo: string): string[] {
  const out = git(repo, ['status', '--porcelain=v1', '--untracked-files=normal'])
  if (out === '') return []
  return out.split('\n').map((line) => line.slice(3).trim()).filter((p) => p !== '')
}

export function changedFiles(repo: string, from: string, to: string): string[] {
  const out = git(repo, ['diff', '--name-only', `${from}...${to}`])
  return out === '' ? [] : out.split('\n')
}

export type Commit = { sha: string; subject: string }

/** Commits reachable from `to` but not from `from`, oldest first. */
export function commitsBetween(repo: string, from: string, to: string): Commit[] {
  const out = git(repo, ['log', '--reverse', '--format=%H%x00%s', `${from}..${to}`])
  if (out === '') return []
  return out.split('\n').map((line) => {
    const [sha = '', subject = ''] = line.split('\0')
    return { sha, subject }
  })
}

export function updateRef(repo: string, ref: string, sha: string): void {
  git(repo, ['update-ref', ref, sha])
}

export function deleteRef(repo: string, ref: string): void {
  if (tryRevParse(repo, ref) !== null) {
    git(repo, ['update-ref', '-d', ref])
  }
}

/** True when `ancestor` is reachable from `descendant`, i.e. a fast-forward is possible. */
export function isAncestor(repo: string, ancestor: string, descendant: string): boolean {
  return gitTry(repo, ['merge-base', '--is-ancestor', ancestor, descendant]).ok
}
