import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Image upload for recipe content.
///
/// Every upload is compressed on the device first. A modern phone camera
/// produces 4–8MB per photo; a feed card shows it at 400px and a detail screen
/// at 800px, so uploading the original is bandwidth nobody sees — and bandwidth
/// is the cost centre for this app, not storage.
///
/// 1440px at quality 80 is the compromise the plan calls for: still sharp when
/// a step photo is pinched open, roughly 250KB on the wire.
class MediaRepository {
  MediaRepository({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const _longestEdge = 1440;
  static const _quality = 80;

  Future<String> uploadRecipeImage({
    required String recipeId,
    required String filePath,
    required String slot,
  }) => _upload(path: 'recipes/$recipeId/$slot.jpg', filePath: filePath);

  Future<String> uploadPlanImage({
    required String planId,
    required String filePath,
    required String slot,
  }) => _upload(path: 'plans/$planId/$slot.jpg', filePath: filePath);

  Future<void> deleteRecipeImage({
    required String recipeId,
    required String slot,
  }) async {
    try {
      await _storage.ref('recipes/$recipeId/$slot.jpg').delete();
    } on FirebaseException {
      // Already gone. The document field is the source of truth.
    }
  }

  Future<String> _upload({required String path, required String filePath}) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      filePath,
      minWidth: _longestEdge,
      minHeight: _longestEdge,
      quality: _quality,
      format: CompressFormat.jpeg,
      // Phone cameras record orientation in EXIF rather than in the pixels.
      // Without this, a photo taken in portrait arrives sideways.
      autoCorrectionAngle: true,
    );
    if (compressed == null) {
      throw StateError('Could not read the selected image');
    }

    final ref = _storage.ref(path);
    await ref.putData(
      Uint8List.fromList(compressed),
      SettableMetadata(
        contentType: 'image/jpeg',
        // Recipe images are immutable once uploaded — a replacement gets a new
        // slot — so they can be cached hard.
        cacheControl: 'public, max-age=604800',
      ),
    );
    return ref.getDownloadURL();
  }
}
