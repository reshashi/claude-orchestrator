/**
 * GitHub Integration
 *
 * Handles PR status checking, merging, and label management via `gh` CLI.
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import type { PrStatus, Logger } from './types.js';

const execFileAsync = promisify(execFile);

export interface GitHubOptions {
  repoOwner: string;
  repoName: string;
  logger: Logger;
}

export class GitHub {
  private readonly logger: Logger;
  private readonly repoFull: string;

  constructor(options: GitHubOptions) {
    this.logger = options.logger;
    this.repoFull = `${options.repoOwner}/${options.repoName}`;
  }

  /**
   * Execute a gh CLI command
   */
  private async gh(args: string[]): Promise<string> {
    try {
      const { stdout } = await execFileAsync('gh', args, {
        timeout: 30000,  // 30 second timeout
      });
      return stdout.trim();
    } catch (err) {
      const error = err as Error & { stderr?: string };
      this.logger.error(`gh command failed: ${args.join(' ')}`, {
        error: error.message,
        stderr: error.stderr,
      });
      throw err;
    }
  }

  /**
   * Get PR number for a branch
   */
  async getPrForBranch(branchName: string): Promise<number | null> {
    try {
      const output = await this.gh([
        'pr', 'list',
        '--repo', this.repoFull,
        '--head', branchName,
        '--state', 'open',
        '--json', 'number',
        '--jq', '.[0].number',
      ]);

      return output ? parseInt(output, 10) : null;
    } catch {
      return null;
    }
  }

  /**
   * Get detailed PR status
   */
  async getPrStatus(prNumber: number): Promise<PrStatus | null> {
    try {
      const output = await this.gh([
        'pr', 'view', String(prNumber),
        '--repo', this.repoFull,
        '--json', 'number,url,state,labels,additions,deletions',
      ]);

      const data = JSON.parse(output) as {
        number: number;
        url: string;
        state: string;
        labels: { name: string }[];
        additions: number;
        deletions: number;
      };

      // Get CI status separately
      const ciStatus = await this.getCiStatus(prNumber);

      return {
        number: data.number,
        url: data.url,
        state: data.state.toLowerCase() as 'open' | 'closed' | 'merged',
        ciStatus,
        labels: data.labels.map(l => l.name),
        additions: data.additions,
        deletions: data.deletions,
      };
    } catch {
      return null;
    }
  }

  /**
   * Get CI status for a PR
   */
  async getCiStatus(prNumber: number): Promise<'pending' | 'passed' | 'failed' | 'unknown'> {
    try {
      const output = await this.gh([
        'pr', 'checks', String(prNumber),
        '--repo', this.repoFull,
      ]);

      if (output.includes('fail') || output.includes('X')) {
        return 'failed';
      }
      if (output.includes('pending') || output.includes('*')) {
        return 'pending';
      }
      if (output.includes('pass') || output.includes('✓')) {
        return 'passed';
      }
      return 'unknown';
    } catch {
      return 'unknown';
    }
  }

  /**
   * Check if PR has specific label
   */
  async hasLabel(prNumber: number, label: string): Promise<boolean> {
    const status = await this.getPrStatus(prNumber);
    return status?.labels.includes(label) ?? false;
  }

  /**
   * Add label to PR
   */
  async addLabel(prNumber: number, label: string): Promise<void> {
    await this.gh([
      'pr', 'edit', String(prNumber),
      '--repo', this.repoFull,
      '--add-label', label,
    ]);

    this.logger.info(`Added label ${label} to PR #${prNumber}`);
  }

  /**
   * Remove label from PR
   */
  async removeLabel(prNumber: number, label: string): Promise<void> {
    try {
      await this.gh([
        'pr', 'edit', String(prNumber),
        '--repo', this.repoFull,
        '--remove-label', label,
      ]);

      this.logger.info(`Removed label ${label} from PR #${prNumber}`);
    } catch {
      // Label might not exist, that's fine
    }
  }

  /**
   * Merge a PR
   */
  async mergePr(
    prNumber: number,
    method: 'squash' | 'merge' | 'rebase' = 'squash',
    deleteBranch: boolean = true
  ): Promise<boolean> {
    try {
      const args = [
        'pr', 'merge', String(prNumber),
        '--repo', this.repoFull,
        `--${method}`,
      ];

      if (deleteBranch) {
        args.push('--delete-branch');
      }

      await this.gh(args);

      this.logger.info(`Merged PR #${prNumber}`, { method, deleteBranch });
      return true;
    } catch (err) {
      this.logger.error(`Failed to merge PR #${prNumber}`, { error: String(err) });
      return false;
    }
  }

  /**
   * Get files changed in a PR
   */
  async getPrFiles(prNumber: number): Promise<string[]> {
    try {
      const output = await this.gh([
        'pr', 'diff', String(prNumber),
        '--repo', this.repoFull,
        '--name-only',
      ]);

      return output.split('\n').filter(f => f.trim());
    } catch {
      return [];
    }
  }

  /**
   * Check if PR has infrastructure changes (needs devops review)
   */
  async needsDevopsReview(prNumber: number): Promise<boolean> {
    const files = await this.getPrFiles(prNumber);

    const infraPatterns = [
      /^\.github\//,
      /vercel\.json$/,
      /^supabase\//,
      /Dockerfile$/,
      /docker-compose/,
      /^\.env/,
      /middleware\.ts$/,
      /playwright\.config/,
    ];

    return files.some(file =>
      infraPatterns.some(pattern => pattern.test(file))
    );
  }

  /**
   * Check if PR is large enough for code-simplifier (50+ lines)
   */
  async needsCodeSimplifier(prNumber: number): Promise<boolean> {
    const status = await this.getPrStatus(prNumber);
    if (!status) return false;

    const totalChanges = status.additions + status.deletions;
    return totalChanges >= 50;
  }

  /**
   * Get current branch name from worktree
   */
  async getCurrentBranch(cwd: string): Promise<string | null> {
    try {
      const { stdout } = await execFileAsync('git', ['branch', '--show-current'], { cwd });
      return stdout.trim() || null;
    } catch {
      return null;
    }
  }

  /**
   * Get repository info from worktree
   */
  async getRepoInfo(cwd: string): Promise<{ owner: string; name: string } | null> {
    try {
      const { stdout } = await execFileAsync(
        'git',
        ['remote', 'get-url', 'origin'],
        { cwd }
      );

      // Parse GitHub URL: https://github.com/owner/repo.git or git@github.com:owner/repo.git
      const httpsMatch = stdout.match(/github\.com\/([^/]+)\/([^/\s]+)/);
      const sshMatch = stdout.match(/github\.com:([^/]+)\/([^/\s]+)/);

      const match = httpsMatch ?? sshMatch;
      if (match) {
        return {
          owner: match[1],
          name: match[2].replace(/\.git$/, ''),
        };
      }

      return null;
    } catch {
      return null;
    }
  }

  /**
   * Create GitHub instance from worktree path
   */
  static async fromWorktree(cwd: string, logger: Logger): Promise<GitHub | null> {
    try {
      const { stdout } = await execFileAsync(
        'git',
        ['remote', 'get-url', 'origin'],
        { cwd }
      );

      const httpsMatch = stdout.match(/github\.com\/([^/]+)\/([^/\s]+)/);
      const sshMatch = stdout.match(/github\.com:([^/]+)\/([^/\s]+)/);

      const match = httpsMatch ?? sshMatch;
      if (match) {
        return new GitHub({
          repoOwner: match[1],
          repoName: match[2].replace(/\.git$/, ''),
          logger,
        });
      }

      return null;
    } catch {
      return null;
    }
  }
}
