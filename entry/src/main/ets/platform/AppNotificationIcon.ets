import { bundleManager } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { image } from '@kit.ImageKit';
import { DrawableDescriptor } from '@kit.ArkUI';
import { NotificationIconProvider, encodeWatchIcon, validateIconSize, iconBytesPerPixel } from '../core/WatchIcon';

// Created only for the currently authorized notification source. No installed-app enumeration or disk cache.
export class AppNotificationIcon implements NotificationIconProvider {
  private resources: resourceManager.ResourceManager;
  private bundleName: string;
  constructor(resources: resourceManager.ResourceManager, bundleName: string) { this.resources = resources; this.bundleName = bundleName; }
  async load(side: number, format: number): Promise<Uint8Array | undefined> {
    let descriptor: DrawableDescriptor | undefined = undefined;
    let pixel: image.PixelMap | undefined = undefined;
    let raw = new Uint8Array();
    try {
      validateIconSize(side); iconBytesPerPixel(format);
      const bundle = bundleManager.getBundleInfoSync(this.bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const app = bundle.appInfo;
      if (!app || !app.iconResource || app.iconResource.id <= 0) return undefined;
      // The resource overload also handles HarmonyOS layered/adaptive icons.
      const resource: Resource = { id: app.iconResource.id, type: 20000, params: [], bundleName: this.bundleName,
        moduleName: app.iconResource.moduleName };
      descriptor = this.resources.getDrawableDescriptor(resource);
      pixel = descriptor.getPixelMap();
      if (!pixel) return undefined;
      const info = pixel.getImageInfoSync(); const width = info.size.width; const height = info.size.height;
      if (width < 1 || height < 1 || width > 1024 || height > 1024) return undefined;
      raw = new Uint8Array(width * height * 4);
      // This API returns BGRA with the explicitly requested packed row stride.
      pixel.readPixelsToAreaSync({ pixels: raw.buffer, offset: 0, stride: width * 4,
        region: { x: 0, y: 0, size: { width: width, height: height } } });
      return encodeWatchIcon(raw, width, height, side, format, info.alphaType === image.AlphaType.PREMUL);
    } catch (_) { return undefined; }
    finally {
      raw.fill(0);
      if (pixel) { try { await pixel.release(); } catch (_) { } }
      if (descriptor) { try { descriptor.release(); } catch (_) { } }
    }
  }
}
