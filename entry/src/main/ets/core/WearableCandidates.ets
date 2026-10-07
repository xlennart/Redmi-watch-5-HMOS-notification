// Bluetooth wrist-watch class, or a name suggesting a watch/fitness band.
// HFP watches may report an audio class, so class alone is not sufficient.
export function isWristWearableCandidate(name: string, majorMinorClass: number = 0): boolean {
  if (majorMinorClass === 0x0704) return true;
  const label = name.trim().toLowerCase();
  if (/earbuds|freebuds|airpods|buds|headphones|headset|耳机|眼镜|glasses|helmet/.test(label)) return false;
  if (/watch|band|手表|手环|腕表|腕带|bracelet/.test(label)) return true;
  return /amazfit\s+(gtr|gts|bip|t-rex|active|balance|cheetah|falcon)|fitbit|galaxy\s+fit|gear\s+s[23]|polar\s+(pacer|vantage|grit)|suunto\s+(race|vertical|[3579])/.test(label);
}
