import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'

/**
 * A throwaway git repository. Every test runs real git commands against one of
 * these, because the whole point of the integration engine is what git actually
 * does, not what we believe it does.
 */
export type Fixture = {
  path: string
  git: (...args: string[]) => string
  write: (file: string, content: string) => void
  commit: (message: string) => string
  branch: (name: string, from?: string) => void
  checkout: (ref: string) => void
  sha: (ref: string) => string
  cleanup: () => void
}

export function makeRepo(): Fixture {
  const path = mkdtempSync(join(tmpdir(), 'omija-test-'))

  const git = (...args: string[]): string =>
    execFileSync('git', ['-C', path, ...args], { encoding: 'utf8' }).trim()

  const write = (file: string, content: string): void => {
    const target = join(path, file)
    mkdirSync(dirname(target), { recursive: true })
    writeFileSync(target, content)
  }

  const commit = (message: string): string => {
    git('add', '-A')
    git('commit', '-m', message)
    return git('rev-parse', 'HEAD')
  }

  git('init', '--initial-branch=main')
  git('config', 'user.email', 'test@omija.local')
  git('config', 'user.name', 'Omija Test')
  git('config', 'commit.gpgsign', 'false')

  const fixture: Fixture = {
    path,
    git,
    write,
    commit,
    branch: (name, from = 'HEAD') => void git('branch', name, from),
    checkout: (ref) => void git('checkout', ref),
    sha: (ref) => git('rev-parse', ref),
    cleanup: () => rmSync(path, { recursive: true, force: true }),
  }

  write('README.md', '# fixture\n')
  commit('init')
  return fixture
}

/** Create a branch off `from` that adds one file, then return to the base branch. */
export function taskBranch(
  repo: Fixture,
  name: string,
  file: string,
  content: string,
  from = 'main',
): void {
  repo.git('checkout', '-b', name, from)
  repo.write(file, content)
  repo.commit(`feat: ${name}`)
  repo.checkout(from)
}
