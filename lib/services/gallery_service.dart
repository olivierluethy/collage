import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// Reads device albums/photos and saves the finished collage back to the
/// gallery — all through photo_manager (no extra save plugin needed).
class GalleryService {
  const GalleryService();

  /// Albums that contain images, newest first ("Recent" style first entry).
  Future<List<AssetPathEntity>> albums() {
    return PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
  }

  Future<int> albumCount(AssetPathEntity album) => album.assetCountAsync;

  /// A page of assets from an album.
  Future<List<AssetEntity>> page(AssetPathEntity album, int page, {int size = 60}) {
    return album.getAssetListPaged(page: page, size: size);
  }

  /// A square-ish thumbnail for grid tiles.
  Future<Uint8List?> thumb(AssetEntity asset, {int px = 300}) {
    return asset.thumbnailDataWithSize(ThumbnailSize.square(px));
  }

  /// Full-resolution bytes for rendering into the collage / export.
  Future<Uint8List?> full(AssetEntity asset) => asset.originBytes;

  Future<AssetEntity?> byId(String id) => AssetEntity.fromId(id);

  double aspectOf(AssetEntity asset) {
    if (asset.height == 0) return 1;
    return asset.width / asset.height;
  }

  /// Save exported image bytes (PNG or JPG — the filename's extension tells the
  /// gallery which) to the gallery. Returns the created asset, or null on
  /// failure.
  Future<AssetEntity?> saveImage(Uint8List bytes, {required String filename}) {
    return PhotoManager.editor.saveImage(bytes, filename: filename, title: filename);
  }
}
