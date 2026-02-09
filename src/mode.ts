/**
 * Mode detection for the Node.js orchestrator layer.
 * Mirrors scripts/mode-detect.sh for TypeScript consumers.
 */

export type OrchestratorMode = 'agent-teams' | 'legacy';

export function detectMode(): OrchestratorMode {
  if (process.env.ORCHESTRATOR_MODE === 'agent-teams' || process.env.ORCHESTRATOR_MODE === 'legacy') {
    return process.env.ORCHESTRATOR_MODE;
  }
  if (process.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) {
    return 'agent-teams';
  }
  return 'legacy';
}

export function isAgentTeams(): boolean {
  return detectMode() === 'agent-teams';
}

export function isLegacyMode(): boolean {
  return detectMode() === 'legacy';
}
