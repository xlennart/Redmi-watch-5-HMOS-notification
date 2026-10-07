import { bundleManager } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { image } from '@kit.ImageKit';
import { DrawableDescriptor } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationIconProvider, encodeWatchIcon, validateIconSize, iconBytesPerPixel } from '../core/WatchIcon';

// Created only for the currently authorized notification source. No installed-app enumeration or disk cache.
export class AppNotificationIcon implements NotificationIconProvider {
  reason: string = '';
  private resources: resourceManager.ResourceManager;
  private bundleName: string;
  constructor(resources: resourceManager.ResourceManager, bundleName: string) { this.resources = resources; this.bundleName = bundleName; }
  async load(side: number, format: number): Promise<Uint8Array | undefined> {
    let descriptor: DrawableDescriptor | undefined = undefined;
    let pixel: image.PixelMap | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let square: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let raw = new Uint8Array();
    let squareBytes = new Uint8Array();
    let mediaBytes = new Uint8Array();
    try {
      this.reason = 'dimensions'; validateIconSize(side); if (format !== 6) iconBytesPerPixel(format);
      this.reason = 'bundle';
      const bundle = bundleManager.getBundleInfoSync(this.bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const app = bundle.appInfo;
      if (!app || !app.iconResource || app.iconResource.id <= 0) { this.reason = 'icon_resource_missing'; return undefined; }
      // The resource overload also handles HarmonyOS layered/adaptive icons.
      const resource: Resource = { id: app.iconResource.id, type: 20000, params: [], bundleName: this.bundleName,
        moduleName: app.iconResource.moduleName };
      this.reason = 'drawable';
      try { descriptor = this.resources.getDrawableDescriptor(resource); pixel = descriptor.getPixelMap(); } catch (_) { }
      if (!pixel) {
        this.reason = 'media';
        mediaBytes = await this.resources.getMediaContent(resource);
        if (mediaBytes.length < 1 || mediaBytes.length > 2097152) { this.reason = 'media_size'; return undefined; }
        source = image.createImageSource(mediaBytes.buffer);
        const sourceInfo = await source.getImageInfo(0);
        if (sourceInfo.size.width < 1 || sourceInfo.size.height < 1 || sourceInfo.size.width > 1024 || sourceInfo.size.height > 1024) {
          this.reason = 'media_dimensions'; return undefined;
        }
        pixel = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.BGRA_8888 });
      }
      this.reason = 'pixels';
      const info = pixel.getImageInfoSync(); const width = info.size.width; const height = info.size.height;
      if (width < 1 || height < 1 || width > 1024 || height > 1024) { this.reason = 'pixel_size'; return undefined; }
      raw = new Uint8Array(width * height * 4);
      // This API returns BGRA with the explicitly requested packed row stride.
      pixel.readPixelsToAreaSync({ pixels: raw.buffer, offset: 0, stride: width * 4,
        region: { x: 0, y: 0, size: { width: width, height: height } } });
      if (format !== 6) { this.reason = 'encoded'; return encodeWatchIcon(raw, width, height, side, format, info.alphaType === image.AlphaType.PREMUL); }
      this.reason = 'png';
      squareBytes = encodeWatchIcon(raw, width, height, side, 3, info.alphaType === image.AlphaType.PREMUL);
      square = await image.createPixelMap(squareBytes.buffer, { size: { width: side, height: side },
        srcPixelFormat: image.PixelMapFormat.BGRA_8888, pixelFormat: image.PixelMapFormat.BGRA_8888, alphaType: image.AlphaType.UNPREMUL });
      packer = image.createImagePacker();
      const packed = new Uint8Array(await packer.packToData(square, { format: 'image/png', quality: 100 }));
      if (packed.length > 65536) { packed.fill(0); this.reason = 'png_size'; return undefined; }
      this.reason = 'encoded'; return packed;
    } catch (error) { const code = (error as BusinessError).code; this.reason += code ? '_' + code : '_failed'; return undefined; }
    finally {
      raw.fill(0); squareBytes.fill(0); mediaBytes.fill(0);
      if (square) { try { await square.release(); } catch (_) { } }
      if (packer) { try { await packer.release(); } catch (_) { } }
      if (source) { try { await source.release(); } catch (_) { } }
      if (pixel) { try { await pixel.release(); } catch (_) { } }
      if (descriptor) { try { descriptor.release(); } catch (_) { } }
    }
  }
}
