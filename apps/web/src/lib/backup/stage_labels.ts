import type { BackupProgress } from './backup_writer';
import type { RestoreProgress } from './restore_orchestrator';
import type { MessageKey } from '../i18n/messages';

/// Every stage either backup or restore can report. Typed off the two
/// progress unions rather than restated, so adding a stage to one of them
/// fails the map below to compile until it has a label.
export type TransferStage = BackupProgress['stage'] | RestoreProgress['stage'];

const STAGE_KEYS: Record<TransferStage, MessageKey> = {
	reading: 'settingsAccount.stageReading',
	profile: 'settingsAccount.stageProfile',
	runs: 'settingsAccount.stageRuns',
	tracks: 'settingsAccount.stageTracks',
	routes: 'settingsAccount.stageRoutes',
	writing: 'settingsAccount.stageWriting',
	done: 'settingsAccount.stageDone',
};

export function transferStageKey(stage: TransferStage): MessageKey {
	return STAGE_KEYS[stage];
}
