import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

export class MusicBackgroundTask {
  private running: boolean = false;
  private stopped: boolean = false;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async start(): Promise<void> {
    if (this.running) return;
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: 'com.xlennart.wristnotifications', abilityName: 'EntryAbility' }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 11, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    await backgroundTaskManager.startBackgroundRunning(this.context,
      backgroundTaskManager.BackgroundMode.BLUETOOTH_INTERACTION, agent);
    this.running = true;
    if (this.stopped) await this.stop();
  }
  async stop(): Promise<void> {
    this.stopped = true;
    if (!this.running) return;
    this.running = false;
    try { await backgroundTaskManager.stopBackgroundRunning(this.context); } catch (_) { }
  }
}
